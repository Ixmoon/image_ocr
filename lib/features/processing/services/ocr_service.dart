import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_ocr/core/services/temporary_file_service.dart';
import 'package:image_ocr/features/processing/services/image_preprocessing_service.dart';

// OCR服务类，封装了与ML Kit的交互
class OcrService {
  final TextRecognizer _textRecognizer;
  final ImagePreprocessingService _preprocessingService;
  final TemporaryFileService _tempFileService;

  // 根据平台初始化识别器，并注入依赖
  OcrService(this._preprocessingService, this._tempFileService)
      : _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  // [核心修改] 在这里统一处理预处理和OCR
  Future<RecognizedText> processImage(String imagePath) async {
    if (kIsWeb || Platform.isWindows) {
      return RecognizedText(text: '', blocks: const []);
    }

    try {
      // 1. 解码图片
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('无法解码图片: $imagePath');

      // 2. 对图片进行预处理
      final preprocessedImage = _preprocessingService.preprocessForOcr(image);

      // 3. 将预处理后的图片保存到临时文件
      final tempOcrPath = await _tempFileService.create('ocr_input_', '.png');
      await File(tempOcrPath).writeAsBytes(img.encodePng(preprocessedImage));

      // 4. 对预处理后的临时图片进行OCR
      final inputImage = InputImage.fromFilePath(tempOcrPath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      
      return recognizedText;

    } catch (e) {
      rethrow;
    }
  }

  // 释放资源
  void dispose() {
    _textRecognizer.close();
  }
}

// [核心修改] 更新Provider，注入依赖
final ocrServiceProvider = Provider<OcrService>((ref) {
  final preprocessingService = ref.watch(imagePreprocessingServiceProvider);
  final tempFileService = ref.watch(temporaryFileServiceProvider);
  final service = OcrService(preprocessingService, tempFileService);
  ref.onDispose(service.dispose);
  return service;
});