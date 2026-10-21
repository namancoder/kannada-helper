import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pure image helpers for Scan mode. No Flutter imports, so they can run in a
/// background isolate (via `compute`) and be unit-tested directly.

/// The scan box, as fractions of the upright camera picture, centred.
class ScanBox {
  const ScanBox({this.widthFraction = 0.9, this.heightFraction = 0.3});

  final double widthFraction;
  final double heightFraction;
}

/// A single-channel (grayscale) picture.
class GrayImage {
  const GrayImage(this.bytes, this.width, this.height);

  final Uint8List bytes; // width * height, row-major, no padding
  final int width;
  final int height;
}

/// Inputs for [cropFrame]. Plain fields only, so it can cross isolates.
class FrameRequest {
  const FrameRequest({
    required this.luma,
    required this.width,
    required this.height,
    required this.rowStride,
    required this.rotation,
    this.box = const ScanBox(),
  });

  /// Brightness (Y) plane straight from the camera.
  final Uint8List luma;
  final int width;
  final int height;

  /// Bytes per row in [luma]; can be larger than [width].
  final int rowStride;

  /// Clockwise degrees (0, 90, 180, 270) that turn the frame upright.
  /// On phones this is the camera's sensor orientation, usually 90.
  final int rotation;

  final ScanBox box;
}

/// Rotates the frame upright, cuts out the scan box and boosts contrast.
GrayImage cropFrame(FrameRequest r) {
  final rot = ((r.rotation % 360) + 360) % 360;
  if (rot % 90 != 0) throw ArgumentError.value(r.rotation, 'rotation');
  final sideways = rot == 90 || rot == 270;
  final uprightW = sideways ? r.height : r.width;
  final uprightH = sideways ? r.width : r.height;

  final boxW = (uprightW * r.box.widthFraction).round().clamp(1, uprightW).toInt();
  final boxH = (uprightH * r.box.heightFraction).round().clamp(1, uprightH).toInt();
  final left = (uprightW - boxW) ~/ 2;
  final top = (uprightH - boxH) ~/ 2;

  final out = Uint8List(boxW * boxH);
  var i = 0;
  for (var y = top; y < top + boxH; y++) {
    for (var x = left; x < left + boxW; x++) {
      // Map each upright pixel back to where it sits in the raw frame.
      final int sx, sy;
      switch (rot) {
        case 90:
          sx = y;
          sy = r.height - 1 - x;
        case 180:
          sx = r.width - 1 - x;
          sy = r.height - 1 - y;
        case 270:
          sx = r.width - 1 - y;
          sy = x;
        default:
          sx = x;
          sy = y;
      }
      out[i++] = r.luma[sy * r.rowStride + sx];
    }
  }
  _stretchContrast(out);
  return GrayImage(out, boxW, boxH);
}

/// Spreads brightness so the darkest 2% become black and the brightest 2%
/// white. Helps Tesseract with dim or washed-out signs.
void _stretchContrast(Uint8List px) {
  if (px.isEmpty) return;
  final hist = List<int>.filled(256, 0);
  for (final v in px) {
    hist[v]++;
  }
  final cut = (px.length * 0.02).floor();
  var lo = 0, seen = 0;
  while (lo < 255 && seen + hist[lo] <= cut) {
    seen += hist[lo++];
  }
  var hi = 255;
  seen = 0;
  while (hi > 0 && seen + hist[hi] <= cut) {
    seen += hist[hi--];
  }
  if (hi - lo < 16) return; // flat picture, nothing to stretch
  final range = hi - lo;
  for (var i = 0; i < px.length; i++) {
    final v = ((px[i] - lo) * 255 / range).round();
    px[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
  }
}

/// Encodes a grayscale picture as PNG for the OCR engine.
Uint8List encodeGrayPng(GrayImage g) {
  final image = img.Image.fromBytes(
    width: g.width,
    height: g.height,
    // Copy so the buffer starts exactly at our pixels.
    bytes: Uint8List.fromList(g.bytes).buffer,
    numChannels: 1,
  );
  return img.encodePng(image);
}

/// Live frames: camera Y plane -> cropped, upright PNG. Run with `compute`.
Uint8List frameToPng(FrameRequest request) => encodeGrayPng(cropFrame(request));

/// Inputs for [photoToPng].
class PhotoRequest {
  const PhotoRequest(this.jpeg, {this.box = const ScanBox()});

  final Uint8List jpeg;
  final ScanBox box;
}

/// Frozen photo: JPEG -> cropped, upright PNG. Run with `compute`.
/// Returns null if the photo can't be decoded.
Uint8List? photoToPng(PhotoRequest request) {
  final decoded = img.decodeJpg(request.jpeg);
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded); // apply EXIF rotation
  final luma = Uint8List(upright.width * upright.height);
  var i = 0;
  for (final p in upright) {
    luma[i++] = img.getLuminanceRgb(p.r, p.g, p.b).round().clamp(0, 255).toInt();
  }
  return encodeGrayPng(cropFrame(FrameRequest(
    luma: luma,
    width: upright.width,
    height: upright.height,
    rowStride: upright.width,
    rotation: 0,
    box: request.box,
  )));
}

/// Keeps only Kannada words from raw OCR output.
/// Drops Latin letters, stray symbols and single-letter noise, and joins lines.
String cleanKannada(String raw) {
  final words = <String>[];
  for (final token in raw.split(RegExp(r'\s+'))) {
    final kept = String.fromCharCodes(
        token.runes.where((c) => c >= 0x0C80 && c <= 0x0CFF));
    if (kannadaLetterCount(kept) >= 2) words.add(kept);
  }
  return words.join(' ');
}

/// Counts Kannada letters (vowels and consonants), ignoring signs and digits.
int kannadaLetterCount(String s) => s.runes
    .where((c) => (c >= 0x0C85 && c <= 0x0C94) || (c >= 0x0C95 && c <= 0x0CB9))
    .length;
