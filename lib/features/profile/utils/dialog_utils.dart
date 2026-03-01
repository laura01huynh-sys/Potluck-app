import 'package:flutter/material.dart';

import '../../../core/config/dietary_data.dart';

/// Shows a dialog with the full definition of a lifestyle (e.g. vegan, keto).
void showLifestyleDefinition(BuildContext context, String lifestyle) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(lifestyle.replaceAll('-', ' ').toUpperCase()),
      content: Text(
        lifestyleFullDefinitions[lifestyle] ?? 'No definition available.',
        style: const TextStyle(fontSize: 14, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
