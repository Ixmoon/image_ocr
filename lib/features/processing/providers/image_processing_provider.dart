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
    final totalStopwatch = Stopwatch()..start();
    final stepStopwatch = Stopwatch();
    final log = (String step, int elapsed) => debugPrint('[PERF][Main Isolate] $step: ${elapsed}ms');

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

      // 1. Prepare all data in parallel on the main isolate
      stepStopwatch.start();
      final allTemplateFieldIds = templates.expand((t) => t.fieldIds).toSet();
      
      // [CRITICAL FIX] Sanitize the TemplateField objects from Hive before sending them to an isolate.
      // [ULTIMATE FIX] Convert all Hive objects to plain, sendable objects.
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
      log('1a. Sanitize Hive Objects', stepStopwatch.elapsedMilliseconds);
      
      stepStopwatch.reset();
      stepStopwatch.start();
      
      // [REFACTOR] Implement Pipelined Parallelism with a unified pool.
      // First, process all templates' data, as it's a shared dependency for all subsequent tasks.
      final templateDataFutures = templates.map((t) async {
        final ocrResponse = await pool.processOcr(t.sourceImagePath);
        if (!ocrResponse.isSuccess) throw Exception('Failed to OCR template: ${t.name}');
        final bytes = await File(t.sourceImagePath).readAsBytes();
        return {'id': t.id, 'ocr': ocrResponse.data as RecognizedText, 'bytes': bytes};
      }).toList();

      final templateResults = await Future.wait(templateDataFutures);
      final templateOcrMap = {for (var r in templateResults) r['id'] as String: r['ocr'] as RecognizedText};
      final templateBytesMap = {for (var r in templateResults) r['id'] as String: r['bytes'] as Uint8List};
      log('1b. All Parallel Template OCR & Read', stepStopwatch.elapsedMilliseconds);

      stepStopwatch.reset();
      stepStopwatch.start();

      // Now, create a complete processing pipeline for each target image.
      // Each pipeline is a Future that performs OCR, composition, and file saving for one image.
      final processingPipelines = targetImagePaths.map((targetPath) async {
        try {
          // 1. OCR for the specific target image
          final targetOcrResponse = await pool.processOcr(targetPath);
          if (!targetOcrResponse.isSuccess) throw Exception('Failed to OCR target: $targetPath');
          final targetOcrResult = targetOcrResponse.data as RecognizedText;

          // 2. Create payload for this image
          final payload = CompositionPayload(
            templates: sanitizedTemplates,
            targetImagePath: targetPath,
            targetOcrResult: targetOcrResult,
            templateOcrResults: templateOcrMap,
            fieldsMap: fieldsMap,
            templateImageBytes: templateBytesMap,
          );

          // 3. Offload composition to the same isolate pool
          final compositionResponse = await pool.processComposition(payload);
          if (!compositionResponse.isSuccess) throw Exception('Failed to compose image: $targetPath');
          final resultBytes = compositionResponse.data as Uint8List;
          
          // 4. Save the result and update state
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

      // A single Future.wait to run all pipelines in parallel.
      await Future.wait(processingPipelines);
      log('2. All Parallel Pipelines', stepStopwatch.elapsedMilliseconds);
      
      totalStopwatch.stop();
      final totalTime = totalStopwatch.elapsedMilliseconds;
      final avgTime = totalTime / targetImagePaths.length;
      debugPrint('[PERF][Main Isolate] >>> Total Batch Time: ${totalTime}ms (${avgTime.toStringAsFixed(2)}ms/image) <<<');


    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return;
    }

    state = state.copyWith(isProcessing: false);
  }
}