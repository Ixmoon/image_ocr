import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

/// 负责在OCR之前对图像进行预处理，以提高识别准确率。
class ImagePreprocessingService {
  /// 对给定的图像应用一系列预处理滤镜。
  ///
  /// [image] 是从文件中解码的原始图像。
  /// 返回一个经过优化处理以用于OCR的新图像。
  img.Image preprocessForOcr(img.Image image) {
    // 遵从指示：在OCR前进行灰度化和锐化处理
    
    // 1. 转换为灰度图
    final processedImage = img.grayscale(image.clone());

    // 2. 应用锐化（通过卷积实现）
    // 定义一个标准的锐化卷积核
    final sharpenKernel = [
       0, -1,  0,
      -1,  5, -1,
       0, -1,  0
    ];
    
    final sharpenedImage = img.convolution(processedImage, filter: sharpenKernel);

    return sharpenedImage;
  }
}

/// Riverpod Provider，用于在应用中访问 ImagePreprocessingService 的实例。
final imagePreprocessingServiceProvider = Provider<ImagePreprocessingService>((ref) {
  return ImagePreprocessingService();
});