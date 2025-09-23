import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

// 图像合成服务
class ImageCompositionService {
  
  // 执行图像合成的核心方法
  Future<img.Image> compose({
    required img.Image baseImage,
    required Uint8List patchImageBytes,
    required Rect targetValueArea,
  }) async {
    var patchImage = img.decodeImage(patchImageBytes);
    if (patchImage == null) {
      return baseImage; // 如果补丁图片解码失败，返回原图
    }

    // compositeImage返回一个新的Image对象，而不是在原地修改
    final newImage = img.compositeImage(
      baseImage,
      patchImage,
      dstX: targetValueArea.left.toInt(),
      dstY: targetValueArea.top.toInt(),
    );

    return newImage;
  }

  // findTargetValueRect 方法已被移除，逻辑移至 ImageProcessingProvider
}

// 创建Provider
final imageCompositionServiceProvider = Provider<ImageCompositionService>((ref) {
  return ImageCompositionService();
});