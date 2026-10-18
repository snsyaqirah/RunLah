import 'package:flutter/widgets.dart';

import 'bib_scanner.dart';

/// Web build: no ML Kit, so no camera OCR. The console uses the keypad and
/// simulated reads instead.
BibScanner createBibScanner() => _UnsupportedScanner();

class _UnsupportedScanner implements BibScanner {
  @override
  bool get available => false;

  @override
  final ValueNotifier<ScannerPhase> phase = ValueNotifier(ScannerPhase.idle);

  @override
  String? get error => null;

  @override
  Future<void> start(void Function(List<OcrHit> hits) onHits) async {}

  @override
  Future<void> stop() async {}

  @override
  Widget preview() => const SizedBox.shrink();

  @override
  void dispose() => phase.dispose();
}
