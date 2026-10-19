import 'package:flutter/material.dart';

/// "From: English | हिंदी" switch shared by Type and Speak modes.
class SourceToggle extends StatelessWidget {
  const SourceToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value; // 'en' or 'hi'
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('From', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'hi', label: Text('हिंदी')),
          ],
          selected: {value},
          onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
        ),
      ],
    );
  }
}
