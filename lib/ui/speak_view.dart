import 'dart:async';

import 'package:flutter/material.dart';

import '../engines/engines.dart';
import '../services/to_kannada.dart';
import 'kannada_result.dart';
import 'source_toggle.dart';

/// Tap the mic, speak English or Hindi, hear and read it in Kannada.
class SpeakView extends StatefulWidget {
  const SpeakView({
    super.key,
    required this.speech,
    required this.toKannada,
    required this.tts,
    required this.romanizer,
    required this.voiceInstalled,
    this.active = true,
  });

  final SpeechToText speech;
  final ToKannada toKannada;
  final TextToSpeech tts;
  final Romanizer romanizer;
  final bool? voiceInstalled;

  /// False while another mode is on screen; listening stops when this flips.
  final bool active;

  @override
  State<SpeakView> createState() => _SpeakViewState();
}

class _SpeakViewState extends State<SpeakView> with WidgetsBindingObserver {
  StreamSubscription<Transcript>? _session;

  /// Holds what was heard once listening ends, so a misheard word can be
  /// fixed by hand and translated again.
  final _editor = TextEditingController();

  /// The exact text the current Kannada result came from.
  String _translatedFrom = '';

  String _from = 'en';
  bool _listening = false;
  bool _translating = false;
  bool _autoPlay = true;
  String _heard = '';
  String? _kannada;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(SpeakView old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only 'paused' (app in background). 'inactive' also fires while the
    // mic permission dialog is open, and stopping then would kill the session.
    if (state == AppLifecycleState.paused) _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.cancel();
    if (_listening) widget.speech.stop();
    _editor.dispose();
    super.dispose();
  }

  void _stop() {
    if (_listening) widget.speech.stop();
  }

  Future<void> _onMicPressed() async {
    if (_listening) {
      await widget.speech.stop();
      return;
    }
    await widget.tts.stop(); // don't let the phone hear itself
    if (!mounted) return;

    final from = _from;
    var latest = '';
    var handled = false; // translate each session exactly once

    void handle(String text) {
      if (handled || text.trim().isEmpty) return;
      handled = true;
      _translate(text, from);
    }

    setState(() {
      _listening = true;
      _heard = '';
      _kannada = null;
      _error = null;
      _translatedFrom = '';
      _editor.clear();
    });

    await _session?.cancel();
    _session = widget.speech.listen(from).listen(
      (t) {
        latest = t.text;
        if (mounted) setState(() => _heard = t.text);
        if (t.isFinal) handle(t.text);
      },
      onError: (Object e) {
        if (handled || !mounted) return;
        setState(() => _error = speechErrorMessage(e));
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _listening = false;
          // Hand the transcript to the editable field.
          if (_editor.text.isEmpty) _editor.text = latest.trim();
        });
        handle(latest);
      },
    );
  }

  Future<void> _translate(String text, String from) async {
    final input = text.trim();
    if (!mounted || input.isEmpty) return;
    setState(() {
      _translating = true;
      _error = null;
      _translatedFrom = input;
      if (_editor.text.trim() != input) _editor.text = input;
    });
    try {
      final kannada = await widget.toKannada(input, from);
      if (!mounted) return;
      setState(() => _kannada = kannada);
      if (_autoPlay && widget.voiceInstalled != false && kannada.isNotEmpty) {
        await widget.tts.speak(kannada, 'kn');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not translate: $e');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  /// Re-translates whatever is in the editor now.
  void _retranslate() {
    FocusScope.of(context).unfocus();
    _translate(_editor.text, _from);
  }

  /// What was heard, editable. The ↻ button lights up once it's changed.
  Widget _buildEditor() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _editor,
      builder: (context, value, _) {
        // Enabled after an edit, or to retry a translation that failed.
        final changed = value.text.trim().isNotEmpty &&
            (value.text.trim() != _translatedFrom || _error != null);
        return TextField(
          key: const Key('heard'),
          controller: _editor,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _retranslate(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'What you said',
            helperText: changed
                ? 'Tap ↻ to translate your edit'
                : 'Heard a word wrong? Tap to fix it',
            suffixIcon: IconButton(
              key: const Key('retranslate'),
              tooltip: 'Translate again',
              icon: const Icon(Icons.refresh),
              color: changed ? Theme.of(context).colorScheme.primary : null,
              onPressed: changed && !_translating ? _retranslate : null,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final kannada = _kannada;
    final language = _from == 'en' ? 'English' : 'Hindi';

    return ListView(
      children: [
        SourceToggle(
          value: _from,
          enabled: !_listening,
          onChanged: (v) => setState(() => _from = v),
        ),
        const SizedBox(height: 32),
        Center(
          child: SizedBox(
            width: 112,
            height: 112,
            child: FilledButton(
              key: const Key('mic'),
              onPressed: _translating ? null : _onMicPressed,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: _listening ? colors.error : null,
                foregroundColor: _listening ? colors.onError : null,
              ),
              child: Icon(_listening ? Icons.stop : Icons.mic, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _listening ? 'Listening… tap to stop' : 'Tap and speak in $language',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_listening && _heard.isNotEmpty)
          Text(
            '“$_heard”',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(fontStyle: FontStyle.italic),
          ),
        if (!_listening && _translatedFrom.isNotEmpty) _buildEditor(),
        if (_translating) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error)),
        ],
        if (kannada != null && kannada.isNotEmpty) ...[
          const SizedBox(height: 16),
          KannadaResult(
            kannada: kannada,
            romanizer: widget.romanizer,
            tts: widget.tts,
            voiceInstalled: widget.voiceInstalled,
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Play Kannada automatically'),
          value: _autoPlay,
          onChanged: (v) => setState(() => _autoPlay = v),
        ),
      ],
    );
  }
}

/// Turns engine error codes into something a human can act on.
String speechErrorMessage(Object error) {
  final code = error is SpeechException ? error.code : '$error';
  if (code.contains('permission') || code.contains('unavailable')) {
    return 'Couldn\'t use the microphone. Allow microphone access for '
        'Kannada Helper in your phone\'s app settings, and make sure '
        'Google speech services are installed.';
  }
  if (code.contains('no_match') || code.contains('speech_timeout')) {
    return 'Didn\'t catch that. Tap the mic and try again.';
  }
  if (code.contains('network')) {
    return 'This language needs internet for speech, or its offline '
        'speech pack in your phone\'s settings.';
  }
  if (code.contains('busy')) {
    return 'The mic is busy. Wait a second and try again.';
  }
  return 'Mic error ($code). Try again.';
}
