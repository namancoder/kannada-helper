import 'package:flutter/material.dart';

import '../engines/engines.dart';
import 'result_card.dart';

/// A [ResultCard] wired to the romanizer and text-to-speech.
class KannadaResult extends StatelessWidget {
  const KannadaResult({
    super.key,
    required this.kannada,
    required this.romanizer,
    required this.tts,
    required this.voiceInstalled,
  });

  final String kannada;
  final Romanizer romanizer;
  final TextToSpeech tts;

  /// null = not checked yet (play button shown optimistically).
  final bool? voiceInstalled;

  static const noVoiceHint = "No Kannada voice found. Install it once in your "
      "phone's text-to-speech settings to hear this.";

  @override
  Widget build(BuildContext context) {
    final noVoice = voiceInstalled == false;
    return ResultCard(
      romanized: romanizer.toLatin(kannada),
      kannada: kannada,
      onPlay: noVoice ? null : () => tts.speak(kannada, 'kn'),
      audioHint: noVoice ? noVoiceHint : null,
    );
  }
}
