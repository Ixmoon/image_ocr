import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';

// 自定义绘制器，用于在图片上绘制高亮框和可调整的选区
class SelectionPainter extends CustomPainter {
  final Matrix4 matrix;
  final Rect? selectionRect;
  final List<Rect> highlightRects;
  final Rect? labelRect; // 新增：专门用于绘制标签的Rect
  final Size imageSize;
  final Size canvasSize;

  SelectionPainter({
    required this.matrix,
    this.selectionRect,
    required this.highlightRects,
    this.labelRect, // 新增
    required this.imageSize,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty) return;

    // 1. 计算图片在不变形的情况下适应画布的初始变换（缩放和居中偏移）
    final FittedSizes fittedSizes = applyBoxFit(BoxFit.contain, imageSize, canvasSize);
    final Size sourceSize = fittedSizes.source;
    final Size destinationSize = fittedSizes.destination;
    
    final double scaleX = destinationSize.width / sourceSize.width;
    final double scaleY = destinationSize.height / sourceSize.height;
    final double offsetX = (canvasSize.width - destinationSize.width) / 2.0;
    final double offsetY = (canvasSize.height - destinationSize.height) / 2.0;

    // 2. 定义一个函数，将图片坐标系的Rect，通过两步转换，变为最终屏幕（视口）坐标系的Rect
    Rect imageRectToViewportRect(Rect imageRect) {
      // 步骤A: 将图片坐标转换为初始场景（Scene）坐标
      final sceneTopLeft = Offset(imageRect.left * scaleX + offsetX, imageRect.top * scaleY + offsetY);
      final sceneBottomRight = Offset(imageRect.right * scaleX + offsetX, imageRect.bottom * scaleY + offsetY);
      
      // 步骤B: 将场景坐标通过InteractiveViewer的当前变换矩阵，转换为最终的屏幕（Viewport）坐标
      final viewportTopLeft = MatrixUtils.transformPoint(matrix, sceneTopLeft);
      final viewportBottomRight = MatrixUtils.transformPoint(matrix, sceneBottomRight);
      
      return Rect.fromPoints(viewportTopLeft, viewportBottomRight);
    }

    // 3. 使用上述转换函数进行绘制
    final highlightPaint = Paint()
      ..color = Colors.yellow.withAlpha(100)
      ..style = PaintingStyle.fill;

    for (final rect in highlightRects) {
      canvas.drawRect(imageRectToViewportRect(rect), highlightPaint);
    }

    // 新增：用红色绘制标签框
    if (labelRect != null) {
      final labelPaint = Paint()
        ..color = Colors.red.withAlpha(100)
        ..style = PaintingStyle.fill;
      canvas.drawRect(imageRectToViewportRect(labelRect!), labelPaint);
    }

    if (selectionRect != null) {
      final selectionPaint = Paint()
        ..color = Colors.blue.withAlpha(70)
        ..style = PaintingStyle.fill;
      
      final currentScale = matrix.getMaxScaleOnAxis();
      final borderPaint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 2.0 / currentScale // 动态调整边框宽度以保持视觉一致
        ..style = PaintingStyle.stroke;

      final viewportSelectionRect = imageRectToViewportRect(selectionRect!);
      canvas.drawRect(viewportSelectionRect, selectionPaint);
      canvas.drawRect(viewportSelectionRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) {
    return oldDelegate.matrix != matrix ||
           oldDelegate.selectionRect != selectionRect ||
           oldDelegate.highlightRects != highlightRects ||
           oldDelegate.labelRect != labelRect || // 新增
           oldDelegate.imageSize != imageSize ||
           oldDelegate.canvasSize != canvasSize;
  }
}


// 可交互的图片查看器，支持缩放、平移和区域选择
class InteractiveImageViewer extends StatefulWidget {
  final String imagePath;
  final List<Rect> highlightRects; // 需要高亮的区域
  final Rect? labelRect; // 新增
  final Rect? initialSelection; // 初始选区
  final Function(Rect) onSelectionChanged; // 选区变化时的回调

  const InteractiveImageViewer({
    super.key,
    required this.imagePath,
    this.highlightRects = const [],
    this.labelRect, // 新增
    this.initialSelection,
    required this.onSelectionChanged,
  });

  @override
  State<InteractiveImageViewer> createState() => _InteractiveImageViewerState();
}

class _InteractiveImageViewerState extends State<InteractiveImageViewer> {
  final TransformationController _transformationController = TransformationController();
  Rect? _selectionRect;
  Offset? _dragStart;
  Size _imageSize = Size.zero;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _selectionRect = widget.initialSelection;
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final image = File(widget.imagePath);
    final decodedImage = await decodeImageFromList(await image.readAsBytes());
    if (mounted) {
      setState(() {
        _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
      });
    }
  }

  @override
  void didUpdateWidget(covariant InteractiveImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelection != oldWidget.initialSelection) {
      setState(() {
        _selectionRect = widget.initialSelection;
      });
    }
    if (widget.imagePath != oldWidget.imagePath) {
      _loadImageSize();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _canvasSize = constraints.biggest;
          // 最终结构性修复：使用Stack分离交互层和绘制层
          return Stack(
            children: [
              InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 5.0,
                onInteractionStart: (details) {
                  if (_imageSize.isEmpty) return;
                  final scenePos = _transformationController.toScene(details.localFocalPoint);
                  _dragStart = _transformScenePointToImagePoint(scenePos);
                  setState(() {
                    _selectionRect = Rect.fromPoints(_dragStart!, _dragStart!);
                  });
                },
                onInteractionUpdate: (details) {
                  if (_dragStart == null || _imageSize.isEmpty) return;
                  final scenePos = _transformationController.toScene(details.localFocalPoint);
                  final dragCurrent = _transformScenePointToImagePoint(scenePos);
                  setState(() {
                    _selectionRect = Rect.fromPoints(_dragStart!, dragCurrent);
                  });
                },
                onInteractionEnd: (details) {
                  if (_selectionRect != null) {
                    if (_selectionRect!.width > 2 && _selectionRect!.height > 2) {
                      widget.onSelectionChanged(_selectionRect!);
                    }
                  }
                  _dragStart = null;
                  setState(() {});
                },
                // InteractiveViewer的child现在只是图片本身
                child: _imageSize == Size.zero
                    ? const SizedBox()
                    : Center(child: Image.file(File(widget.imagePath))),
              ),
              // 在上层覆盖一个独立的CustomPaint用于绘制
              // 用IgnorePointer包裹，使其不捕获手势，让手势可以“穿透”到下面的InteractiveViewer
              IgnorePointer(
                child: CustomPaint(
                  size: _canvasSize,
                  painter: SelectionPainter(
                    matrix: _transformationController.value,
                    selectionRect: _selectionRect,
                    highlightRects: widget.highlightRects,
                    labelRect: widget.labelRect, // 新增
                    imageSize: _imageSize,
                    canvasSize: _canvasSize,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Offset _transformScenePointToImagePoint(Offset scenePoint) {
    // 这个函数用于将屏幕上的点击/拖动点（已转换为场景坐标）反向转换回图片坐标。
    // 它需要手动应用`BoxFit.contain`的逆运算来找到它在原始图片上的对应点。
    final FittedSizes fittedSizes = applyBoxFit(BoxFit.contain, _imageSize, _canvasSize);
    final Size sourceSize = fittedSizes.source;
    final Size destinationSize = fittedSizes.destination;
    
    final double scaleX = destinationSize.width / sourceSize.width;
    final double scaleY = destinationSize.height / sourceSize.height;
    final double offsetX = (_canvasSize.width - destinationSize.width) / 2.0;
    final double offsetY = (_canvasSize.height - destinationSize.height) / 2.0;

    return Offset(
      (scenePoint.dx - offsetX) / scaleX,
      (scenePoint.dy - offsetY) / scaleY,
    );
  }
}