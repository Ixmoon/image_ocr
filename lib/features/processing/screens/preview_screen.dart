// lib/features/processing/screens/preview_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class PreviewScreen extends StatelessWidget {
  final String imagePath;
  final bool canReplace;

  const PreviewScreen({
    super.key,
    required this.imagePath,
    this.canReplace = false,
  });

  Future<void> _replaceImage(BuildContext context) async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null && context.mounted) {
      context.pop(pickedFile.path);
    }
  }

  Future<void> _saveToGallery(BuildContext context) async {
    // 请求更精确的 photos 权限
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) {
      try {
        // --- [FIX 1] 修正API调用 ---
        // 使用 saveFile 并提供正确的命名参数
        final result = await SaverGallery.saveFile(
          filePath: imagePath,
          fileName: 'processed_image_${DateTime.now().millisecondsSinceEpoch}.png',
          skipIfExists: true, // 安全的默认值
          androidRelativePath: "Pictures/ImageOCR",
        );

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.isSuccess ? '已保存到相册' : '保存失败')),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要存储权限才能保存图片')),
      );
    }
  }

  // --- [FIX 2] 更新为新的 Share Plus API ---
  Future<void> _shareImage(BuildContext context) async {
    await Share.shareXFiles([XFile(imagePath)], text: '分享图片');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.file(File(imagePath)),
            ),
          ),
          // 在左上角添加一个半透明的返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withAlpha((255 * 0.3).round()),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black.withAlpha(128),
        elevation: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (canReplace)
              TextButton.icon(
                icon: const Icon(Icons.flip_camera_ios_outlined),
                label: const Text('替换图片'),
                onPressed: () => _replaceImage(context),
              ),
            TextButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享'),
              onPressed: () => _shareImage(context),
            ),
            TextButton.icon(
              icon: const Icon(Icons.save_alt_outlined),
              label: const Text('保存到相册'),
              onPressed: () => _saveToGallery(context),
            ),
          ],
        ),
      ),
    );
  }
}