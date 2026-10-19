import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'engines.dart';

/// v1 speech engine: the phone's built-in recognizer via `speech_to_text`.
/// Free. Hindi may need internet unless the offline Hindi pack is installed
/// in the phone's speech settings.
class PlatformSpeechToText implements SpeechToText {
  PlatformSpeechToText({
    this.listenFor = const Duration(seconds: 30),
    this.pauseFor = const Duration(seconds: 3),
  });

  /// Longest single session.
  final Duration listenFor;

  /// Silence that ends a session. (Android may cut in sooner on its own.)
  final Duration pauseFor;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  StreamController<Transcript>? _session;
  Timer? _closeTimer;

  static String _locale(String lang) => switch (lang) {
        'en' => 'en_IN',
        'hi' => 'hi_IN',
        'kn' => 'kn_IN',
        _ => throw ArgumentError.value(lang, 'lang', 'Unsupported language'),
      };

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
      );
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  @override
  Stream<Transcript> listen(String lang) {
    _finish(); // end any previous session
    final session = StreamController<Transcript>();
    _session = session;
    _start(session, lang);
    return session.stream;
  }

  Future<void> _start(StreamController<Transcript> session, String lang) async {
    if (!await initialize()) {
      _fail(session, const SpeechException('error_unavailable'));
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) {
          if (session.isClosed) return;
          session.add(Transcript(result.recognizedWords,
              isFinal: result.finalResult));
          if (result.finalResult) _finish();
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _locale(lang),
          partialResults: true,
          cancelOnError: true,
          listenFor: listenFor,
          pauseFor: pauseFor,
        ),
      );
    } catch (e) {
      _fail(session, SpeechException('error_start: $e'));
    }
  }

  @override
  Future<void> stop() async {
    if (!_initialized) return;
    await _speech.stop();
    // The final result normally follows a stop(); close anyway if it doesn't.
    _scheduleClose();
  }

  void _onStatus(String status) {
    if (status == 'done') {
      _finish();
    } else if (status == 'notListening') {
      _scheduleClose();
    }
  }

  void _onError(SpeechRecognitionError error) {
    final session = _session;
    if (session == null || session.isClosed) return;
    session.addError(
        SpeechException(error.errorMsg, permanent: error.permanent));
    if (error.permanent) _finish();
  }

  /// Safety net: if the engine never sends 'done', don't hang the UI.
  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(seconds: 2), _finish);
  }

  void _fail(StreamController<Transcript> session, SpeechException e) {
    if (session.isClosed) return;
    session.addError(e);
    if (identical(session, _session)) {
      _finish();
    } else {
      session.close();
    }
  }

  void _finish() {
    _closeTimer?.cancel();
    _closeTimer = null;
    final session = _session;
    _session = null;
    if (session != null && !session.isClosed) session.close();
  }
}
