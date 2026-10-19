import 'package:flutter/material.dart';

import '../engines/engines.dart';
import '../services/to_kannada.dart';
import 'kannada_result.dart';
import 'source_toggle.dart';

/// Type English or Hindi, get Kannada you can read and hear.
class TypeView extends StatefulWidget {
  const TypeView({
    super.key,
    required this.toKannada,
    required this.tts,
    required this.romanizer,
    required this.voiceInstalled,
  });

  final ToKannada toKannada;
  final TextToSpeech tts;
  final Romanizer romanizer;
  final bool? voiceInstalled;

  @override
  State<TypeView> createState() => _TypeViewState();
}

class _TypeViewState extends State<TypeView> {
  final _controller = TextEditingController();

  String _from = 'en';
  bool _busy = false;
  String? _kannada;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    final input = _controller.text.trim();
    if (input.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.toKannada(input, _from);
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
        SourceToggle(value: _from, onChanged: (v) => setState(() => _from = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _translate(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: _from == 'en' ? 'How much is this?' : 'यह कितने का है?',
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
          KannadaResult(
            kannada: kannada,
            romanizer: widget.romanizer,
            tts: widget.tts,
            voiceInstalled: widget.voiceInstalled,
          ),
      ],
    );
  }
}
