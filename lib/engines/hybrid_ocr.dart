import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'engines.dart';

/// OCR engine for Scan mode, fully on-device:
///  * Tesseract (Kannada model, downloaded once) finds where the words are and
///    reads them too; it's good on clean printed fonts.
///  * IndicPhotoOCR's PARSeq model (bundled in the app as
///    `models/kannada_parseq_int8.onnx`) reads each word as well; it's much
///    better on real photos and signboards.
///  * Per word, whichever engine is more confident wins.
/// (Google ML Kit can't read Kannada script, so it isn't an option here.)
///
/// The heavy lifting is native: `android/.../MainActivity.kt`, source of truth
/// in `tool/android/MainActivity.kt`.
class HybridOcr implements Ocr {
  HybridOcr({
    this.modelUrl =
        'https://github.com/tesseract-ocr/tessdata_fast/raw/main/kan.traineddata',
  });

  final String modelUrl;

  static const _channel = MethodChannel('kannada_helper/ocr');
  static const _language = 'kan';

  /// Tesseract page mode 6: treat the box as one uniform block of text.
  static const _psmSingleBlock = 6;

  /// A real model is well over this; anything smaller is a failed download.
  static const _minValidBytes = 100 * 1024;

  int _slot = 0; // alternate temp files so a slow read never sees a half write

  /// Tesseract expects `<dataDir>/tessdata/<lang>.traineddata`.
  Future<File> _model() async {
    final dataDir = await _channel.invokeMethod<String>('dataDir');
    if (dataDir == null) throw StateError('OCR bridge returned no data folder');
    final tessdata = Directory('$dataDir/tessdata');
    if (!tessdata.existsSync()) await tessdata.create(recursive: true);
    return File('${tessdata.path}/$_language.traineddata');
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
  Future<OcrResult> read(Uint8List image) async {
    _slot = 1 - _slot;
    final file = File('${Directory.systemTemp.path}/kh_scan_$_slot.png');
    await file.writeAsBytes(image, flush: true);
    final r = await _channel.invokeMapMethod<String, Object?>('readWords', {
      'path': file.path,
      'lang': _language,
      'psm': _psmSingleBlock,
    });
    String str(String key) => (r?[key] as String?) ?? '';
    int number(String key) => (r?[key] as num?)?.toInt() ?? 0;
    final debug = [
      '${str('engine')} · ${number('ms')} ms',
      if (str('parseqText').isNotEmpty) 'PARSeq: ${str('parseqText')}',
      'Tesseract (${number('tessConfidence')}): ${str('tessText')}',
      if (str('note').isNotEmpty) str('note'),
    ].join('\n');
    return OcrResult(str('text'), number('confidence'), debug: debug);
  }
}
