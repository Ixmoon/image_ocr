import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_clone_tool/features/processing/services/ocr_service.dart';
import 'package:image_clone_tool/features/templates/models/template_field.dart';
import 'package:image_clone_tool/features/templates/providers/template_providers.dart';
import 'package:image_clone_tool/widgets/interactive_image_viewer.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

// 定义字段和“值”区域的屏幕
class DefineFieldScreen extends ConsumerStatefulWidget {
  final TemplateField? fieldToEdit; // 接收待编辑的字段
  const DefineFieldScreen({super.key, this.fieldToEdit});

  @override
  ConsumerState<DefineFieldScreen> createState() => _DefineFieldScreenState();
}

class _DefineFieldScreenState extends ConsumerState<DefineFieldScreen> {
  final _fieldNameController = TextEditingController();
  RecognizedText? _ocrResult;
  Rect? _labelRect;
  Rect? _valueRect;
  bool _isOcrLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.fieldToEdit != null) {
      // --- 编辑模式 ---
      final field = widget.fieldToEdit!;
      _fieldNameController.text = field.name;
      _labelRect = field.labelRect;
      _valueRect = field.valueRect;
      _isOcrLoading = false; // 编辑模式不需要OCR
    } else {
      // --- 创建模式 ---
      _runOcr();
    }
  }

  Future<void> _runOcr() async {
    final sourceImagePath = ref.read(templateCreationProvider)?.sourceImagePath;
    // --- [日志 7] ---
    //print('[DEBUG] DefineFieldScreen: _runOcr started. Image path: $sourceImagePath');
    if (sourceImagePath == null) {
      setState(() => _isOcrLoading = false);
      // --- [日志 8] ---
      //print('[WARNING] DefineFieldScreen: Source image path is null. OCR aborted.');
      return;
    }

    final ocrService = ref.read(ocrServiceProvider);
    final result = await ocrService.processImage(sourceImagePath);
    if (mounted) {
      setState(() {
        _ocrResult = result;
        _isOcrLoading = false;
        // --- [日志 9] ---
        //print('[DEBUG] DefineFieldScreen: OCR finished. Result has ${_ocrResult?.blocks.length ?? 0} blocks.');
      });
    }
  }

  Future<void> _findAndHighlightLabel() async {
    //print('[DEBUG] DefineFieldScreen: "放大镜" clicked. Searching for text: "${_fieldNameController.text}"');
    
    if (_ocrResult == null || _fieldNameController.text.isEmpty) {
      //print('[WARNING] DefineFieldScreen: Search aborted. OCR result is null or search text is empty.');
      return;
    }
    
    final searchText = _fieldNameController.text;
    TextBlock? foundBlock;
    for (final block in _ocrResult!.blocks) {
      if (block.text.contains(searchText)) {
        foundBlock = block;
        //print('[DEBUG] DefineFieldScreen: Found matching text block: "${block.text}"');
        break;
      }
    }

    if (foundBlock != null) {
      // 异步获取图片尺寸
      final sourceImagePath = ref.read(templateCreationProvider)!.sourceImagePath;
      final imageFile = File(sourceImagePath);
      final image = await img.decodeImage(await imageFile.readAsBytes());
      
      if (image == null) {
        //print('[ERROR] DefineFieldScreen: Could not decode image to get its width.');
        return;
      }

      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();
      final labelBox = foundBlock.boundingBox;

      setState(() {
        _labelRect = labelBox;
        
        // “拦腰斩断”式预测逻辑 - 遵从最终指令，并添加边界检查
        const double verticalPadding = 5.0;
        
        // 确保 top 不会小于 0
        final double top = (labelBox.top - verticalPadding).clamp(0.0, imageHeight);
        
        // 确保 bottom 不会超过图片高度
        final double bottom = (labelBox.bottom + verticalPadding).clamp(0.0, imageHeight);

        // 根据安全的 top 和 bottom 计算最终的高度
        final double height = bottom - top;

        _valueRect = Rect.fromLTWH(
          0.0,
          top,
          imageWidth,
          height,
        );
        //print('[DEBUG] DefineFieldScreen: Highlighted labelRect: $_labelRect and predicted valueRect: $_valueRect');
      });
    } else {
      //print('[WARNING] DefineFieldScreen: Text "$searchText" not found in OCR result.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('在图片中未找到该文本')),
      );
    }
  }

  Future<void> _saveField() async {
    // --- [日志 15] ---
    //print('[DEBUG] DefineFieldScreen: Save button clicked.');
    if (_valueRect == null || _fieldNameController.text.isEmpty || _labelRect == null) {
      // --- [日志 16] ---
      //print('[ERROR] DefineFieldScreen: Save aborted. Missing required data. valueRect: $_valueRect, labelRect: $_labelRect, fieldName: "${_fieldNameController.text}"');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('错误：缺少字段名或未定义标签/值区域')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final template = ref.read(templateCreationProvider)!;
      // --- [日志 17] ---
      //print('[DEBUG] DefineFieldScreen: Cropping image with valueRect: $_valueRect');
      final imageBytes = await File(template.sourceImagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) throw Exception('无法解码源图片');

      final croppedImage = img.copyCrop(
        image,
        x: _valueRect!.left.toInt(),
        y: _valueRect!.top.toInt(),
        width: _valueRect!.width.toInt(),
        height: _valueRect!.height.toInt(),
      );
      
      final newField = TemplateField(
        // 如果是编辑模式，使用旧ID；如果是创建模式，生成新ID
        id: widget.fieldToEdit?.id ?? const Uuid().v4(),
        name: _fieldNameController.text,
        labelRect: _labelRect!,
        valueRect: _valueRect!,
        valueImageBytes: img.encodePng(croppedImage),
      );
      // --- [日志 18] ---
      //print('[DEBUG] DefineFieldScreen: Created new TemplateField with id: ${newField.id}. Calling provider to save...');

      await ref.read(templateCreationProvider.notifier).addOrUpdateField(newField);
      
      // --- [日志 19] ---
      //print('[DEBUG] DefineFieldScreen: Provider save call finished. Popping screen.');

      if (mounted) context.pop();

    } catch (e) {
      // --- [日志 20] ---
      //print('[ERROR] DefineFieldScreen: _saveField failed with exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存字段失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceImagePath = ref.watch(templateCreationProvider)?.sourceImagePath;

    if (sourceImagePath == null) {
      return const Scaffold(body: Center(child: Text('错误：未找到源图片')));
    }

    final canSave = _valueRect != null && _fieldNameController.text.isNotEmpty && !_isSaving;
    
    // 将“值”区域放入高亮列表（黄色）
    final highlights = <Rect>[
      if (_valueRect != null) _valueRect!,
    ];

    return Scaffold(
      appBar: AppBar(
        // 根据是否在编辑模式显示不同标题
        title: Text(widget.fieldToEdit == null ? '定义新字段' : '编辑字段'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '保存字段',
              onPressed: canSave ? _saveField : null,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _fieldNameController,
              decoration: InputDecoration(
                labelText: '输入字段名 (如: 姓名)',
                hintText: '输入后点击右侧搜索按钮定位',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _findAndHighlightLabel,
                  tooltip: '在图片中定位标签',
                ),
              ),
            ),
          ),
          Expanded(
            child: _isOcrLoading
                ? const Center(child: CircularProgressIndicator())
                : InteractiveImageViewer(
                    imagePath: sourceImagePath,
                    labelRect: _labelRect, // 将标签框（红色）单独传递
                    highlightRects: highlights,
                    initialSelection: _valueRect,
                    onSelectionChanged: (newRect) {
                      // 根据最终指令，此回调不再需要更新任何状态
                    },
                  ),
          ),
        ],
      ),
    );
  }
}