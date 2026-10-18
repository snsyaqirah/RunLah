import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/l10n/i18n.dart';

/// One line the voice coach said (also shown as a caption on screen, so the
/// coach still "works" with the sound off or in a demo on a projector).
@immutable
class VoiceLine {
  const VoiceLine(this.text, this.at);
  final String text;
  final DateTime at;
}

/// Text-to-speech for the voice coach and spoken cheers.
///
/// Uses flutter_tts in Malay (ms-MY) or English (en-US) to match the app
/// language. Every platform call is guarded: on platforms without TTS (unit
/// tests, Linux desktop) [speak] quietly does nothing except update
/// [lastLine].
class VoiceService {
  FlutterTts? _tts;
  bool _unavailable = false;
  String? _lang;

  /// The most recent line, for on-screen captions.
  final ValueNotifier<VoiceLine?> lastLine = ValueNotifier(null);

  Future<void> speak(String text) async {
    final clean = _clean(text);
    if (clean.isEmpty) return;
    lastLine.value = VoiceLine(text, DateTime.now());
    if (_unavailable) return;
    try {
      final tts = _tts ??= await _create();
      final lang = I18n.instance.isMalay ? 'ms-MY' : 'en-US';
      if (lang != _lang) {
        _lang = lang;
        try {
          await tts.setLanguage(lang);
        } catch (_) {
          // Voice for that language not installed; the default voice still speaks.
        }
      }
      await tts.speak(clean);
    } catch (_) {
      _unavailable = true;
    }
  }

  Future<void> stop() async {
    if (_unavailable || _tts == null) return;
    try {
      await _tts!.stop();
    } catch (_) {}
  }

  Future<FlutterTts> _create() async {
    final tts = FlutterTts();
    // Optional tuning; ignore platforms that don't support a call.
    Future<void> tryCall(Future<dynamic> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await tryCall(() => tts.setQueueMode(1)); // queue lines instead of cutting off
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await tryCall(() => tts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            [IosTextToSpeechAudioCategoryOptions.duckOthers, IosTextToSpeechAudioCategoryOptions.mixWithOthers],
            IosTextToSpeechAudioMode.voicePrompt,
          ));
    }
    await tryCall(() => tts.setSpeechRate(kIsWeb ? 1.0 : 0.5));
    return tts;
  }

  /// Strips emoji and pictographs so the TTS engine doesn't read them out.
  static String _clean(String s) => s
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
