import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_ocr/core/router/app_router.dart';
import 'package:gal/gal.dart';
import 'package:image_ocr/core/constants/app_constants.dart';
import 'package:image_ocr/features/processing/models/image_processing_state.dart';
import 'package:permission_handler/permission_handler.dart';

class BatchPreviewScreen extends StatefulWidget {
  final ImageProcessingState processingState;
  const BatchPreviewScreen({super.key, required this.processingState});

  @override
  State<BatchPreviewScreen> createState() => _BatchPreviewScreenState();
}

class _BatchPreviewScreenState extends State<BatchPreviewScreen> {
  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 确保在 build 完成后显示 SnackBar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.processingState.failedPaths.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.processingState.failedPaths.length} 张图片处理失败。'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });
  }

  Future<void> _saveAllToGallery(BuildContext context) async {
    final resultImagePaths = widget.processingState.results;
    if (resultImagePaths.isEmpty) return;

    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) {
      int successCount = 0;
      if (!context.mounted) return;
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
          // 直接调用gal插件保存，无需任何手动文件检查或路径管理
          await Gal.putImage(path, album: AppConstants.imageAlbumName);
          successCount++;
        } catch (e) {
          // Log or handle individual file saving errors if necessary.
        }
      }

      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (!context.mounted) return;
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
    final resultImagePaths = widget.processingState.results;
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.orange, size: 60),
                  SizedBox(height: 16),
                  Text('没有成功处理的图片'),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 9 / 16,
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
          context.push(AppRouter.previewPath, extra: imagePath);
        },
        child: Container(
          color: Colors.black.withAlpha((255 * 0.1).round()),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
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