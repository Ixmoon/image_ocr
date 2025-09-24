import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_ocr/features/processing/services/ocr_isolate_service.dart';

// This service now acts as a coordinator for the persistent OCR isolate.
class OcrService {
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final Completer<void> _isolateReadyCompleter = Completer();

  OcrService() {
    _initIsolate();
  }

  Future<void> _initIsolate() async {
    final mainReceivePort = ReceivePort();
    final token = RootIsolateToken.instance;
    if (token == null) {
      _isolateReadyCompleter.completeError('Cannot get RootIsolateToken.');
      return;
    }
    
    final startRequest = IsolateStartRequest(token, mainReceivePort.sendPort);
    _isolate = await Isolate.spawn(ocrIsolateEntryPoint, startRequest);
    
    // Wait for the isolate to send back its SendPort
    final isolateResponse = await mainReceivePort.first;
    if (isolateResponse is SendPort) {
      _isolateSendPort = isolateResponse;
      _isolateReadyCompleter.complete();
    } else {
      _isolateReadyCompleter.completeError('Isolate initialization failed.');
    }
  }

  /// Triggers the ML Kit engine to load its models by processing a dummy image.
  Future<void> warmUp() async {
    await _isolateReadyCompleter.future; // Ensure the isolate is ready first.
    final responsePort = ReceivePort();
    final request = IsolateWarmupRequest(responsePort.sendPort);
    _isolateSendPort!.send(request);
    await responsePort.first;
  }

  Future<(RecognizedText, Size)> processImage(String imagePath) async {
    // Ensure the isolate is ready before sending requests.
    await _isolateReadyCompleter.future;
    if (_isolateSendPort == null) {
      throw Exception('OCR Isolate is not available.');
    }

    final responsePort = ReceivePort();
    final request = IsolateRequest(responsePort.sendPort, imagePath);
    
    _isolateSendPort!.send(request);
    
    final response = await responsePort.first;

    if (response is IsolateResponse) {
      return (response.recognizedText, response.imageSize);
    } else {
      // Propagate the error from the isolate.
      throw response;
    }
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}

// The provider now manages the lifecycle of the OcrService coordinator.
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  ref.onDispose(service.dispose);
  return service;
});