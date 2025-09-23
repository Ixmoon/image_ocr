import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// OCR服务类，封装了与ML Kit的交互
class OcrService {
  final TextRecognizer? _textRecognizer;

  // 根据平台初始化识别器
  OcrService()
      : _textRecognizer = kIsWeb || Platform.isWindows
            ? null // 在Windows或Web上，我们不初始化ML Kit识别器
            : TextRecognizer(script: TextRecognitionScript.chinese);

  // 处理单个图片文件，返回识别结果
  Future<RecognizedText> processImage(String imagePath) async {
    // --- [日志 1] ---
    //print('[DEBUG] OcrService: processImage called for path: $imagePath');

    if (kIsWeb || Platform.isWindows || _textRecognizer == null) {
      // --- [日志 2] ---
      //print('[DEBUG] OcrService: Platform not supported, returning empty result.');
      return RecognizedText(text: '', blocks: const []);
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      // --- [日志 3] ---
      //print('[DEBUG] OcrService: Starting ML Kit text recognition...');
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      // --- [日志 4] ---
      //print('[DEBUG] OcrService: Recognition successful. Found ${recognizedText.blocks.length} text blocks.');
      return recognizedText;
    } catch (e) {
      // --- [日志 5] ---
      //print('[ERROR] OcrService: OCR processing failed: $e');
      rethrow;
    }
  }

  // 释放资源
  void dispose() {
    _textRecognizer?.close();
  }
}

// Provider保持不变
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = OcrService();
  ref.onDispose(service.dispose);
  return service;
});