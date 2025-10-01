import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';

/// 一个可复用的、响应全局导航状态的文件夹面包屑组件。
class FolderBreadcrumb extends ConsumerWidget {
  const FolderBreadcrumb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(folderPathProvider);

    return SizedBox(
      height: 30,
      child: pathAsync.when(
        data: (path) {
          // 使用 ListView.builder 提高性能
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            scrollDirection: Axis.horizontal,
            itemCount: path.length,
            separatorBuilder: (context, index) => const Icon(
              Icons.chevron_right,
              color: Colors.grey,
              size: 16,
            ),
            itemBuilder: (context, index) {
              final folder = path[index];
              final isLast = index == path.length - 1;

              // 点击面包屑项，导航到对应的层级
              final onTap = isLast
                  ? null // 最后一项（当前目录）不可点击
                  : () => ref.read(folderNavigationStackProvider.notifier).popTo(index);

              return InkWell(
                onTap: onTap,
                child: Center(
                  child: Text(
                    folder?.name ?? '根目录',
                    style: TextStyle(
                      color: isLast ? Colors.black : Colors.blue,
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: SizedBox(height: 1, width: 80, child: LinearProgressIndicator())),
        error: (e, s) => const SizedBox.shrink(),
      ),
    );
  }
}