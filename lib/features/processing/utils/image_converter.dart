import 'dart:typed_data';
import 'package:image/image.dart' as img;

// This function is designed to be run in an isolate.
// It converts an image from the 'image' package (in RGB format) to NV21 format (YUV420sp).
Uint8List convertRgbToNv21(img.Image image) {
  final int width = image.width;
  final int height = image.height;
  final int frameSize = width * height;
  
  final yuv420sp = Uint8List(frameSize * 3 ~/ 2);
  
  int yIndex = 0;
  int uvIndex = frameSize;

  for (int j = 0; j < height; j++) {
    for (int i = 0; i < width; i++) {
      final pixel = image.getPixel(i, j);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();

      // Standard RGB to YUV conversion formula
      int y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
      int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
      int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;

      yuv420sp[yIndex++] = y.clamp(16, 235);

      // NV21 format has interleaved V and U planes with 2x2 subsampling.
      if (j % 2 == 0 && i % 2 == 0) {
        yuv420sp[uvIndex++] = v.clamp(16, 240);
        yuv420sp[uvIndex++] = u.clamp(16, 240);
      }
    }
  }
  
  return yuv420sp;
}