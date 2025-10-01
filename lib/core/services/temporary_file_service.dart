import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

/// 负责创建和清理临时文件，确保应用不会留下垃圾文件。
class TemporaryFileService {
  final List<String> _tempFilePaths = [];
  Directory? _tempDir;

  /// 获取临时目录，如果不存在则创建。
  Future<Directory> get _directory async {
    _tempDir ??= await getTemporaryDirectory();
    return _tempDir!;
  }

  /// 创建一个新的、唯一的临时文件路径。
  ///
  /// [prefix] 文件名前缀，例如 "ocr_" 或 "result_"。
  /// [extension] 文件扩展名，例如 ".png"。
  ///
  /// 返回创建的临时文件的完整路径。
  Future<String> create(String prefix, String extension) async {
    final dir = await _directory;
    final fileName = '$prefix${const Uuid().v4()}$extension';
    final path = p.join(dir.path, fileName);
    _tempFilePaths.add(path);
    return path;
  }

  /// 清理所有由本服务创建的临时文件。
  Future<void> clearAll() async {
    // 1. 创建路径列表的副本，以避免在迭代时修改原始列表。
    final pathsToDelete = List<String>.from(_tempFilePaths);
    
    // 2. 立即清空原始列表，这样新的文件可以被安全地创建，不会干扰清理过程。
    _tempFilePaths.clear();

    // 3. 遍历副本以删除文件。
    for (final path in pathsToDelete) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // 忽略删除失败的错误
      }
    }
  }
}

/// Riverpod Provider，用于在应用中访问 TemporaryFileService 的单例。
final temporaryFileServiceProvider = Provider<TemporaryFileService>((ref) {
  final service = TemporaryFileService();
  // 当Provider被销毁时（例如应用退出），自动清理文件
  ref.onDispose(() {
    service.clearAll();
  });
  return service;
});