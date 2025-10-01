import 'dart:isolate';
import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:image_ocr/features/templates/widgets/template_selector.dart';

enum OverlayState { collapsed, expanded, capturing, invisible }

class OverlayWidget extends ConsumerStatefulWidget {
  const OverlayWidget({super.key});

  @override
  ConsumerState<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends ConsumerState<OverlayWidget> {
  static const String _kPortNameOverlay = 'OVERLAY';
  static const String _kPortNameHome = 'UI';
  final _receivePort = ReceivePort();
  SendPort? homePort;
  OverlayState _state = OverlayState.collapsed;
  OverlayState _previousState = OverlayState.collapsed;
  
  // This channel is not used here, commands are sent via Isolate ports.
  // static const MethodChannel _screenshotChannel = MethodChannel('com.example.image_ocr/screenshot');

  @override
  void initState() {
    super.initState();
    homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
    IsolateNameServer.registerPortWithName(_receivePort.sendPort, _kPortNameOverlay);
    
    // 监听来自主应用的命令
    _receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final command = message['command'] as String?;
        switch (command) {
          case 'close_overlay':
            FlutterOverlayWindow.closeOverlay();
            break;
          case 'update_state':
            // This logic might need adjustment based on the new state machine
            break;
          case 'screenshot_done':
            // Screenshot is done, restore previous state
            final wasExpanded = message['wasExpanded'] as bool? ?? false;
            setState(() {
              _state = wasExpanded ? OverlayState.expanded : OverlayState.collapsed;
            });
            _resizeOverlay();
            break;
        }
      }
    });
    
    // 定期检查主应用连接状态
    _startHeartbeat();
  }
  
  /// 定期检查与主应用的连接
  void _startHeartbeat() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
      if (homePort == null) {
        // 连接丢失，尝试重新建立
        debugPrint('Lost connection to main app, attempting to reconnect...');
      }
    });
  }

  /// 截屏处理逻辑 (V2: 清晰分离命令)
  Future<void> _handleScreenshot() async {
    try {
      _previousState = _state;
      
      setState(() {
        _state = OverlayState.invisible;
      });
      await _resizeOverlay();
      
      // --- 核心修复：根据是否选择模板，发送不同命令 ---
      final selectedTemplates = ref.read(selectedTemplatesForProcessingProvider);
      
      if (selectedTemplates.isNotEmpty) {
        // 截屏并处理
        await _sendMessageToMain('request_screenshot_and_process', {
          'wasExpanded': _previousState == OverlayState.expanded,
          'templates': selectedTemplates.map((t) => {'templateId': t.id}).toList(),
        });
      } else {
        // 仅截屏
        await _sendMessageToMain('request_screenshot_only', {
          'wasExpanded': _previousState == OverlayState.expanded,
        });
      }
      
      // 恢复状态的逻辑现在由主应用在处理完成后���过 'screenshot_done' 命令触发
      // 因此这里不再需要手动恢复
      
    } catch (e) {
      debugPrint('截屏请求失败: $e');
      // 出错时也要恢复状态
      await _restorePreviousState();
    }
  }

  /// 向主应用发送消息
  Future<void> _sendMessageToMain(String command, Map<String, dynamic> payload) async {
    homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
    if (homePort != null) {
      homePort!.send({
        'command': command,
        'payload': payload,
      });
      debugPrint('Message sent to main: $command');
    } else {
      debugPrint('Failed to send message: Cannot connect to main app.');
      // 可以考虑在这里增加一些错误提示，比如弹出一个Toast
      throw Exception('无法连接到主应用');
    }
  }
  
  /// 恢复到之前的状态
  Future<void> _restorePreviousState() async {
    setState(() {
      _state = _previousState;
    });
    await _resizeOverlay();
  }

  Future<void> _toggleExpansion() async {
    setState(() {
      _state = (_state == OverlayState.collapsed)
          ? OverlayState.expanded
          : OverlayState.collapsed;
    });
    await _resizeOverlay();
  }

  Future<void> _resizeOverlay() async {
    switch (_state) {
      case OverlayState.collapsed:
        await FlutterOverlayWindow.resizeOverlay(60, 60, true);
        break;
      case OverlayState.expanded:
        await FlutterOverlayWindow.resizeOverlay(350, 600, true);
        break;
      case OverlayState.capturing:
        await FlutterOverlayWindow.resizeOverlay(80, 80, true);
        break;
      case OverlayState.invisible:
        await FlutterOverlayWindow.resizeOverlay(1, 1, true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- [CRITICAL FIX] Wrap the entire overlay in a MaterialApp ---
    // This provides the necessary Overlay context for widgets like Tooltip to function.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: Colors.transparent,
        child: _buildOverlayContent(),
      ),
    );
  }

  Widget _buildOverlayContent() {
    switch (_state) {
      case OverlayState.collapsed:
        return _buildCollapsedView();
      case OverlayState.expanded:
        return _buildExpandedView();
      case OverlayState.capturing:
        return _buildCapturingView();
      case OverlayState.invisible:
        return _buildInvisibleView();
    }
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

  Widget _buildCapturingView() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.deepPurple.withOpacity(0.8),
      ),
      child: const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildInvisibleView() {
    return Container(
      width: 1,
      height: 1,
      color: Colors.transparent,
    );
  }

  Widget _buildExpandedView() {
    final selectedTemplates = ref.watch(selectedTemplatesForProcessingProvider);

    return Container(
      width: 350,
      height: 600,
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
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: Text(
                      '已选 ${selectedTemplates.length} 个模板',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // --- [NEW] Minimize Button ---
                IconButton(
                  icon: const Icon(Icons.minimize, color: Colors.white),
                  tooltip: '最小化',
                  onPressed: _toggleExpansion, // Minimize action is the same as toggling expansion
                ),
                // --- [CHANGED] Close Button ---
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: '关闭悬浮窗',
                  onPressed: () async {
                    // This now permanently closes the overlay for the session.
                    await FlutterOverlayWindow.closeOverlay();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TemplateSelector(
              selectedTemplates: selectedTemplates,
              enablePagination: true, // 在悬浮窗中启用分页功能
              onTemplateSelectionChanged: (template) {
                final notifier = ref.read(selectedTemplatesForProcessingProvider.notifier);
                final currentSelection = Set<Template>.from(notifier.state);
                if (currentSelection.any((t) => t.id == template.id)) {
                  currentSelection.removeWhere((t) => t.id == template.id);
                } else {
                  currentSelection.add(template);
                }
                notifier.state = currentSelection;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _handleScreenshot,
                child: Text(selectedTemplates.isNotEmpty ? '截屏并处理' : '仅截屏'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
