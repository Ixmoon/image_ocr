import 'package:flutter/painting.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// [最终正确实现] 在OCR结果中查找与给定文本最匹配的文本行作为锚点。
TextLine? findAnchorLine({
  required RecognizedText ocrResult,
  required String searchText,
}) {
  if (searchText.isEmpty) return null;

  final cleanSearchText = searchText.replaceAll(' ', '');
  if (cleanSearchText.isEmpty) return null;
  

  // 遍历所有的块和行
  for (final block in ocrResult.blocks) {
    for (final line in block.lines) {
      final cleanLineText = line.text.replaceAll(' ', '');
      
      // 如果找到第一个包含搜索文本的行，就立即返回它
      if (cleanLineText.contains(cleanSearchText)) {
        return line;
      }
    }
  }

  // 如果遍历完所有行都没有找到，则返回null
  return null;
}

/// 根据给定的标签锚点行，推断出对应的值区域。
///
/// [anchorLine]: 已找到的标签文本行。
/// [imageSize]: 整个图片的尺寸，用于边界检查。
/// 返回一个代表值区域的 [Rect]。
Rect findValueRectForAnchorLine({
  required TextLine anchorLine,
  required Size imageSize,
}) {
  // “拦腰斩断”式预测逻辑
  const double verticalPadding = 5.0;
  final labelBox = anchorLine.boundingBox;
  final double top = (labelBox.top - verticalPadding).clamp(0.0, imageSize.height);
  final double bottom = (labelBox.bottom + verticalPadding).clamp(0.0, imageSize.height);
  
  return Rect.fromLTWH(
    0.0,
    top,
    imageSize.width,
    bottom - top,
  );
}