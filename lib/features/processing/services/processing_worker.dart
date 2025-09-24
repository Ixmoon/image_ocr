import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart'; // CRITICAL FIX: Import for Isolate binding
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_ocr/features/processing/services/image_composition_service.dart';
import 'package:image_ocr/features/processing/utils/anchor_finder.dart';

// --- Data Structures for Isolate Communication ---

/// Defines the type of task for the worker isolate.
enum TaskType { ocr, composition }

/// A generic request sent from the main isolate to a worker isolate.
class ProcessingRequest {
  final SendPort sendPort;
  final TaskType taskType;
  final dynamic payload; // Can be String for OCR path or CompositionPayload

  ProcessingRequest(this.sendPort, this.taskType, this.payload);
}

/// A generic response sent from a worker isolate back to the main isolate.
class ProcessingResponse {
  final bool isSuccess;
  final dynamic data; // Can be RecognizedText or Uint8List
  final String? error;

  ProcessingResponse.success(this.data)
      : isSuccess = true,
        error = null;

  ProcessingResponse.failure(this.error)
      : isSuccess = false,
        data = null;
}

/// A plain, sendable version of the TemplateField model.
class PlainTemplateField {
  final String id;
  final String name;
  PlainTemplateField({required this.id, required this.name});
}

/// A plain, sendable version of the Template model.
class PlainTemplate {
  final String id;
  final String name;
  final String sourceImagePath;
  final List<String> fieldIds;
  PlainTemplate({
    required this.id,
    required this.name,
    required this.sourceImagePath,
    required this.fieldIds,
  });
}

/// Data needed for the composition task, using only sendable plain objects.
class CompositionPayload {
  final List<PlainTemplate> templates;
  final String targetImagePath;
  final RecognizedText targetOcrResult;
  final Map<String, RecognizedText> templateOcrResults;
  final Map<String, PlainTemplateField> fieldsMap;
  final Map<String, Uint8List> templateImageBytes;

  CompositionPayload({
    required this.templates,
    required this.targetImagePath,
    required this.targetOcrResult,
    required this.templateOcrResults,
    required this.fieldsMap,
    required this.templateImageBytes,
  });
}

// --- Isolate Entry Point and Task Handlers ---

/// The main entry point for the processing worker isolate.
void processingWorkerEntryPoint(Map<String, dynamic> context) async {
  // [ULTIMATE FIX] Correctly initialize the binding for background isolates.
  final mainSendPort = context['port'] as SendPort;
  final token = context['token'] as RootIsolateToken;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  final textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  await for (final dynamic message in workerReceivePort) {
    if (message is ProcessingRequest) {
      try {
        dynamic result;
        if (message.taskType == TaskType.ocr) {
          result = await _performOcr(textRecognizer, message.payload as String);
        } else if (message.taskType == TaskType.composition) {
          result = await _performComposition(message.payload as CompositionPayload);
        }
        message.sendPort.send(ProcessingResponse.success(result));
      } catch (e) {
        // Still log the error in the worker as it's critical for debugging if something goes wrong.
        debugPrint('[Worker] Task failed: $e');
        message.sendPort.send(ProcessingResponse.failure(e.toString()));
      }
    }
  }

  textRecognizer.close();
}

/// Performs text recognition on a given image path.
Future<RecognizedText> _performOcr(TextRecognizer textRecognizer, String imagePath) async {
  final inputImage = InputImage.fromFilePath(imagePath);
  final recognizedText = await textRecognizer.processImage(inputImage);
  return recognizedText;
}

/// Performs image composition based on the provided payload.
Future<Uint8List> _performComposition(CompositionPayload payload) async {
  final totalStopwatch = Stopwatch()..start();
  final stepStopwatch = Stopwatch();
  final imageId = payload.targetImagePath.split('/').last;
  final log = (String step, int elapsed) => debugPrint('[PERF][Isolate for $imageId] $step: ${elapsed}ms');

  final compositionService = ImageCompositionService();

  // 1. Decode the target image
  stepStopwatch.start();
  final targetImageBytes = await File(payload.targetImagePath).readAsBytes();
  final targetImage = img.decodeImage(targetImageBytes);
  if (targetImage == null) {
    throw Exception('Failed to decode target image in isolate: ${payload.targetImagePath}');
  }
  log('1. Decode Target Image', stepStopwatch.elapsedMilliseconds);
  
  img.Image currentImage = targetImage;

  // 2. Sequentially apply each template
  for (final template in payload.templates) {
    stepStopwatch.reset();
    stepStopwatch.start();
    final templateOcrResult = payload.templateOcrResults[template.id]!;
    final templateImageBytes = payload.templateImageBytes[template.id]!;
    final templateImage = img.decodeImage(templateImageBytes);
    if (templateImage == null) {
      throw Exception('Failed to decode template image in isolate: ${template.name}');
    }
    log('2a. Decode Template "${template.name}"', stepStopwatch.elapsedMilliseconds);

    for (final fieldId in template.fieldIds) {
      final field = payload.fieldsMap[fieldId];
      if (field == null) continue;

      stepStopwatch.reset();
      stepStopwatch.start();
      final templateAnchor = findAnchorLine(ocrResult: templateOcrResult, searchText: field.name);
      final targetAnchor = findAnchorLine(ocrResult: payload.targetOcrResult, searchText: field.name);
      if (templateAnchor == null || targetAnchor == null) {
        // Gracefully skip if anchor is not found, instead of throwing an exception
        debugPrint('Anchor for "${field.name}" not found. Skipping field.');
        continue;
      }
      log('2b. Find Anchors for "${field.name}"', stepStopwatch.elapsedMilliseconds);
      
      stepStopwatch.reset();
      stepStopwatch.start();
      final templateValueRect = findValueRectForAnchorLine(
        anchorLine: templateAnchor,
        imageSize: Size(templateImage.width.toDouble(), templateImage.height.toDouble()),
      );
      final patchImage = img.copyCrop(
        templateImage,
        x: templateValueRect.left.toInt(),
        y: templateValueRect.top.toInt(),
        width: templateValueRect.width.toInt(),
        height: templateValueRect.height.toInt(),
      );
      final patchImageBytes = Uint8List.fromList(img.encodePng(patchImage));
      log('2c. Crop Patch for "${field.name}"', stepStopwatch.elapsedMilliseconds);

      stepStopwatch.reset();
      stepStopwatch.start();
      final targetValueRect = findValueRectForAnchorLine(
        anchorLine: targetAnchor,
        imageSize: Size(targetImage.width.toDouble(), targetImage.height.toDouble()),
      );
      currentImage = await compositionService.compose(
        baseImage: currentImage,
        patchImageBytes: patchImageBytes,
        targetValueArea: targetValueRect,
      );
      log('2d. Compose Patch for "${field.name}"', stepStopwatch.elapsedMilliseconds);
    }
  }

  // 3. Encode the final image and return its bytes
  stepStopwatch.reset();
  stepStopwatch.start();
  final result = Uint8List.fromList(img.encodePng(currentImage));
  log('3. Encode Final Image', stepStopwatch.elapsedMilliseconds);
  
  totalStopwatch.stop();
  debugPrint('[PERF][Isolate for $imageId] >>> Total Composition Time: ${totalStopwatch.elapsedMilliseconds}ms <<<');
  
  return result;
}