import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  final VoidCallback onStartMeeting;

  const HomePage({super.key, required this.onStartMeeting});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'HearNow',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Meeting assistant with separate mic + system transcripts.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onStartMeeting,
            icon: const Icon(Icons.record_voice_over),
            label: const Text('Start Meeting'),
          ),
          const SizedBox(height: 12),
          Text(
            'Tip: set server URL via --dart-define.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
