import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
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
  final List<SendPort> _allWorkerPorts = [];

  bool _isDisposed = false;
  bool _isInitialized = false;
  bool _isInitializing = false;

  /// Creates the service but delays initialization until needed.
  ProcessingIsolatePoolService();

  /// Ensures the pool is initialized before use.
  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    
    if (_isInitializing) {
      await _poolReadyCompleter.future;
      return;
    }
    
    _isInitializing = true;
    await _init();
  }

  /// Warms up all worker isolates in the background.
  /// This is completely asynchronous and won't block the main thread.
  void warmUpAsync() {
    // Don't wait for this - let it run in background
    _warmUpInBackground();
  }

  Future<void> _warmUpInBackground() async {
    try {
      await _ensureInitialized();
      
      final tempDir = await getTemporaryDirectory();
      final dummyImagePath = path.join(tempDir.path, 'warmup.png');
      final dummyImage = img.Image(width: 32, height: 32);
      await File(dummyImagePath).writeAsBytes(img.encodePng(dummyImage));

      final warmupFutures = _allIsolates.map((_) async {
        try {
          final decodeResponse = await dispatch(TaskType.decode, dummyImagePath);
          if (decodeResponse.isSuccess) {
            final ocrPayload = OcrPayload(imageBytes: decodeResponse.data, imagePath: dummyImagePath);
            await dispatch(TaskType.ocr, ocrPayload);
          }
        } catch (e) {
          // Individual warmup failures are not critical.
        }
      }).toList();
      
      await Future.wait(warmupFutures);
      await File(dummyImagePath).delete();
    } catch (e) {
      // Top-level warmup failure is not critical.
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
        _allWorkerPorts.add(workerSendPort);
        _idleWorkers.add(workerSendPort);
      } catch (e) {
        // Failed to spawn an isolate, will proceed with fewer workers.
      }
    }

    if (_idleWorkers.isNotEmpty) {
      _isInitialized = true;
      _poolReadyCompleter.complete();
    } else {
      _poolReadyCompleter.completeError('Failed to initialize any workers.');
    }
  }

  /// Submits a task to the isolate pool.
  Future<ProcessingResponse> dispatch(TaskType type, dynamic payload) async {
    await _ensureInitialized();
    if (_isDisposed) {
      throw Exception('ProcessingIsolatePoolService has been disposed.');
    }
    final completer = Completer<ProcessingResponse>();
    _taskQueue.add(_TaskRequest(type, payload, completer));
    _dispatch();
    return completer.future;
  }

  /// Submits a task to ALL worker isolates. Useful for initialization.
  Future<void> broadcast(TaskType type, dynamic payload) async {
    await _ensureInitialized();
    if (_isDisposed) {
      throw Exception('ProcessingIsolatePoolService has been disposed.');
    }

    final broadcastFutures = _allWorkerPorts.map((workerPort) {
      final completer = Completer<ProcessingResponse>();
      final responsePort = ReceivePort();
      final requestForWorker = ProcessingRequest(responsePort.sendPort, type, payload);
      
      workerPort.send(requestForWorker);

      responsePort.first.then((response) {
        if (response is ProcessingResponse && response.isSuccess) {
          completer.complete(response);
        } else {
          final error = response is ProcessingResponse ? response.error : 'Unknown broadcast error';
          completer.completeError(ProcessingResponse.failure(error));
        }
      });
      return completer.future;
    });

    await Future.wait(broadcastFutures);
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
    _allWorkerPorts.clear();
  }
}

/// Riverpod provider for the ProcessingIsolatePoolService singleton.
final processingIsolatePoolProvider = Provider<ProcessingIsolatePoolService>((ref) {
  final service = ProcessingIsolatePoolService();
  ref.onDispose(service.dispose);
  return service;
});