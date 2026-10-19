import 'package:flutter/material.dart';

import '../engines/engines.dart';
import 'result_card.dart';

enum Mode { type, speak, scan }

/// The only screen: three modes, nothing else.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.translator,
    required this.tts,
    required this.romanizer,
  });

  final Translator translator;
  final TextToSpeech tts;
  final Romanizer romanizer;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Mode _mode = Mode.type;

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
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              Expanded(
                // IndexedStack keeps each mode's state when you switch.
                child: IndexedStack(
                  index: _mode.index,
                  children: [
                    TypeView(
                      translator: widget.translator,
                      tts: widget.tts,
                      romanizer: widget.romanizer,
                    ),
                    const _ComingSoon(
                        icon: Icons.mic,
                        text: 'Speak mode arrives in Phase 2.'),
                    const _ComingSoon(
                        icon: Icons.camera_alt,
                        text: 'Scan mode arrives in Phase 3.'),
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

/// Type English or Hindi, get Kannada you can read and hear.
class TypeView extends StatefulWidget {
  const TypeView({
    super.key,
    required this.translator,
    required this.tts,
    required this.romanizer,
  });

  final Translator translator;
  final TextToSpeech tts;
  final Romanizer romanizer;

  @override
  State<TypeView> createState() => _TypeViewState();
}

class _TypeViewState extends State<TypeView> {
  final _controller = TextEditingController();
  final Map<String, String> _cache = {}; // "from|text" -> Kannada

  String _from = 'en';
  bool _busy = false;
  bool? _voiceInstalled; // null until checked
  String? _kannada;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.tts.isAvailable('kn').then((ok) {
      if (mounted) setState(() => _voiceInstalled = ok);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();

    final key = '$_from|$input';
    final cached = _cache[key];
    if (cached != null) {
      setState(() {
        _kannada = cached;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.translator.translate(input, _from, 'kn');
      _cache[key] = result;
      if (mounted) setState(() => _kannada = result);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not translate: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kannada = _kannada;
    return ListView(
      children: [
        Row(
          children: [
            Text('From', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'hi', label: Text('हिंदी')),
              ],
              selected: {_from},
              onSelectionChanged: (s) => setState(() => _from = s.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _translate(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText:
                _from == 'en' ? 'How much is this?' : 'यह कितने का है?',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _translate,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.translate),
          label: const Text('To Kannada'),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (kannada != null && kannada.isNotEmpty)
          ResultCard(
            romanized: widget.romanizer.toLatin(kannada),
            kannada: kannada,
            onPlay: _voiceInstalled == false
                ? null
                : () => widget.tts.speak(kannada, 'kn'),
            audioHint: _voiceInstalled == false
                ? 'No Kannada voice found. Install it once in your phone\'s '
                    'text-to-speech settings to hear this.'
                : null,
          ),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
