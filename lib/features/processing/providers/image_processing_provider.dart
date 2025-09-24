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

/// A data class to hold all necessary information for processing a single image in an isolate.
class _CompositionPayload {
  final List<Template> templates;
  final String targetImagePath;
  final RecognizedText targetOcrResult;
  final Map<String, RecognizedText> templateOcrResults;
  final Map<String, TemplateField> fieldsMap;
  final Map<String, Uint8List> templateImageBytes;

  _CompositionPayload({
    required this.templates,
    required this.targetImagePath,
    required this.targetOcrResult,
    required this.templateOcrResults,
    required this.fieldsMap,
    required this.templateImageBytes,
  });
}

/// This top-level function runs in a separate isolate to perform CPU-bound work.
Future<Uint8List> _performCompositionInIsolate(_CompositionPayload payload) async {
  final compositionService = ImageCompositionService();

  // 1. Decode the target image
  final targetImageBytes = await File(payload.targetImagePath).readAsBytes();
  final targetImage = img.decodeImage(targetImageBytes);
  if (targetImage == null) {
    throw Exception('Failed to decode target image in isolate: ${payload.targetImagePath}');
  }

  img.Image currentImage = targetImage;

  // 2. Sequentially apply each template
  for (final template in payload.templates) {
    final templateOcrResult = payload.templateOcrResults[template.id]!;
    final templateImageBytes = payload.templateImageBytes[template.id]!;
    final templateImage = img.decodeImage(templateImageBytes);
    if (templateImage == null) {
      throw Exception('Failed to decode template image in isolate: ${template.name}');
    }

    for (final fieldId in template.fieldIds) {
      final field = payload.fieldsMap[fieldId];
      if (field == null) continue;

      final templateAnchor = findAnchorLine(ocrResult: templateOcrResult, searchText: field.name);
      if (templateAnchor == null) throw Exception('In template "${template.name}", anchor "${field.name}" not found.');

      final targetAnchor = findAnchorLine(ocrResult: payload.targetOcrResult, searchText: field.name);
      if (targetAnchor == null) throw Exception('In target image, anchor "${field.name}" not found.');

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

      currentImage = await compositionService.compose(
        baseImage: currentImage,
        patchImageBytes: patchImageBytes,
        targetValueArea: targetValueRect,
      );
    }
  }

  // 3. Encode the final image and return its bytes
  return Uint8List.fromList(img.encodePng(currentImage));
}


@riverpod
class ImageProcessing extends AutoDisposeNotifier<ImageProcessingState> {
  @override
  ImageProcessingState build() {
    return ImageProcessingState.initial();
  }

  Future<void> processBatch({
    required List<Template> templates,
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
      final fieldsBox = Hive.box<TemplateField>('template_fields');
      final tempFileService = ref.read(temporaryFileServiceProvider);

      // 1. Prepare all data in parallel on the main isolate
      final allTemplateFieldIds = templates.expand((t) => t.fieldIds).toSet();
      final fieldsMap = {for (var id in allTemplateFieldIds) id: fieldsBox.get(id)!};

      final templateFutures = templates.map((t) async {
        final ocr = await ocrService.processImage(t.sourceImagePath);
        final bytes = await File(t.sourceImagePath).readAsBytes();
        return {'id': t.id, 'ocr': ocr, 'bytes': bytes};
      }).toList();

      final targetFutures = targetImagePaths.map((path) async {
        final ocr = await ocrService.processImage(path);
        return {'path': path, 'ocr': ocr};
      }).toList();

      final templateResults = await Future.wait(templateFutures);
      final targetResults = await Future.wait(targetFutures);

      final templateOcrMap = {for (var r in templateResults) r['id'] as String: r['ocr'] as RecognizedText};
      final templateBytesMap = {for (var r in templateResults) r['id'] as String: r['bytes'] as Uint8List};

      // 2. Create a payload for each target image
      final payloads = targetResults.map((targetData) {
        return _CompositionPayload(
          templates: templates,
          targetImagePath: targetData['path'] as String,
          targetOcrResult: targetData['ocr'] as RecognizedText,
          templateOcrResults: templateOcrMap,
          fieldsMap: fieldsMap,
          templateImageBytes: templateBytesMap,
        );
      }).toList();

      // 3. Offload composition work to isolates
      final processingFutures = payloads.map((payload) {
        return compute(_performCompositionInIsolate, payload).then((resultBytes) async {
          final resultPath = await tempFileService.create('result_', '.png');
          await File(resultPath).writeAsBytes(resultBytes);
          
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            results: [...state.results, resultPath],
          );
        }).catchError((e) {
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            failedPaths: [...state.failedPaths, payload.targetImagePath],
          );
        });
      }).toList();

      await Future.wait(processingFutures);

    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return;
    }

    state = state.copyWith(isProcessing: false);
  }
}