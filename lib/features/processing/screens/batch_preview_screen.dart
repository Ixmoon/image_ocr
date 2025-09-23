// lib/features/processing/screens/batch_preview_screen.dart
import 'dart:io'; // <--- [FIX] 修正了这里的导入语句 (dart.io -> dart:io)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_clone_tool/core/router/app_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';

class BatchPreviewScreen extends StatelessWidget {
  final List<String> resultImagePaths;
  const BatchPreviewScreen({super.key, required this.resultImagePaths});

  Future<void> _saveAllToGallery(BuildContext context) async {
    // 请求更精确的 photos 权限
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) {
      int successCount = 0;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("正在保存..."),
            ],
          ),
        ),
      );

      for (final path in resultImagePaths) {
        try {
          final result = await SaverGallery.saveFile(
            filePath: path,
            fileName: 'processed_image_${DateTime.now().millisecondsSinceEpoch}_$successCount.png',
            skipIfExists: true,
            androidRelativePath: "Pictures/ImageCloneTool",
          );
          if (result.isSuccess) {
            successCount++;
          }
        } catch (e) {
          // 忽略单张图片的保存失败
        }
      }

      if (!context.mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successCount / ${resultImagePaths.length} 张图片已保存到相册')),
      );
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要存储权限才能保存图片')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('处理结果 (${resultImagePaths.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            tooltip: '全部保存到相册',
            onPressed: resultImagePaths.isNotEmpty
                ? () => _saveAllToGallery(context)
                : null,
          ),
        ],
      ),
      body: resultImagePaths.isEmpty
          ? const Center(
              child: Text('没有成功处理的图片'),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // 每行2个，使其更“竖直”
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 9 / 16, // 强制为竖直长方形
              ),
              itemCount: resultImagePaths.length,
              itemBuilder: (context, index) {
                return _ResultGridItem(imagePath: resultImagePaths[index]);
              },
            ),
    );
  }
}

class _ResultGridItem extends StatelessWidget {
  final String imagePath;
  const _ResultGridItem({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: GestureDetector(
        onTap: () {
          // 跳转到功能更全的预览页
          context.push(AppRouter.previewPath, extra: imagePath);
        },
        child: Container(
          color: Colors.black.withOpacity(0.1),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain, // 确保图片完整显示不拉伸
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(Icons.error_outline, color: Colors.red),
              );
            },
          ),
        ),
      ),
    );
  }
}