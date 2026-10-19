import 'package:flutter/material.dart';

import '../services/language_packs.dart';

/// One-time screen: download the offline language packs, then never again.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.packs, required this.onDone});

  final LanguagePacks packs;
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _downloading = false;
  String? _current;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await widget.packs.downloadMissing(
        onStart: (code) => setState(() => _current = LanguagePacks.names[code]),
      );
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _current = null;
        _error = 'Download failed. Check your connection (Wi-Fi works best) '
            'and try again.\n\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('ನಮಸ್ಕಾರ', style: text.displaySmall),
              const SizedBox(height: 8),
              Text('One-time setup', style: text.titleLarge),
              const SizedBox(height: 16),
              Text(
                'Download the English, Hindi and Kannada language packs '
                '(a few dozen MB each). After this, translation works '
                'offline, even in airplane mode.',
                style: text.bodyLarge,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: text.bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.error)),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _downloading ? null : _download,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_downloading
                        ? 'Downloading ${_current ?? ''}…'
                        : 'Download language packs'),
                  ),
                ),
              ),
              if (_downloading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
