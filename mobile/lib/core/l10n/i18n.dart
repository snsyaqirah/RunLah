import 'package:flutter/foundation.dart';

import 'bm_cheer.dart';
import 'bm_core.dart';
import 'bm_home.dart';
import 'bm_insights.dart';
import 'bm_organizer.dart';
import 'bm_profile.dart';
import 'bm_run.dart';
import 'bm_three.dart';

/// Lightweight BM / English translation.
///
/// Strings are written in English at the call site: `tr('Start run')`.
/// The Bahasa Malaysia text is looked up from the per-feature maps below;
/// a missing key falls back to English, so nothing ever shows blank.
/// Placeholders use braces: `tr('Passed {n} runners', {'n': 37})`.
///
/// The whole MaterialApp is keyed on [I18n.lang], so switching language
/// rebuilds every screen.
class I18n extends ChangeNotifier {
  I18n._();
  static final I18n instance = I18n._();

  static const supported = ['en', 'ms'];

  String _lang = 'en';
  String get lang => _lang;
  bool get isMalay => _lang == 'ms';

  set lang(String value) {
    if (!supported.contains(value) || value == _lang) return;
    _lang = value;
    notifyListeners();
  }

  static final Map<String, String> _bm = {
    ...bmCore,
    ...bmHome,
    ...bmRun,
    ...bmCheer,
    ...bmInsights,
    ...bmOrganizer,
    ...bmProfile,
    ...bmThree,
  };

  /// Keys that have no BM translation yet (debug builds only). Handy for
  /// finding gaps: call `I18n.missing` from a debug console.
  static final Set<String> missing = {};

  String translate(String en, [Map<String, Object?> args = const {}]) {
    var out = en;
    if (_lang == 'ms') {
      final bm = _bm[en];
      if (bm != null) {
        out = bm;
      } else if (kDebugMode) {
        missing.add(en);
      }
    }
    if (args.isNotEmpty) {
      args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
    }
    return out;
  }
}

/// Translate an English UI string into the current language.
String tr(String en, [Map<String, Object?> args = const {}]) => I18n.instance.translate(en, args);
