import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_ocr/core/services/temporary_file_service.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';
import 'package:image_ocr/features/processing/services/processing_isolate_pool_service.dart';
import 'package:image_ocr/features/processing/services/processing_worker.dart';
import 'package:hive/hive.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/models/template_field.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'image_processing_provider.g.dart';

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
      final fieldsBox = Hive.box<TemplateField>('template_fields');
      final tempFileService = ref.read(temporaryFileServiceProvider);
      final pool = ref.read(processingIsolatePoolProvider);

      final allTemplateFieldIds = templates.expand((t) => t.fieldIds).toSet();
      final fieldsMap = <String, PlainTemplateField>{};
      for (final id in allTemplateFieldIds) {
        final fieldFromBox = fieldsBox.get(id)!;
        fieldsMap[id] = PlainTemplateField(id: fieldFromBox.id, name: fieldFromBox.name);
      }
      final sanitizedTemplates = templates.map((t) => PlainTemplate(
        id: t.id,
        name: t.name,
        sourceImagePath: t.sourceImagePath,
        fieldIds: List<String>.from(t.fieldIds),
      )).toList();

      final allImagePaths = {
        ...templates.map((t) => t.sourceImagePath),
        ...targetImagePaths,
      }.toList();

      final decodeFutures = allImagePaths.map((path) async {
        final response = await pool.dispatch(TaskType.decode, path);
        if (!response.isSuccess) throw Exception('Failed to decode image: $path');
        return MapEntry(path, response.data as Uint8List);
      });
      final allDecodedBytes = Map.fromEntries(await Future.wait(decodeFutures));

      final ocrFutures = allImagePaths.map((path) async {
        final payload = OcrPayload(imageBytes: allDecodedBytes[path]!, imagePath: path);
        final response = await pool.dispatch(TaskType.ocr, payload);
        if (!response.isSuccess) throw Exception('Failed to OCR image: $path');
        final (text, size) = response.data as (RecognizedText, Size);
        return MapEntry(path, {'ocr': text, 'size': size});
      });
      final ocrResultsWithSizes = Map.fromEntries(await Future.wait(ocrFutures));
      final allOcrResults = ocrResultsWithSizes.map((key, value) => MapEntry(key, value['ocr'] as RecognizedText));

      final initPayload = InitializePayload(
        templates: sanitizedTemplates,
        templateOcrResults: {
          for (var t in templates) t.id: allOcrResults[t.sourceImagePath]!
        },
        fieldsMap: fieldsMap,
        templateImageBytes: {
          for (var t in templates) t.id: allDecodedBytes[t.sourceImagePath]!
        },
      );
      await pool.broadcast(TaskType.initialize, initPayload);

      final processingPipelines = targetImagePaths.map((targetPath) async {
        try {
          final payload = CompositionPayload(
            targetImagePath: targetPath,
            targetImageBytes: allDecodedBytes[targetPath]!,
            targetOcrResult: allOcrResults[targetPath]!,
          );

          final compositionResponse = await pool.dispatch(TaskType.composition, payload);
          if (!compositionResponse.isSuccess) throw Exception('Failed to compose image: $targetPath');
          final resultBytes = compositionResponse.data as Uint8List;

          final resultPath = await tempFileService.create('result_', '.png');
          await File(resultPath).writeAsBytes(resultBytes);

          state = state.copyWith(
            processedCount: state.processedCount + 1,
            results: [...state.results, resultPath],
          );
        } catch (e) {
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            failedPaths: [...state.failedPaths, targetPath],
          );
        }
      }).toList();

      await Future.wait(processingPipelines);

    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return;
    }

    state = state.copyWith(isProcessing: false);
  }
}