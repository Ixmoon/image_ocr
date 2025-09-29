import 'dart:developer';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/overlay/template_selector_widget.dart';
import 'package:image_ocr/features/templates/models/folder.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';

class OverlayWidget extends ConsumerStatefulWidget {
  const OverlayWidget({Key? key}) : super(key: key);

  @override
  ConsumerState<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends ConsumerState<OverlayWidget> {
  static const String _kPortNameOverlay = 'OVERLAY';
  static const String _kPortNameHome = 'UI';
  final _receivePort = ReceivePort();
  SendPort? homePort;
  String? latestMessageFromOverlay;
  bool isExpanded = false;

  @override
  void initState() {
    super.initState();
    if (homePort != null) return;
    final res = IsolateNameServer.registerPortWithName(
      _receivePort.sendPort,
      _kPortNameOverlay,
    );
    log("$res : OVERLAY_REGISTERED");
    _receivePort.listen((message) {
      log("message from UI: $message");
      if (mounted) {
        setState(() {
          latestMessageFromOverlay = 'message from UI: $message';
        });
      }
    });
  }

  Future<void> _sendMessageToMain() async {
    final selectedTemplate = ref.read(overlaySelectedTemplateProvider);
    if (selectedTemplate == null) {
      log("没有选择模板");
      return;
    }

    homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
    if (homePort != null) {
      setState(() {
        latestMessageFromOverlay = "正在处理截屏...";
      });
      
      homePort?.send([
        'request_screenshot_processing',
        {
          'templateId': selectedTemplate.id,
          'templateName': selectedTemplate.name,
        }
      ]);
      
      await Future.delayed(const Duration(milliseconds: 1000));
      await FlutterOverlayWindow.closeOverlay();
    } else {
      log("无法连接到主应用");
    }
  }

  Future<void> _toggleExpansion() async {
    if (isExpanded) {
      await FlutterOverlayWindow.resizeOverlay(60, 60, true);
      setState(() {
        isExpanded = false;
      });
    } else {
      await FlutterOverlayWindow.resizeOverlay(350, 500, true);
      setState(() {
        isExpanded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: isExpanded ? _buildExpandedView() : _buildCollapsedView(),
      ),
    );
  }

  Widget _buildCollapsedView() {
    return GestureDetector(
      onTap: _toggleExpansion,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blue,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.screenshot_monitor,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedView() {
    return Container(
      width: 350,
      height: 500,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          // 标题栏（可拖动区域）
          Container(
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16.0),
                  child: Text(
                    '选择模板',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _toggleExpansion,
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // 模板选择器（使用按钮翻页）
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const PaginatedTemplateSelector(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 截屏并处理按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _sendMessageToMain,
                      child: const Text('截屏并处理'),
                    ),
                  ),
                  // 状态消息
                  if (latestMessageFromOverlay != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      latestMessageFromOverlay!,
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 分页的模板选择器，使用按钮翻页避免滚动手势冲突
class PaginatedTemplateSelector extends ConsumerStatefulWidget {
  const PaginatedTemplateSelector({super.key});

  @override
  ConsumerState<PaginatedTemplateSelector> createState() => _PaginatedTemplateSelectorState();
}

class _PaginatedTemplateSelectorState extends ConsumerState<PaginatedTemplateSelector> {
  int currentPage = 0;
  final int itemsPerPage = 5;
  late final List<String?> _navigationStack;

  @override
  void initState() {
    super.initState();
    // Initialize navigation stack with the root folder.
    _navigationStack = [ref.read(currentFolderIdProvider)];
  }

  @override
  Widget build(BuildContext context) {
    final currentFolderId = _navigationStack.last;
    final contentsAsync = ref.watch(folderContentsProvider(currentFolderId));
    final selectedTemplate = ref.watch(overlaySelectedTemplateProvider);

    return contentsAsync.when(
      loading: () => const Center(
        child: SizedBox(
          width: 16, 
          height: 16, 
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (err, stack) => const Center(
        child: Text(
          '加载失败',
          style: TextStyle(fontSize: 10),
        ),
      ),
      data: (contents) {
        if (contents.isEmpty) {
          return const Center(
            child: Text(
              '此文件夹为空',
              style: TextStyle(fontSize: 10),
            ),
          );
        }

        final totalItems = contents.length;
        final totalPages = (totalItems / itemsPerPage).ceil();
        final startIndex = currentPage * itemsPerPage;
        final endIndex = (startIndex + itemsPerPage).clamp(0, totalItems);
        final currentItems = contents.sublist(startIndex, endIndex);

        return Column(
          children: [
            // 导航和翻页控制栏
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  // 返回按钮
                  if (_navigationStack.length > 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 16),
                      onPressed: () => setState(() {
                        _navigationStack.removeLast();
                        currentPage = 0;
                      }),
                    ),
                  // 翻页控制
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 16),
                          onPressed: currentPage > 0
                              ? () => setState(() => currentPage--)
                              : null,
                        ),
                        Text(
                          '${currentPage + 1} / $totalPages',
                          style: const TextStyle(fontSize: 12),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 16),
                          onPressed: currentPage < totalPages - 1
                              ? () => setState(() => currentPage++)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  // 占位保持对称
                  if (_navigationStack.length <= 1)
                    const SizedBox(width: 48),
                ],
              ),
            ),
            // 当前页内容
            Expanded(
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(), // 禁用滚动
                padding: const EdgeInsets.all(4.0),
                itemCount: currentItems.length,
                itemBuilder: (context, index) {
                  final item = currentItems[index];
                  if (item is Folder) {
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 1.0),
                      child: InkWell(
                        onTap: () {
                          // 进入子文件夹时重置页码
                          setState(() {
                            currentPage = 0;
                            _navigationStack.add(item.id);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 14, color: Colors.orange),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  } else if (item is Template) {
                    final template = item;
                    final isSelected = selectedTemplate?.id == template.id;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 1.0),
                      child: InkWell(
                        onTap: () {
                          ref.read(overlaySelectedTemplateProvider.notifier).state = template;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.shade100 : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                            border: isSelected ? Border.all(color: Colors.blue, width: 1) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                size: 14,
                                color: isSelected ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  template.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                    color: isSelected ? Colors.blue.shade700 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
