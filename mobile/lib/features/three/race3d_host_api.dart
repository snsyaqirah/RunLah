import 'package:flutter/material.dart';

import '../../core/l10n/i18n.dart';

/// What a platform host (WebView on mobile, iframe on web) reports back.
class Race3DHostCallbacks {
  const Race3DHostCallbacks({
    required this.onMessage,
    required this.onAttach,
    required this.onPageStarted,
    required this.onPageFinished,
  });

  /// JSON posted by the page.
  final void Function(String json) onMessage;

  /// The host can now send JSON commands to the page.
  final void Function(Future<void> Function(String json) send) onAttach;
  final VoidCallback onPageStarted;
  final VoidCallback onPageFinished;
}

/// Shown where the 3D scene can't run (widget tests, Linux/Windows desktop).
class Race3DPlaceholder extends StatelessWidget {
  const Race3DPlaceholder({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1220), Color(0xFF1A2547), Color(0xFF0B1220)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.view_in_ar_rounded, size: 44, color: Colors.white38),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String race3dUnsupportedMessage() => tr('The 3D view runs on Android, iOS and the web app.');
