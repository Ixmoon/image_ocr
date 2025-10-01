import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';
import 'package:image_ocr/features/processing/services/processing_isolate_pool_service.dart';
import 'package:image_ocr/features/processing/services/processing_worker.dart';
import 'package:hive/hive.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/models/template_field.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as p;

part 'image_processing_provider.g.dart';

// 存储处理后的图片数据，避免临时文件
final Map<String, Uint8List> _processedImageData = {};

@Riverpod()
class ImageProcessing extends _$ImageProcessing {
  @override
  ImageProcessingState build() {
    return ImageProcessingState.initial();
  }

  Future<ImageProcessingState> processBatch({
    required List<Template> templates,
    required List<String> targetImagePaths,
  }) async {
    // 清理之前的处理数据
    _processedImageData.clear();
    
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
      // final tempFileService = ref.read(temporaryFileServiceProvider); // No longer needed
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
  
      // 优化：并行解码和OCR，避免重复解码
      final decodeAndOcrFutures = allImagePaths.map((path) async {
        final decodeResponse = await pool.dispatch(TaskType.decode, path);
        if (!decodeResponse.isSuccess) throw Exception('Failed to decode image: $path');
        
        final imageBytes = decodeResponse.data as Uint8List;
        final payload = OcrPayload(imageBytes: imageBytes, imagePath: path);
        final ocrResponse = await pool.dispatch(TaskType.ocr, payload);
        if (!ocrResponse.isSuccess) throw Exception('Failed to OCR image: $path');
        
        final (text, size) = ocrResponse.data as (RecognizedText, Size);
        return MapEntry(path, {
          'bytes': imageBytes,
          'ocr': text,
          'size': size,
        });
      });
      
      final allResults = Map.fromEntries(await Future.wait(decodeAndOcrFutures));
      final allDecodedBytes = allResults.map((key, value) => MapEntry(key, value['bytes'] as Uint8List));
      final allOcrResults = allResults.map((key, value) => MapEntry(key, value['ocr'] as RecognizedText));

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
          if (!compositionResponse.isSuccess) {
            // --- FINAL FIX: Propagate the original error from the isolate ---
            throw Exception(compositionResponse.error ?? 'Worker returned a failure without an error message for $targetPath');
          }
          final resultBytes = compositionResponse.data as Uint8List;

          // --- 优化：直接返回处理后的字节数据，避免临时文件 ---
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            results: [...state.results, targetPath], // 使用原路径作为标识
            // 将处理后的字节数据存储在状态中，供后续直接使用
          );
          
          // 将处理后的数据暂存，供main.dart使用
          _processedImageData[targetPath] = resultBytes;
        } catch (e) {
          state = state.copyWith(
            processedCount: state.processedCount + 1,
            failedPaths: [...state.failedPaths, targetPath],
            // --- FINAL FIX: Record the specific error message ---
            error: e.toString(),
          );
        }
      }).toList();

      await Future.wait(processingPipelines);

    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return state; // 返回最终状态
    }

    state = state.copyWith(isProcessing: false);
    return state; // 返回最终状态
  }
  
  /// 获取处理后的图片数据
  Uint8List? getProcessedImageData(String originalPath) {
    return _processedImageData[originalPath];
  }
  
  /// 清理处理后的图片数据
  void clearProcessedImageData(String originalPath) {
    _processedImageData.remove(originalPath);
  }
}