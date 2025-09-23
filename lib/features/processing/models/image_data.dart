import 'package:flutter/painting.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// 数据模型：用于存储单张图片的信息及其OCR识别结果
// 注意：这个模型在当前模板驱动的流程中未被直接使用，但保留下来以备未来功能扩展
class ImageData {
  final String imagePath; // 图片在设备上的本地路径
  final Size imageSize; // 图片的原始尺寸
  final List<TextBlock> ocrResult; // OCR识别出的文本块列表

  const ImageData({
    required this.imagePath,
    required this.imageSize,
    this.ocrResult = const [], // 默认为空列表
  });

  // 创建一个新实例，用于更新OCR结果
  ImageData copyWith({
    String? imagePath,
    Size? imageSize,
    List<TextBlock>? ocrResult,
  }) {
    return ImageData(
      imagePath: imagePath ?? this.imagePath,
      imageSize: imageSize ?? this.imageSize,
      ocrResult: ocrResult ?? this.ocrResult,
    );
  }
}