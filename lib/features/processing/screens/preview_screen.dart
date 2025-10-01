// lib/features/processing/screens/preview_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_ocr/core/constants/app_constants.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

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
    // 检查权限
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相册权限才能保存图片')),
        );
      }
      return;
    }

    try {
      // 直接调用gal插件保存，并使用全局常量指定相册名
      // 无需任何手动文件复制或路径管理
      await Gal.putImage(imagePath, album: AppConstants.imageAlbumName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册的 ${AppConstants.imageAlbumName} 文件夹')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
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