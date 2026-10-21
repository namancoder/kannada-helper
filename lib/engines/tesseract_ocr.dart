import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

import 'engines.dart';

/// v1 OCR engine: Tesseract with the Kannada model, fully on-device.
/// (Google ML Kit can't read Kannada script, so it isn't an option here.)
///
/// The Kannada model (`kan.traineddata`, "fast" variant, a few MB) is
/// downloaded once from the official tesseract-ocr GitHub repo, not bundled.
class TesseractOcr implements Ocr {
  TesseractOcr({
    this.modelUrl =
        'https://github.com/tesseract-ocr/tessdata_fast/raw/main/kan.traineddata',
  });

  final String modelUrl;

  static const _modelFile = 'kan.traineddata';

  /// A real model is well over this; anything smaller is a failed download.
  static const _minValidBytes = 100 * 1024;

  int _slot = 0; // alternate temp files so a slow read never sees a half write

  Future<File> _model() async {
    final dir = Directory(await FlutterTesseractOcr.getTessdataPath());
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/$_modelFile');
  }

  @override
  Future<bool> isReady() async {
    final file = await _model();
    return file.existsSync() && file.lengthSync() > _minValidBytes;
  }

  @override
  Future<void> prepare(
      {void Function(int received, int? total)? onProgress}) async {
    if (await isReady()) return;
    final target = await _model();
    final part = File('${target.path}.part');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(modelUrl));
      final response = await request.close(); // follows GitHub's redirect
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: request.uri);
      }
      final total = response.contentLength > 0 ? response.contentLength : null;
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (received < _minValidBytes) {
        throw const FormatException('Downloaded file is too small');
      }
      await part.rename(target.path); // only a complete file gets the real name
    } catch (_) {
      if (part.existsSync()) await part.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<String> read(Uint8List image) async {
    _slot = 1 - _slot;
    final file = File('${Directory.systemTemp.path}/kh_scan_$_slot.png');
    await file.writeAsBytes(image, flush: true);
    return FlutterTesseractOcr.extractText(
      file.path,
      language: 'kan',
      args: {
        'psm': '6', // treat the box as one uniform block of text
        'preserve_interword_spaces': '1',
      },
    );
  }
}
