import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_ocr/core/services/temporary_file_service.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';
import 'package:image_ocr/features/processing/services/image_composition_service.dart';
import 'package:image_ocr/features/processing/services/ocr_service.dart';
import 'package:image_ocr/features/processing/utils/anchor_finder.dart';
import 'package:hive/hive.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/models/template_field.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:image/image.dart' as img;

part 'image_processing_provider.g.dart';

@riverpod
class ImageProcessing extends AutoDisposeNotifier<ImageProcessingState> {
  @override
  ImageProcessingState build() {
    return ImageProcessingState.initial();
  }

  Future<void> processBatch({
    required List<Template> templates, // 接收模板列表
    required List<String> targetImagePaths,
  }) async {
    ref.read(temporaryFileServiceProvider).clearAll();

    state = ImageProcessingState(
      isProcessing: true,
      totalCount: targetImagePaths.length,
      processedCount: 0,
      results: [],
      failedPaths: [],
      error: null,
    );

    try {
      final ocrService = ref.read(ocrServiceProvider);
      final compositionService = ref.read(imageCompositionServiceProvider);
      final fieldsBox = Hive.box<TemplateField>('template_fields');
      final tempFileService = ref.read(temporaryFileServiceProvider); // [修复] 重新添加这行

      // 1. 并行对所有相关模板进行OCR
      final templateOcrFutures = templates.map((t) async {
        // [最终架构] 直接调用OcrService，它内部已包含预处理
        final ocrResult = await ocrService.processImage(t.sourceImagePath);
        // 为了合成，我们仍然需要解码模板图片
        final image = img.decodeImage(await File(t.sourceImagePath).readAsBytes());
        if (image == null) throw Exception('无法解码模板源图: ${t.name}');
        return {'id': t.id, 'image': image, 'ocr': ocrResult};
      }).toList();
      
      final templateOcrResults = await Future.wait(templateOcrFutures);
      // [修正] 显式指定Map类型以解决类型推断问题
      final templateDataMap = <String, Map<String, dynamic>>{
        for (var e in templateOcrResults) e['id'] as String: e
      };

      // 2. 并行处理每一张目标图片
      final processingFutures = targetImagePaths.map((path) {
        return _processSingleImage(
          templates: templates,
          targetImagePath: path,
          templateDataMap: templateDataMap,
          compositionService: compositionService,
          ocrService: ocrService,
          fieldsBox: fieldsBox,
          tempFileService: tempFileService, // [修复] 将其传递给 _processSingleImage
        ).then((resultPath) {
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            results: [...state.results, resultPath],
          );
          return {'path': path, 'status': 'success'};
        }).catchError((e) {
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            failedPaths: [...state.failedPaths, path],
          );
          return {'path': path, 'status': 'failure'};
        });
      }).toList();

      await Future.wait(processingFutures);

    } catch (e) {
       state = state.copyWith(isProcessing: false, error: e.toString());
       return;
    }

    state = state.copyWith(isProcessing: false);
  }

  Future<String> _processSingleImage({
    required List<Template> templates,
    required String targetImagePath,
    required Map<String, Map<String, dynamic>> templateDataMap,
    required ImageCompositionService compositionService,
    required OcrService ocrService,
    required Box<TemplateField> fieldsBox,
    required TemporaryFileService tempFileService, // [修复] 在函数签名中接收它
  }) async {
    
    // [最终架构] 直接调用OcrService，它内���已包含预处理
    final targetOcrResult = await ocrService.processImage(targetImagePath);

    // 为了合成，我们仍然需要解码目标图片
    final targetImage = img.decodeImage(await File(targetImagePath).readAsBytes());
    if (targetImage == null) throw Exception('无法解码目标图片');

    img.Image currentImage = targetImage;

    // [核心逻辑] 依次应用每一个模板
    for (final template in templates) {
      final templateData = templateDataMap[template.id]!;
      final templateImage = templateData['image'] as img.Image;
      final templateOcrResult = templateData['ocr'] as RecognizedText;

      for (final fieldId in template.fieldIds) {
        final field = fieldsBox.get(fieldId);
        if (field == null) continue;

        final templateAnchor = findAnchorLine(ocrResult: templateOcrResult, searchText: field.name);
        if (templateAnchor == null) throw Exception('在模板 "${template.name}" 中找不到锚点 "${field.name}"');

        final targetAnchor = findAnchorLine(ocrResult: targetOcrResult, searchText: field.name);
        if (targetAnchor == null) throw Exception('在目标图片中找不到锚点 "${field.name}"');

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

        final targetValueRect = findValueRectForAnchorLine(
          anchorLine: targetAnchor,
          imageSize: Size(targetImage.width.toDouble(), targetImage.height.toDouble()),
        );

        // 基于上一个模板处理的结果，继续合成
        currentImage = await compositionService.compose(
          baseImage: currentImage,
          patchImageBytes: patchImageBytes,
          targetValueArea: targetValueRect,
        );
      }
    }

    final resultPath = await tempFileService.create('result_', '.png');
    await File(resultPath).writeAsBytes(img.encodePng(currentImage));
    return resultPath;
  }
}