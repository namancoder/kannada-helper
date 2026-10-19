import 'package:flutter/material.dart';

/// Shows a translation the way you'll actually use it:
/// Kannada in English letters (big), Kannada script (small), and a play button.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.romanized,
    required this.kannada,
    this.onPlay,
    this.audioHint,
  });

  final String romanized;
  final String kannada;

  /// Null hides the play button (e.g. no Kannada voice installed).
  final VoidCallback? onPlay;

  /// Shown under the text when audio isn't available.
  final String? audioHint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    romanized,
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (onPlay != null)
                  IconButton.filledTonal(
                    tooltip: 'Play',
                    icon: const Icon(Icons.volume_up),
                    onPressed: onPlay,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              kannada,
              style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (audioHint != null) ...[
              const SizedBox(height: 12),
              Text(audioHint!,
                  style: text.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
