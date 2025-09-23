import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_clone_tool/features/processing/models/image_processing_state.dart';
import 'package:image_clone_tool/features/processing/services/image_composition_service.dart';
import 'package:image_clone_tool/features/processing/services/ocr_service.dart';
import 'package:hive/hive.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzzy;
import 'package:image_clone_tool/features/templates/models/template.dart';
import 'package:image_clone_tool/features/templates/models/template_field.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

part 'image_processing_provider.g.dart';

// 负责处理应用模板时的图像合成流程，支持批量处理
@riverpod
class ImageProcessing extends AutoDisposeNotifier<ImageProcessingState> {
  @override
  ImageProcessingState build() {
    // 返回初始状态
    return ImageProcessingState.initial();
  }

  // 核心方法：批量处理图片
  Future<void> processBatch({
    required Template template,
    required List<String> targetImagePaths,
  }) async {
    // 1. 初始化状态，进入处理中
    state = ImageProcessingState(
      isProcessing: true,
      totalCount: targetImagePaths.length,
      processedCount: 0,
      results: [],
      error: null,
    );

    final List<String> successfulResults = [];

    // 2. 循环处理每张图片
    for (int i = 0; i < targetImagePaths.length; i++) {
      final path = targetImagePaths[i];
      try {
        // 调用单个图片的处理逻辑
        final resultPath = await _processSingleImage(template, path);
        successfulResults.add(resultPath);
      } catch (e) {
        // 如果单张图片处理失败，打印错误日志，但继续处理下一张
        if (kDebugMode) {
          //print('Error processing image $path: $e');
        }
      }
      // 更新进度状态
      state = state.copyWith(processedCount: i + 1);
    }

    // 3. 所有图片处理完成，更新最终状态
    state = state.copyWith(isProcessing: false, results: successfulResults);
  }

  // 单个图片的处理逻辑
  Future<String> _processSingleImage(Template template, String targetImagePath) async {
    final ocrService = ref.read(ocrServiceProvider);
    final compositionService = ref.read(imageCompositionServiceProvider);

    // 对目标图片进行OCR
    final RecognizedText targetOcrResult = await ocrService.processImage(targetImagePath);

    // 加载目标图片
    final targetImageBytes = await File(targetImagePath).readAsBytes();
    final decodedImage = img.decodeImage(targetImageBytes);
    if (decodedImage == null) throw Exception('Failed to decode target image.');

    img.Image currentImage = decodedImage; // 使用一个不可空的局部变量

    final fieldsBox = Hive.box<TemplateField>('template_fields');

    // 遍历模板中的每个字段ID，并在目标图片上进行替换
    for (final fieldId in template.fieldIds) {
      final field = fieldsBox.get(fieldId);
      if (field == null) continue;

      // --- 核心替换逻辑开始 ---
      // 1. 定位锚点：在目标图片中找到与模板标签最匹配的文本块
      TextBlock? anchorBlock;
      int highestRatio = 0;
      final regex = RegExp(r'[^a-zA-Z0-9\u4e00-\u9fa5]');
      final sourceText = field.name.toLowerCase().replaceAll(regex, '');

      for (final block in targetOcrResult.blocks) {
        final targetText = block.text.toLowerCase().replaceAll(regex, '');
        final ratio = fuzzy.ratio(sourceText, targetText);
        if (ratio > highestRatio) {
          highestRatio = ratio;
          anchorBlock = block;
        }
      }

      // 2. 如果找到锚点，则计算替换区域并执行合成
      if (anchorBlock != null && highestRatio >= 60) {
        final targetLabelRect = anchorBlock.boundingBox;
        final imageSize = Size(currentImage.width.toDouble(), currentImage.height.toDouble());

        // a. 计算模板中的垂直偏移
        final verticalOffset = field.valueRect.top - field.labelRect.top;
        // b. 计算新图片上替换区域的 top
        final newTop = targetLabelRect.top + verticalOffset;
        // c. 高度直接使用模板中定义的高度
        final newHeight = field.valueRect.height;

        // d. left 永远是0，width 永远是图片宽度，构造最终的替换区域
        final targetValueRect = Rect.fromLTWH(
          0.0,
          newTop,
          imageSize.width,
          newHeight,
        );

        // e. 执行图像合成
        currentImage = await compositionService.compose(
          baseImage: currentImage,
          patchImageBytes: Uint8List.fromList(field.valueImageBytes),
          targetValueArea: targetValueRect,
        );
      }
      // --- 核心替换逻辑结束 ---
    }

    // 将最终合成的图片保存到应用临时目录
    final tempDir = await getTemporaryDirectory();
    final resultPath = '${tempDir.path}/${const Uuid().v4()}.png';
    final resultFile = File(resultPath);
    await resultFile.writeAsBytes(img.encodePng(currentImage));

    return resultPath;
  }
}