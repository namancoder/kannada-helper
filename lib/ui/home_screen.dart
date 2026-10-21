import 'package:flutter/material.dart';

import '../engines/engines.dart';
import '../services/from_kannada.dart';
import '../services/to_kannada.dart';
import 'scan_view.dart';
import 'speak_view.dart';
import 'type_view.dart';

enum Mode { type, speak, scan }

/// The only screen: three modes, nothing else.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.translator,
    required this.tts,
    required this.romanizer,
    required this.speech,
    required this.ocr,
  });

  final Translator translator;
  final TextToSpeech tts;
  final Romanizer romanizer;
  final SpeechToText speech;
  final Ocr ocr;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ToKannada _toKannada = ToKannada(widget.translator);
  late final FromKannada _fromKannada = FromKannada(widget.translator);
  Mode _mode = Mode.type;
  bool? _voiceInstalled; // checked once, shared by all modes

  @override
  void initState() {
    super.initState();
    widget.tts.isAvailable('kn').then((ok) {
      if (mounted) setState(() => _voiceInstalled = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kannada Helper')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<Mode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: Mode.type,
                      icon: Icon(Icons.keyboard),
                      label: Text('Type')),
                  ButtonSegment(
                      value: Mode.speak,
                      icon: Icon(Icons.mic),
                      label: Text('Speak')),
                  ButtonSegment(
                      value: Mode.scan,
                      icon: Icon(Icons.camera_alt),
                      label: Text('Scan')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  widget.tts.stop();
                  setState(() => _mode = s.first);
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                // IndexedStack keeps each mode's state when you switch.
                child: IndexedStack(
                  index: _mode.index,
                  children: [
                    TypeView(
                      toKannada: _toKannada,
                      tts: widget.tts,
                      romanizer: widget.romanizer,
                      voiceInstalled: _voiceInstalled,
                    ),
                    SpeakView(
                      speech: widget.speech,
                      toKannada: _toKannada,
                      tts: widget.tts,
                      romanizer: widget.romanizer,
                      voiceInstalled: _voiceInstalled,
                      active: _mode == Mode.speak,
                    ),
                    ScanView(
                      ocr: widget.ocr,
                      fromKannada: _fromKannada,
                      tts: widget.tts,
                      romanizer: widget.romanizer,
                      voiceInstalled: _voiceInstalled,
                      active: _mode == Mode.scan,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
