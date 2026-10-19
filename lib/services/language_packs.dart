import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../engines/mlkit_translator.dart';

/// Manages the one-time download of on-device translation models.
/// After this, translation works in airplane mode.
class LanguagePacks {
  static const List<String> required = ['en', 'hi', 'kn'];

  static const Map<String, String> names = {
    'en': 'English',
    'hi': 'Hindi',
    'kn': 'Kannada',
  };

  final OnDeviceTranslatorModelManager _manager =
      OnDeviceTranslatorModelManager();

  String _bcp(String code) => MlKitTranslator.languageFor(code).bcpCode;

  /// Language codes whose models are not on the device yet.
  Future<List<String>> missing() async {
    final result = <String>[];
    for (final code in required) {
      if (!await _manager.isModelDownloaded(_bcp(code))) result.add(code);
    }
    return result;
  }

  /// Downloads each missing model in turn. [onStart] fires before each one.
  /// Throws if any download fails, so the caller can show a retry.
  Future<void> downloadMissing({void Function(String code)? onStart}) async {
    for (final code in await missing()) {
      onStart?.call(code);
      final ok = await _manager.downloadModel(_bcp(code));
      if (!ok) {
        throw StateError('Download failed for ${names[code] ?? code}');
      }
    }
  }
}
