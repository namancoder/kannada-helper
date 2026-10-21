import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kannada_helper/services/scan_frame.dart';

/// A 4x2 frame whose pixel values are their own indices, so the output shows
/// exactly which source pixel ended up where (values are index * 30):
///   0  1  2  3
///   4  5  6  7
FrameRequest frame(int rotation, {int stride = 4, ScanBox? box}) {
  final luma = Uint8List(stride * 2);
  for (var y = 0; y < 2; y++) {
    for (var x = 0; x < 4; x++) {
      luma[y * stride + x] = (y * 4 + x) * 30;
    }
  }
  return FrameRequest(
    luma: luma,
    width: 4,
    height: 2,
    rowStride: stride,
    rotation: rotation,
    box: box ?? const ScanBox(widthFraction: 1, heightFraction: 1),
  );
}

/// Undo the contrast stretch: source values 0..210 (index * 30) are
/// stretched onto 0..255, so this recovers each pixel's index.
List<int> indices(GrayImage g) =>
    g.bytes.map((v) => (v * 7 / 255).round()).toList();

void main() {
  group('cropFrame rotation', () {
    test('0 degrees keeps the frame as is', () {
      final g = cropFrame(frame(0));
      expect([g.width, g.height], [4, 2]);
      expect(indices(g), [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('90 degrees clockwise (typical phone back camera)', () {
      final g = cropFrame(frame(90));
      expect([g.width, g.height], [2, 4]);
      // Left column becomes the top row, read bottom-up.
      expect(indices(g), [4, 0, 5, 1, 6, 2, 7, 3]);
    });

    test('180 degrees', () {
      final g = cropFrame(frame(180));
      expect(indices(g), [7, 6, 5, 4, 3, 2, 1, 0]);
    });

    test('270 degrees', () {
      final g = cropFrame(frame(270));
      expect([g.width, g.height], [2, 4]);
      expect(indices(g), [3, 7, 2, 6, 1, 5, 0, 4]);
    });

    test('row padding (stride > width) is skipped', () {
      final g = cropFrame(frame(0, stride: 6));
      expect(indices(g), [0, 1, 2, 3, 4, 5, 6, 7]);
    });
  });

  test('scan box crops the centre', () {
    final g = cropFrame(
        frame(0, box: const ScanBox(widthFraction: 0.5, heightFraction: 0.5)));
    expect([g.width, g.height], [2, 1]);
    // Centre 2x1 of a 4x2 frame starts at x=1, y=0.
    expect(g.bytes.length, 2);
    expect(g.bytes[0] < g.bytes[1], isTrue);
  });

  test('contrast is stretched to full black..white', () {
    final g = cropFrame(frame(0));
    expect(g.bytes.first, 0);
    expect(g.bytes.last, 255);
  });

  test('PNG round-trips with the right size', () {
    final png = frameToPng(frame(90));
    final decoded = img.decodePng(png)!;
    expect([decoded.width, decoded.height], [2, 4]);
  });

  group('cleanKannada', () {
    test('keeps Kannada words, drops Latin and symbols', () {
      expect(cleanKannada('ಬಸ್ ನಿಲ್ದಾಣ  BUS STOP | 123'), 'ಬಸ್ ನಿಲ್ದಾಣ');
    });
    test('joins lines', () {
      expect(cleanKannada('ಹೋಟೆಲ್\nಊಟ ಸಿದ್ಧ'), 'ಹೋಟೆಲ್ ಊಟ ಸಿದ್ಧ');
    });
    test('drops single-letter noise', () {
      expect(cleanKannada('ಕ ಮನೆ ೧'), 'ಮನೆ');
    });
    test('strips symbols stuck to words', () {
      expect(cleanKannada('“ಸ್ವಾಗತ”!'), 'ಸ್ವಾಗತ');
    });
    test('nothing Kannada gives empty', () {
      expect(cleanKannada('OPEN 24x7'), '');
    });
  });

  test('kannadaLetterCount ignores vowel signs and virama', () {
    expect(kannadaLetterCount('ನಿಲ್ದಾಣ'), 4); // ನ ಲ ದ ಣ
    expect(kannadaLetterCount('abc'), 0);
  });
}
