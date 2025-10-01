import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart'; // CRITICAL FIX: Import for Isolate binding
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_ocr/features/processing/services/image_composition_service.dart';
import 'package:image_ocr/features/processing/utils/anchor_finder.dart';

// --- Data Structures for Isolate Communication ---

/// Defines the type of task for the worker isolate.
enum TaskType { initialize, decode, ocr, composition }

/// A generic request sent from the main isolate to a worker isolate.
class ProcessingRequest {
  final SendPort sendPort;
  final TaskType taskType;
  final dynamic payload;

  ProcessingRequest(this.sendPort, this.taskType, this.payload);
}

/// A generic response sent from a worker isolate back to the main isolate.
class ProcessingResponse {
  final bool isSuccess;
  final dynamic data;
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
class OcrPayload {
  final Uint8List imageBytes;
  final String imagePath; // Used as a key

  OcrPayload({required this.imageBytes, required this.imagePath});
}

/// Data needed for the one-time initialization of a worker.
class InitializePayload {
  final List<PlainTemplate> templates;
  final Map<String, RecognizedText> templateOcrResults;
  final Map<String, PlainTemplateField> fieldsMap;
  final Map<String, Uint8List> templateImageBytes;

  InitializePayload({
    required this.templates,
    required this.templateOcrResults,
    required this.fieldsMap,
    required this.templateImageBytes,
  });
}

class CompositionPayload {
  final Uint8List targetImageBytes;
  final String targetImagePath; // Used as a key
  final RecognizedText targetOcrResult;

  CompositionPayload({
    required this.targetImageBytes,
    required this.targetImagePath,
    required this.targetOcrResult,
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

  // Enhanced cache to hold pre-decoded image objects
  _WorkerCache? cache;

  await for (final dynamic message in workerReceivePort) {
    if (message is ProcessingRequest) {
      try {
        dynamic result;
        switch (message.taskType) {
          case TaskType.initialize:
            cache = _WorkerCache.create(message.payload as InitializePayload);
            result = true;
            break;
          case TaskType.decode:
            result = await _performDecode(message.payload as String);
            break;
          case TaskType.ocr:
            result = await _performOcr(textRecognizer, message.payload as OcrPayload);
            break;
          case TaskType.composition:
            if (cache == null) {
              throw StateError('Worker has not been initialized with template data.');
            }
            result = await _performComposition(
              message.payload as CompositionPayload,
              cache,
            );
            break;
        }
        message.sendPort.send(ProcessingResponse.success(result));
      } catch (e) {
        message.sendPort.send(ProcessingResponse.failure(e.toString()));
      }
    }
  }

  textRecognizer.close();
}

// --- Image Processing Helpers from original ocr_isolate_service.dart ---

Uint8List _applyGrayscaleAndSharpen(img.Image image, int width, int height) {
  final grayscale = Uint8List(width * height);
  final sharpened = Uint8List(width * height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      grayscale[y * width + x] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }

  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final p0 = grayscale[(y - 1) * width + x];
      final p1 = grayscale[y * width + x - 1];
      final p2 = grayscale[y * width + x];
      final p3 = grayscale[y * width + x + 1];
      final p4 = grayscale[(y + 1) * width + x];
      final newValue = (5 * p2) - p0 - p1 - p3 - p4;
      sharpened[y * width + x] = newValue.clamp(0, 255);
    }
  }

  for (var x = 0; x < width; x++) {
    sharpened[x] = grayscale[x];
    sharpened[(height - 1) * width + x] = grayscale[(height - 1) * width + x];
  }
  for (var y = 0; y < height; y++) {
    sharpened[y * width] = grayscale[y * width];
    sharpened[y * width + width - 1] = grayscale[y * width + width - 1];
  }
  
  return sharpened;
}

Uint8List _convertRgbToNv21WithPrecomputedLuma(img.Image image, Uint8List luma, int width, int height) {
  final frameSize = width * height;
  final yuv420sp = Uint8List(frameSize + (width * height ~/ 2));

  yuv420sp.setRange(0, frameSize, luma);

  int uvIndex = frameSize;
  for (int j = 0; j < height / 2; j++) {
    for (int i = 0; i < width / 2; i++) {
      final x = i * 2;
      final y = j * 2;
      final p1 = image.getPixel(x, y);
      final p2 = image.getPixel(x + 1, y);
      final p3 = image.getPixel(x, y + 1);
      final p4 = image.getPixel(x + 1, y + 1);
      final r = (p1.r + p2.r + p3.r + p4.r) / 4;
      final g = (p1.g + p2.g + p3.g + p4.g) / 4;
      final b = (p1.b + p2.b + p3.b + p4.b) / 4;
      final u = -0.169 * r - 0.331 * g + 0.5 * b + 128;
      final v = 0.5 * r - 0.419 * g - 0.081 * b + 128;
      yuv420sp[uvIndex++] = v.toInt().clamp(0, 255);
      yuv420sp[uvIndex++] = u.toInt().clamp(0, 255);
    }
  }

  return yuv420sp;
}


/// Decodes an image from a file path into raw bytes.
Future<Uint8List> _performDecode(String imagePath) async {
  final imageBytes = await File(imagePath).readAsBytes();
  // Here we are just returning the raw file bytes. The actual decoding to pixels
  // will happen in the OCR and Composition tasks from this byte buffer.
  // This ensures I/O is done only once.
  return imageBytes;
}

/// Performs text recognition on raw image bytes, applying platform-specific optimizations.
/// Returns both the OCR result and the original image size.
Future<(RecognizedText, Size)> _performOcr(TextRecognizer textRecognizer, OcrPayload payload) async {
  img.Image? image;
  try {
    image = img.decodeImage(payload.imageBytes);
    if (image == null) throw Exception('Failed to decode image: ${payload.imagePath}');

    InputImage inputImage;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isAndroid) {
      // Use the highly optimized NV21 conversion path for Android.
      final evenWidth = image.width.isOdd ? image.width - 1 : image.width;
      final evenHeight = image.height.isOdd ? image.height - 1 : image.height;

      final sharpenedLuma = _applyGrayscaleAndSharpen(image, evenWidth, evenHeight);
      final nv21Bytes = _convertRgbToNv21WithPrecomputedLuma(image, sharpenedLuma, evenWidth, evenHeight);
      
      inputImage = InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(evenWidth.toDouble(), evenHeight.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: evenWidth,
        ),
      );
    } else {
      // Use BGRA8888 for other platforms (e.g., iOS).
      // OPTIMIZED: Get bytes directly without unnecessary copy
      final bgraBytes = image.getBytes(order: img.ChannelOrder.bgra);
      inputImage = InputImage.fromBytes(
        bytes: bgraBytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.width * 4,
        ),
      );
    }

    final recognizedText = await textRecognizer.processImage(inputImage);
    return (recognizedText, imageSize);
  } finally {
    // 优化：及时清理图片内存
    image?.clear();
  }
}

/// Performs image composition based on the provided payload.
/// Holds all the pre-processed and cached data for a worker isolate.
class _WorkerCache {
  final InitializePayload initPayload;
  final Map<String, img.Image> decodedTemplateImages;

  _WorkerCache({
    required this.initPayload,
    required this.decodedTemplateImages,
  });

  static _WorkerCache create(InitializePayload payload) {
    final decodedImages = <String, img.Image>{};
    for (final entry in payload.templateImageBytes.entries) {
      // OPTIMIZED: Decode directly on the worker isolate, avoid compute() overhead.
      final image = img.decodeImage(entry.value);
      if (image != null) {
        decodedImages[entry.key] = image;
      }
    }
    return _WorkerCache(initPayload: payload, decodedTemplateImages: decodedImages);
  }
}

Future<Uint8List> _performComposition(
  CompositionPayload payload,
  _WorkerCache cache,
) async {
  final compositionService = ImageCompositionService();

  img.Image? targetImage;
  img.Image? currentImage;
  try {
    targetImage = img.decodeImage(payload.targetImageBytes);
    if (targetImage == null) {
      throw Exception('Failed to decode target image in isolate: ${payload.targetImagePath}');
    }

    currentImage = targetImage;
    bool atLeastOneFieldApplied = false; // 标志位，追踪是否有字段被应用

    for (final template in cache.initPayload.templates) {
      final templateOcrResult = cache.initPayload.templateOcrResults[template.id]!;
      final templateImage = cache.decodedTemplateImages[template.id];
      if (templateImage == null) {
        continue;
      }

      for (final fieldId in template.fieldIds) {
        final field = cache.initPayload.fieldsMap[fieldId];
        if (field == null) continue;

        final templateAnchor = findAnchorLine(ocrResult: templateOcrResult, searchText: field.name);
        final targetAnchor = findAnchorLine(ocrResult: payload.targetOcrResult, searchText: field.name);
        
        // 如果在模板或目标图中找不到锚点，则跳过此字段
        if (templateAnchor == null || targetAnchor == null) {
          continue;
        }

        // 如果代码执行到这里，说明锚点已找到，我们将应用补丁
        atLeastOneFieldApplied = true;

        final templateValueRect = findValueRectForAnchorLine(
          anchorLine: templateAnchor,
          imageSize: Size(templateImage.width.toDouble(), templateImage.height.toDouble()),
        );
        
        img.Image? patchImage;
        try {
          patchImage = img.copyCrop(
            templateImage,
            x: templateValueRect.left.toInt(),
            y: templateValueRect.top.toInt(),
            width: templateValueRect.width.toInt(),
            height: templateValueRect.height.toInt(),
          );

          final targetValueRect = findValueRectForAnchorLine(
            anchorLine: targetAnchor,
            imageSize: Size(targetImage.width.toDouble(), targetImage.height.toDouble()),
          );
          
          final newImage = compositionService.compose(
            baseImage: currentImage!,
            patchImage: patchImage,
            targetValueArea: targetValueRect,
          );
          
          // 优化：及时清理旧的图片内存
          if (currentImage != targetImage) {
            currentImage?.clear();
          }
          currentImage = newImage;
        } finally {
          // 清理patch图片内存
          patchImage?.clear();
        }
      }
    }

    // 在所有操作后，检查是否有任何字段被成功应用
    if (!atLeastOneFieldApplied) {
      throw Exception('Composition failed: No anchors were found in the target image for any of the provided templates.');
    }

    final result = Uint8List.fromList(img.encodePng(currentImage!));
    return result;
  } finally {
    // 优化：确保所有图片内存被清理
    if (currentImage != null && currentImage != targetImage) {
      currentImage.clear();
    }
    targetImage?.clear();
  }
}