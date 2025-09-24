import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // CRITICAL FIX: Import for RootIsolateToken
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/processing/services/processing_worker.dart';

/// A generic request waiting in the queue.
class _TaskRequest {
  final TaskType taskType;
  final dynamic payload;
  final Completer<ProcessingResponse> completer;

  _TaskRequest(this.taskType, this.payload, this.completer);
}

/// Manages a pool of long-lived isolates for high-performance, parallel processing.
class ProcessingIsolatePoolService {
  final _idleWorkers = Queue<SendPort>();
  final _taskQueue = Queue<_TaskRequest>();
  final Completer<void> _poolReadyCompleter = Completer();
  final List<Isolate> _allIsolates = [];

  bool _isDisposed = false;

  /// Initializes the isolate pool on creation.
  ProcessingIsolatePoolService() {
    _init();
  }

  /// Warms up all worker isolates by processing a dummy image for OCR.
  /// This forces the ML Kit models to be fully loaded and ready.
  Future<void> warmUp() async {
    await _poolReadyCompleter.future;

    final tempDir = await getTemporaryDirectory();
    final dummyImagePath = path.join(tempDir.path, 'warmup.png');
    final dummyImage = img.Image(width: 32, height: 32);
    await File(dummyImagePath).writeAsBytes(img.encodePng(dummyImage));

    final warmupFutures = _allIsolates.map((_) => processOcr(dummyImagePath)).toList();
    
    try {
      await Future.wait(warmupFutures);
    } catch (e) {
      // Log warm-up failure as it might be important
      debugPrint('[ProcessingPool] Warm-up failed: $e');
    } finally {
      await File(dummyImagePath).delete();
    }
  }

  Future<void> _init() async {
    final numWorkers = max(1, min(4, Platform.numberOfProcessors - 1));

    // [CRITICAL FIX] Get the token from the root isolate.
    final rootToken = RootIsolateToken.instance;
    if (rootToken == null) {
      _poolReadyCompleter.completeError('Cannot get RootIsolateToken.');
      return;
    }

    for (int i = 0; i < numWorkers; i++) {
      final mainReceivePort = ReceivePort();
      try {
        // [CRITICAL FIX] Pass a map containing the port and the token to the isolate.
        final isolate = await Isolate.spawn(
          processingWorkerEntryPoint,
          {'port': mainReceivePort.sendPort, 'token': rootToken},
        );
        _allIsolates.add(isolate);
        
        final workerSendPort = await mainReceivePort.first as SendPort;
        _idleWorkers.add(workerSendPort);
      } catch (e) {
        debugPrint('[ProcessingPool] Failed to spawn worker isolate: $e');
      }
    }

    if (_idleWorkers.isNotEmpty) {
      _poolReadyCompleter.complete();
    } else {
      _poolReadyCompleter.completeError('Failed to initialize any workers.');
    }
  }

  /// Submits an image for OCR processing.
  Future<ProcessingResponse> processOcr(String imagePath) async {
    return _submitTask(TaskType.ocr, imagePath);
  }

  /// Submits a payload for image composition.
  Future<ProcessingResponse> processComposition(CompositionPayload payload) async {
    return _submitTask(TaskType.composition, payload);
  }

  Future<ProcessingResponse> _submitTask(TaskType type, dynamic payload) async {
    await _poolReadyCompleter.future;
    if (_isDisposed) {
      throw Exception('ProcessingIsolatePoolService has been disposed.');
    }
    final completer = Completer<ProcessingResponse>();
    _taskQueue.add(_TaskRequest(type, payload, completer));
    _dispatch();
    return completer.future;
  }

  void _dispatch() {
    while (!_isDisposed && _idleWorkers.isNotEmpty && _taskQueue.isNotEmpty) {
      final workerPort = _idleWorkers.removeFirst();
      final task = _taskQueue.removeFirst();

      final responsePort = ReceivePort();
      final requestForWorker = ProcessingRequest(responsePort.sendPort, task.taskType, task.payload);
      
      workerPort.send(requestForWorker);

      responsePort.first.then((response) {
        if (response is ProcessingResponse) {
          task.completer.complete(response);
        } else {
          task.completer.completeError(ProcessingResponse.failure('Unknown or invalid response from isolate'));
        }
      }).whenComplete(() {
        if (!_isDisposed) {
          _idleWorkers.add(workerPort);
          _dispatch();
        }
      });
    }
  }

  /// Kills all isolates and cleans up resources.
  void dispose() {
    _isDisposed = true;
    for (final isolate in _allIsolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _allIsolates.clear();
    _idleWorkers.clear();
  }
}

/// Riverpod provider for the ProcessingIsolatePoolService singleton.
final processingIsolatePoolProvider = Provider<ProcessingIsolatePoolService>((ref) {
  final service = ProcessingIsolatePoolService();
  ref.onDispose(service.dispose);
  return service;
});