import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_clone_tool/core/router/app_router.dart';
import 'package:image_clone_tool/features/processing/models/image_processing_state.dart';
import 'package:image_clone_tool/features/processing/providers/image_processing_provider.dart';
import 'package:image_clone_tool/features/templates/models/template.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

// 应用模板到目标图片的屏幕，支持批量处理
class ApplyTemplateScreen extends ConsumerStatefulWidget {
  final Template template;
  const ApplyTemplateScreen({super.key, required this.template});

  @override
  ConsumerState<ApplyTemplateScreen> createState() => _ApplyTemplateScreenState();
}

class _ApplyTemplateScreenState extends ConsumerState<ApplyTemplateScreen> {
  // 修复：使用final，并通过setState创建新列表来更新
  List<String> _targetImagePaths = [];

  Future<void> _pickMultipleImages() async {
    // 1. 请求权限
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相册权限才能选择图片')),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    setState(() {
      _targetImagePaths = [
        ..._targetImagePaths,
        ...pickedFiles.map((file) => file.path)
      ];
    });
  }

  void _removeImage(int index) {
    setState(() {
      // 创建一个移除了指定项的新列表
      _targetImagePaths = List.from(_targetImagePaths)..removeAt(index);
    });
  }

  void _startProcessing() {
    if (_targetImagePaths.isEmpty) return;
    ref.read(imageProcessingProvider.notifier).processBatch(
          template: widget.template,
          targetImagePaths: _targetImagePaths,
        );
  }

  @override
  Widget build(BuildContext context) {
    // 监听图像处理的状态，用于显示进度和处理结果
    ref.listen<ImageProcessingState>(imageProcessingProvider, (previous, next) {
      // 当处理完成时，跳转到批量预览页面
      if (previous?.isProcessing == true && !next.isProcessing) {
        // 使用pushReplacement避免在预览页返回时回到处理页面
        context.pushReplacement(AppRouter.batchPreviewPath, extra: next.results);
      }
      // 如果处理出错，显示错误提示
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('处理失败: ${next.error}')),
        );
      }
    });

    final processingState = ref.watch(imageProcessingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('应用模板: ${widget.template.name}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _targetImagePaths.isEmpty
                ? _EmptyImagePicker(onPressed: _pickMultipleImages)
                : _ImageGrid(
                    imagePaths: _targetImagePaths,
                    onRemove: _removeImage,
                  ),
          ),
          // 底部处理按钮和进度显示
          if (processingState.isProcessing)
            const _ProcessingIndicator()
          else
            _ActionFooter(
              onAdd: _pickMultipleImages,
              onProcess: _targetImagePaths.isNotEmpty ? _startProcessing : null,
              imageCount: _targetImagePaths.length,
            ),
        ],
      ),
    );
  }
}

// 空状态下的图片选择提示
class _EmptyImagePicker extends StatelessWidget {
  final VoidCallback onPressed;
  const _EmptyImagePicker({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_search, size: 80, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 16),
          Text('选择目标图片', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('添加一张或多张图片以应用模板'),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('选择图片'),
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}

// 显示已选图片网格的组件
class _ImageGrid extends StatelessWidget {
  final List<String> imagePaths;
  final ValueChanged<int> onRemove;
  const _ImageGrid({required this.imagePaths, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: imagePaths.length,
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: GridTile(
            header: Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  margin: const EdgeInsets.all(4.0),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
            child: GestureDetector(
              onTap: () => context.push(AppRouter.previewPath, extra: imagePaths[index]),
              child: Container(
                color: Colors.black.withOpacity(0.1),
                child: Image.file(
                  File(imagePaths[index]),
                  fit: BoxFit.contain, // 确保图片完整显示不拉伸
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// 底部操作栏
class _ActionFooter extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback? onProcess;
  final int imageCount;

  const _ActionFooter({
    required this.onAdd,
    required this.onProcess,
    required this.imageCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: onAdd,
            child: const Icon(Icons.add_photo_alternate_outlined),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow_outlined),
              label: Text('开始处理 ($imageCount)'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onProcess,
            ),
          ),
        ],
      ),
    );
  }
}

// 处理中进度指示器
class _ProcessingIndicator extends ConsumerWidget {
  const _ProcessingIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageProcessingProvider);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: state.progress),
          const SizedBox(height: 8),
          Text('正在处理 ${state.processedCount} / ${state.totalCount}...'),
        ],
      ),
    );
  }
}