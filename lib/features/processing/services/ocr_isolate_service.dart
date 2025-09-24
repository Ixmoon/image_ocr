import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_ocr/features/processing/utils/image_converter.dart';

// --- Data Models for Isolate Communication ---

// Used to send the initial token and port to the isolate.
class IsolateStartRequest {
  final RootIsolateToken token;
  final SendPort mainSendPort;
  IsolateStartRequest(this.token, this.mainSendPort);
}

// A marker class for the warmup request.
class IsolateWarmupRequest {
  final SendPort sendPort;
  IsolateWarmupRequest(this.sendPort);
}

class IsolateRequest {
  final SendPort sendPort;
  final String imagePath;
  IsolateRequest(this.sendPort, this.imagePath);
}

class IsolateResponse {
  final RecognizedText recognizedText;
  final Size imageSize;
  IsolateResponse(this.recognizedText, this.imageSize);
}

// --- Image Processing Helpers ---

/// Applies grayscale and a 3x3 sharpening convolution kernel to the image.
/// Returns a list of sharpened luminance (Y) values.
Uint8List _applyGrayscaleAndSharpen(img.Image image) {
  final width = image.width;
  final height = image.height;
  final grayscale = Uint8List(width * height);
  final sharpened = Uint8List(width * height);

  // First, convert the entire image to grayscale
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      // Standard luminance calculation
      grayscale[y * width + x] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }
  }

  // Then, apply the sharpening kernel.
  // Kernel:
  //  0, -1,  0
  // -1,  5, -1
  //  0, -1,  0
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
  
  // [FIX] Fill the border pixels ---
  // Copy top and bottom rows from original grayscale
  for (var x = 0; x < width; x++) {
    sharpened[x] = grayscale[x]; // Top row
    sharpened[(height - 1) * width + x] = grayscale[(height - 1) * width + x]; // Bottom row
  }
  // Copy left and right columns from original grayscale
  for (var y = 0; y < height; y++) {
    sharpened[y * width] = grayscale[y * width]; // Left column
    sharpened[y * width + width - 1] = grayscale[y * width + width - 1]; // Right column
  }
  
  return sharpened;
}

/// Converts an RGB image to NV21 format using a pre-computed luminance channel.
Uint8List _convertRgbToNv21WithPrecomputedLuma(img.Image image, Uint8List luma) {
  final width = image.width;
  final height = image.height;
  final frameSize = width * height;
  final yuv420sp = Uint8List(frameSize + (width * height ~/ 2));

  // Copy the pre-computed luma (Y) data.
  yuv420sp.setRange(0, frameSize, luma);

  // --- Calculate Chroma (U and V) planes ---
  int uvIndex = frameSize;
  for (int j = 0; j < height / 2; j++) {
    for (int i = 0; i < width / 2; i++) {
      final x = i * 2;
      final y = j * 2;

      // Average the RGB values of a 2x2 pixel block.
      final p1 = image.getPixel(x, y);
      final p2 = image.getPixel(x + 1, y);
      final p3 = image.getPixel(x, y + 1);
      final p4 = image.getPixel(x + 1, y + 1);

      final r = (p1.r + p2.r + p3.r + p4.r) / 4;
      final g = (p1.g + p2.g + p3.g + p4.g) / 4;
      final b = (p1.b + p2.b + p3.b + p4.b) / 4;

      // Standard RGB to YUV conversion for U and V
      final u = -0.169 * r - 0.331 * g + 0.5 * b + 128;
      final v = 0.5 * r - 0.419 * g - 0.081 * b + 128;

      // NV21 format stores V followed by U.
      yuv420sp[uvIndex++] = v.toInt().clamp(0, 255);
      yuv420sp[uvIndex++] = u.toInt().clamp(0, 255);
    }
  }

  return yuv420sp;
}

// --- Isolate Entry Point ---
void ocrIsolateEntryPoint(IsolateStartRequest startRequest) async {
  // Ensure the isolate is initialized for plugin communication.
  BackgroundIsolateBinaryMessenger.ensureInitialized(startRequest.token);
  
  final isolateReceivePort = ReceivePort();
  // Send the isolate's SendPort back to the main thread.
  startRequest.mainSendPort.send(isolateReceivePort.sendPort);

  final textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  await for (final dynamic request in isolateReceivePort) {
    try {
      if (request is IsolateWarmupRequest) {
        // --- Handle Warmup Request ---
        // Create a tiny, black image to trigger model loading.
        final warmupImage = img.Image(width: 2, height: 2);
        final nv21Bytes = convertRgbToNv21(warmupImage);
        final inputImage = InputImage.fromBytes(
          bytes: nv21Bytes,
          metadata: InputImageMetadata(
            size: const Size(2, 2),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: 2,
          ),
        );
        await textRecognizer.processImage(inputImage);
        request.sendPort.send(true); // Signal completion
        continue;
      }

      if (request is IsolateRequest) {
        // --- Handle OCR Request ---
        final imageBytes = File(request.imagePath).readAsBytesSync();
        var image = img.decodeImage(imageBytes);
        if (image == null) throw Exception('Failed to decode image');

        // [FIX] NV21 format requires even dimensions. Crop the image if necessary.
        if (image.width.isOdd || image.height.isOdd) {
          final newWidth = image.width.isOdd ? image.width - 1 : image.width;
          final newHeight = image.height.isOdd ? image.height - 1 : image.height;
          image = img.copyCrop(image, x: 0, y: 0, width: newWidth, height: newHeight);
        }

        final imageSize = Size(image.width.toDouble(), image.height.toDouble());
        InputImage inputImage;

        if (Platform.isAndroid) {
          // 1. Apply grayscale and sharpening in a single pass.
          final sharpenedLuma = _applyGrayscaleAndSharpen(image);
          // 2. Convert to NV21 using the pre-computed luma channel.
          final nv21Bytes = _convertRgbToNv21WithPrecomputedLuma(image, sharpenedLuma);
          
          inputImage = InputImage.fromBytes(
            bytes: nv21Bytes,
            metadata: InputImageMetadata(
              size: imageSize,
              rotation: InputImageRotation.rotation0deg,
              format: InputImageFormat.nv21,
              bytesPerRow: image.width,
            ),
          );
        } else {
          final bgraBytes = Uint8List.fromList(image.getBytes(order: img.ChannelOrder.bgra));
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
        request.sendPort.send(IsolateResponse(recognizedText, imageSize));
      }
    } catch (e) {
      // Find the correct port to send the error to.
      if (request is IsolateRequest) {
        request.sendPort.send(e);
      } else if (request is IsolateWarmupRequest) {
        request.sendPort.send(e);
      }
    }
  }
}