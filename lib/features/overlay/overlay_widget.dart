import 'dart:isolate';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_ocr/features/templates/models/template.dart';
import 'package:image_ocr/features/templates/providers/template_providers.dart';
import 'package:image_ocr/features/templates/widgets/template_selector.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  
  // Completer for the ping-pong heartbeat check
  Completer<bool>? _pingCompleter;
  
  // Channel to communicate with native Android code (MainActivity)
  static const MethodChannel _screenshotChannel = MethodChannel('com.lxmoon.image_ocr/screenshot');

  @override
  void initState() {
    super.initState();
    
    // --- [ROBUSTNESS FIX] Read initial state from persistent storage ---
    // This ensures the overlay starts in the correct state after a restart.
    final box = Hive.box('app_state');
    final isExpanded = box.get('overlay_is_expanded', defaultValue: false) as bool;
    _state = isExpanded ? OverlayState.expanded : OverlayState.collapsed;
    _previousState = _state;

    homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
    IsolateNameServer.registerPortWithName(_receivePort.sendPort, _kPortNameOverlay);
    
    // The single, persistent listener for all messages from the main isolate.
    _receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final command = message['command'] as String?;
        switch (command) {
          case 'close_overlay':
            FlutterOverlayWindow.closeOverlay();
            break;
          case 'screenshot_done':
            // Screenshot is done, restore previous state
            final wasExpanded = message['wasExpanded'] as bool? ?? false;
            setState(() {
              _state = wasExpanded ? OverlayState.expanded : OverlayState.collapsed;
            });
            _resizeOverlay();
            break;
          case 'pong':
            // Respond to the ping for the heartbeat check.
            if (_pingCompleter != null && !_pingCompleter!.isCompleted) {
              _pingCompleter!.complete(true);
            }
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

  /// 拍照处理逻辑
  Future<void> _handleTakePicture() async {
    try {
      _previousState = _state;
      setState(() { _state = OverlayState.invisible; });
      await _resizeOverlay();

      final isAlive = await _isMainAppAlive();
      if (!isAlive) {
        debugPrint('Main app is not responding. Waking it up...');
        await _screenshotChannel.invokeMethod('wakeUp');
        await Future.delayed(const Duration(seconds: 2));
      }
      
      await _sendMessageToMain('request_take_picture', {'wasExpanded': _previousState == OverlayState.expanded});

    } catch (e) {
      debugPrint('Take picture request failed: $e');
      await _restorePreviousState();
    }
  }

  /// 截屏处理逻辑 (V3.1: 修复 Stream 监听错误)
  Future<void> _handleScreenshot({bool process = false}) async {
    try {
      _previousState = _state;
      setState(() { _state = OverlayState.invisible; });
      await _resizeOverlay();

      // 1. 检查主应用是否存活
      final isAlive = await _isMainAppAlive();

      if (!isAlive) {
        // 2. 如果不存活，则唤醒它
        debugPrint('Main app is not responding. Waking it up...');
        try {
          await _screenshotChannel.invokeMethod('wakeUp');
          // 等待主应用有足够的时间启动和初始化
          await Future.delayed(const Duration(seconds: 2));
        } catch (e) {
          debugPrint('Failed to wake up main app: $e');
          await _restorePreviousState();
          // TODO: Show an error message to the user
          return;
        }
      }
      
      // 3. (重新)发送截图指令
      await _sendScreenshotCommand(process: process);

    } catch (e) {
      debugPrint('Screenshot request failed: $e');
      await _restorePreviousState();
    }
  }

  /// 检查主应用Isolate是否存活 (Ping-Pong机制)
  Future<bool> _isMainAppAlive() async {
    homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
    if (homePort == null) return false;

    // Create a new completer for this specific ping request.
    _pingCompleter = Completer<bool>();

    // Set up a timeout for the ping.
    final timer = Timer(const Duration(milliseconds: 800), () { // Increased timeout
      if (!_pingCompleter!.isCompleted) {
        _pingCompleter!.complete(false);
        debugPrint('Ping timed out.');
      }
    });

    // Send the ping. The response will be handled by the listener in initState.
    homePort!.send({'command': 'ping'});
    debugPrint('Ping sent.');
    
    final result = await _pingCompleter!.future;
    timer.cancel(); // Clean up the timer
    return result;
  }

  /// 封装发送截图指令的逻辑
  Future<void> _sendScreenshotCommand({bool process = false}) async {
    final selectedTemplates = ref.read(selectedTemplatesForProcessingProvider);
    // If process is true, we must have templates selected.
    if (process && selectedTemplates.isNotEmpty) {
      await _sendMessageToMain('request_screenshot_and_process', {
        'wasExpanded': _previousState == OverlayState.expanded,
        'templates': selectedTemplates.map((t) => {'templateId': t.id}).toList(),
      });
    } else {
      // Otherwise, just take a screenshot.
      await _sendMessageToMain('request_screenshot_only', {
        'wasExpanded': _previousState == OverlayState.expanded,
      });
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

    final newStateIsExpanded = _state == OverlayState.expanded;

    // --- [ROBUSTNESS FIX] Write the new state to persistent storage ---
    await Hive.box('app_state').put('overlay_is_expanded', newStateIsExpanded);

    // Notify the main app about the state change so it can restore correctly.
    homePort ??= IsolateNameServer.lookupPortByName(_kPortNameHome);
    homePort?.send({
      'command': 'update_state',
      'payload': {'isExpanded': newStateIsExpanded}
    });
  }

  Future<void> _resizeOverlay() async {
    // 使用 PlatformDispatcher 来安全地获取屏幕尺寸
    final view = PlatformDispatcher.instance.views.first;
    final screenSize = view.physicalSize / view.devicePixelRatio;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    switch (_state) {
      case OverlayState.collapsed:
        const double ballSize = 60;
        await FlutterOverlayWindow.resizeOverlay(ballSize.toInt(), ballSize.toInt(), true);
        
        // 坐标系中心为 (0,0)，moveOverlay 设置的是悬浮窗的中心点
        // X 坐标：屏幕左边缘 (-width/2) + 悬浮球半径 (ballSize/2) + 边距
        final double x = (-screenWidth / 2) + (ballSize / 2);
        // Y 坐标：屏幕下边缘 (height/2) - 悬浮球半径 (ballSize/2) - 边距
        final double y = (screenHeight / 2) - (ballSize / 2) + 50;
        
        await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
        break;
      case OverlayState.expanded:
        const double windowWidth = 350;
        const double windowHeight = 600;
        await FlutterOverlayWindow.resizeOverlay(windowWidth.toInt(), windowHeight.toInt(), true);
        
        // 将展开窗口的中心点移动到屏幕中心点 (0,0)
        await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
        break;
      case OverlayState.capturing:
        await FlutterOverlayWindow.resizeOverlay(80, 80, true);
        break;
      case OverlayState.invisible:
        await FlutterOverlayWindow.resizeOverlay(1, 1, false);
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
                 // --- [NEW] Clear Selection Button ---
                IconButton(
                  icon: const Icon(Icons.clear_all, color: Colors.white),
                  tooltip: '清空已选',
                  onPressed: () {
                     ref.read(selectedTemplatesForProcessingProvider.notifier).state = {};
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
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
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _handleTakePicture,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.screenshot_monitor),
                    label: const Text('仅截屏'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _handleScreenshot(process: false),
                  ),
                ),
                if (selectedTemplates.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.camera_enhance),
                      label: const Text('截屏并处理'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => _handleScreenshot(process: true),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
