import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

// 自定义绘制器，仅用于在图片上绘制高亮框
class SelectionPainter extends CustomPainter {
  final Matrix4 matrix;
  final List<Rect> highlightRects;
  final Rect? labelRect;
  final Size imageSize;
  final Size canvasSize;

  SelectionPainter({
    required this.matrix,
    required this.highlightRects,
    this.labelRect,
    required this.imageSize,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.isEmpty) return;

    final FittedSizes fittedSizes = applyBoxFit(BoxFit.contain, imageSize, canvasSize);
    final Size sourceSize = fittedSizes.source;
    final Size destinationSize = fittedSizes.destination;
    
    final double scaleX = destinationSize.width / sourceSize.width;
    final double scaleY = destinationSize.height / sourceSize.height;
    final double offsetX = (canvasSize.width - destinationSize.width) / 2.0;
    final double offsetY = (canvasSize.height - destinationSize.height) / 2.0;

    Rect imageRectToViewportRect(Rect imageRect) {
      final sceneTopLeft = Offset(imageRect.left * scaleX + offsetX, imageRect.top * scaleY + offsetY);
      final sceneBottomRight = Offset(imageRect.right * scaleX + offsetX, imageRect.bottom * scaleY + offsetY);
      
      final viewportTopLeft = MatrixUtils.transformPoint(matrix, sceneTopLeft);
      final viewportBottomRight = MatrixUtils.transformPoint(matrix, sceneBottomRight);
      
      return Rect.fromPoints(viewportTopLeft, viewportBottomRight);
    }

    final highlightPaint = Paint()
      ..color = Colors.yellow.withAlpha(100)
      ..style = PaintingStyle.fill;

    for (final rect in highlightRects) {
      canvas.drawRect(imageRectToViewportRect(rect), highlightPaint);
    }

    if (labelRect != null) {
      final labelPaint = Paint()
        ..color = Colors.red.withAlpha(100)
        ..style = PaintingStyle.fill;
      canvas.drawRect(imageRectToViewportRect(labelRect!), labelPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) {
    return oldDelegate.matrix != matrix ||
           oldDelegate.highlightRects != highlightRects ||
           oldDelegate.labelRect != labelRect ||
           oldDelegate.imageSize != imageSize ||
           oldDelegate.canvasSize != canvasSize;
  }
}

// 可交互的图片查看器，仅支持缩放和平移
class InteractiveImageViewer extends StatefulWidget {
  final String imagePath;
  final List<Rect> highlightRects;
  final Rect? labelRect;

  const InteractiveImageViewer({
    super.key,
    required this.imagePath,
    this.highlightRects = const [],
    this.labelRect,
  });

  @override
  State<InteractiveImageViewer> createState() => _InteractiveImageViewerState();
}

class _InteractiveImageViewerState extends State<InteractiveImageViewer> {
  final TransformationController _transformationController = TransformationController();
  Size _imageSize = Size.zero;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
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
          return Stack(
            children: [
              InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 5.0,
                child: _imageSize == Size.zero
                    ? const SizedBox()
                    : Center(child: Image.file(File(widget.imagePath))),
              ),
              IgnorePointer(
                child: CustomPaint(
                  size: _canvasSize,
                  painter: SelectionPainter(
                    matrix: _transformationController.value,
                    highlightRects: widget.highlightRects,
                    labelRect: widget.labelRect,
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
}