import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:image_ocr/features/templates/widgets/folder_breadcrumb.dart';

/// 一个可复用的、显示模板和文件夹并处理导航的核心UI组件。
///
/// 它不包含任何对话框逻辑，可以被嵌入到任何地方（例如对话框、悬浮窗等）。
/// 它总是以多选模式工作。
class TemplateSelector extends ConsumerStatefulWidget {
  /// 当用户选择或取消选择一个模板时触发的回调。
  final ValueChanged<Template> onTemplateSelectionChanged;

  /// 当前已选择的模板集合，用于在UI上高亮显示。
  final Set<Template> selectedTemplates;
  
  /// 已经从外部传入且不可更改的模板ID。
  final Set<String> alreadySelectedIds;

  /// 是否启用分页功能（仅在悬浮窗中使用）
  final bool enablePagination;

  const TemplateSelector({
    super.key,
    required this.onTemplateSelectionChanged,
    required this.selectedTemplates,
    this.alreadySelectedIds = const {},
    this.enablePagination = false,
  });

  @override
  ConsumerState<TemplateSelector> createState() => _TemplateSelectorState();
}

class _TemplateSelectorState extends ConsumerState<TemplateSelector> {
  int _currentPage = 0;
  int _itemsPerPage = 8; // 默认值，会动态计算

  @override
  Widget build(BuildContext context) {
    // Handle the async nature of the navigation stack provider
    final navigationStackAsync = ref.watch(folderNavigationStackProvider);

    return navigationStackAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('无法加载导航: $err')),
      data: (navigationStack) {
        final currentFolderId = navigationStack.last;
        final contentsAsync = ref.watch(folderContentsProvider(currentFolderId));

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 使用独立的、可复用的面包屑组件
            const FolderBreadcrumb(),
            const Divider(height: 1),
            Flexible(
              child: contentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('加载失败: $err')),
                data: (contents) {
                  if (contents.isEmpty) return const Center(child: Text('此文件夹为空'));

                  if (widget.enablePagination) {
                    // 分页模式（悬浮窗）
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        // 動態計算每頁能顯示的項目數量
                        _calculateItemsPerPage(constraints);
                        
                        final totalItems = contents.length;
                        // 确保当前页在有效范围内
                        _ensureValidPage(totalItems);
                        
                        final totalPages = (totalItems / _itemsPerPage.toDouble()).ceil();
                        final startIndex = _currentPage * _itemsPerPage;
                        final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
                        final currentPageItems = contents.sublist(startIndex, endIndex);
                        
                        return Column(
                          children: [
                            // 列表内容
                            Expanded(
                              child: ListView.builder(
                                // 为悬浮窗禁用滚动，避免手势冲突
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: currentPageItems.length,
                                itemBuilder: (context, index) {
                                  final item = currentPageItems[index];
                                  if (item is Folder) {
                                    return _buildFolderItem(ref, item);
                                  } else if (item is Template) {
                                    return _buildTemplateItem(item);
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ),
                            // 分页按钮在下方
                            if (totalPages > 1) _buildPaginationControls(totalPages),
                          ],
                        );
                      },
                    );
                  } else {
                    // 正常滚动模式（其他地方）
                    return ListView.builder(
                      // 允许正常滚动
                      itemCount: contents.length,
                      itemBuilder: (context, index) {
                        final item = contents[index];
                        if (item is Folder) {
                          return _buildFolderItem(ref, item);
                        } else if (item is Template) {
                          return _buildTemplateItem(item);
                        }
                        return const SizedBox.shrink();
                      },
                    );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 根据可用空间动态计算每页能显示的项目数量
  void _calculateItemsPerPage(BoxConstraints constraints) {
    // ListTile的标准高度大约是56dp
    const double itemHeight = 56.0;
    // 分页控件的高度大约是48dp
    const double paginationHeight = 48.0;
    // 预留一些边距
    const double margin = 16.0;
    
    // 计算可用于显示列表项的高度
    final availableHeight = constraints.maxHeight - paginationHeight - margin;
    
    // 计算能显示的项目数量，至少显示1个
    final calculatedItems = (availableHeight / itemHeight).floor();
    _itemsPerPage = calculatedItems > 0 ? calculatedItems : 1;
    
    // 如果当前页超出了范围，重置到最后一页
    // 这里需要在setState中调用，但为了避免在build中调用setState，
    // 我们在didUpdateWidget中处理页面重置
  }

  /// 构建翻页控制按钮
  Widget _buildPaginationControls(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 上一页按钮
          IconButton(
            onPressed: _currentPage > 0 ? _previousPage : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一页',
          ),
          // 页码显示
          Text(
            '${_currentPage + 1} / $totalPages',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // 下一页按钮
          IconButton(
            onPressed: _currentPage < totalPages - 1 ? _nextPage : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }

  /// 上一页
  void _previousPage() {
    if (_currentPage > 0) {
      setState(() {
        _currentPage--;
      });
    }
  }

  /// 下一页
  void _nextPage() {
    setState(() {
      _currentPage++;
    });
  }

  /// 重置页面到第一页（文件夹导航時使用）
  void _resetToFirstPage() {
    if (_currentPage != 0) {
      setState(() {
        _currentPage = 0;
      });
    }
  }

  @override
  void didUpdateWidget(TemplateSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当内容可能发生变化时，重置到第一页
    _resetToFirstPage();
  }

  /// 确保当前页在有效范围内
  void _ensureValidPage(int totalItems) {
    if (_itemsPerPage > 0) {
      final maxPage = ((totalItems / _itemsPerPage.toDouble()).ceil() - 1).clamp(0, double.infinity).toInt();
      if (_currentPage > maxPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentPage = maxPage;
            });
          }
        });
      }
    }
  }

  Widget _buildFolderItem(WidgetRef ref, Folder folder) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name),
      // 点击文件夹时，直接操作全局Provider并重置页面
      onTap: () {
        // Now calling an async method
        ref.read(folderNavigationStackProvider.notifier).push(folder.id).then((_) {
          _resetToFirstPage();
        });
      },
    );
  }

  Widget _buildTemplateItem(Template template) {
    final isExternallySelected = widget.alreadySelectedIds.contains(template.id);
    final isSelected = widget.selectedTemplates.any((t) => t.id == template.id);

    return CheckboxListTile(
      title: Text(template.name),
      value: isSelected,
      enabled: !isExternallySelected,
      onChanged: (bool? value) {
        if (isExternallySelected) return;
        widget.onTemplateSelectionChanged(template);
      },
    );
  }
}