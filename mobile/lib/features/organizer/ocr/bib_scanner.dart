import 'package:flutter/widgets.dart';

import 'bib_scanner_stub.dart' if (dart.library.io) 'bib_scanner_mobile.dart' as impl;

/// A number the camera saw that looks like a bib.
class OcrHit {
  const OcrHit(this.bib, this.confidence);
  final String bib;
  final double confidence;
}

enum ScannerPhase { idle, starting, running, error }

/// Checkpoint camera (F31): camera preview + on-device text recognition on
/// still frames. On Android/iOS it uses the camera plugin and ML Kit; on web
/// (and desktop) [available] is false and the console falls back to the
/// keypad and simulated reads.
abstract class BibScanner {
  static BibScanner create() => impl.createBibScanner();

  /// Camera + OCR can run on this platform.
  bool get available;

  ValueNotifier<ScannerPhase> get phase;

  /// Human-readable reason when [phase] is [ScannerPhase.error].
  String? get error;

  /// Starts the camera and calls [onHits] after each processed frame
  /// (roughly every 700 ms). Never throws: failures set [phase] to error.
  Future<void> start(void Function(List<OcrHit> hits) onHits);

  Future<void> stop();

  /// The live camera preview (only meaningful while running).
  Widget preview();

  void dispose();
}

/// Pulls bib-like numbers (3–5 digits) out of recognised text. Taller text
/// scores higher: the printed bib number is the biggest thing on the bib.
List<OcrHit> extractBibs(Iterable<({String text, double height, double? confidence})> elements) {
  final list = elements.toList();
  if (list.isEmpty) return const [];
  final maxH = list.map((e) => e.height).fold<double>(1, (a, b) => a > b ? a : b);
  final out = <String, double>{};
  for (final e in list) {
    final digits = e.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 3 || digits.length > 5) continue;
    if (e.text.replaceAll(RegExp(r'[0-9#.\-\s]'), '').isNotEmpty) continue;
    final base = e.confidence ?? 0.86;
    final c = (base * (0.72 + 0.28 * (e.height / maxH))).clamp(0.0, 0.99);
    if (c > (out[digits] ?? 0)) out[digits] = c;
  }
  final hits = [for (final e in out.entries) OcrHit(e.key, e.value)]..sort((a, b) => b.confidence.compareTo(a.confidence));
  return hits;
}
