import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'bib_scanner.dart';

/// Android / iOS: camera preview + ML Kit text recognition on still frames.
BibScanner createBibScanner() => _MobileBibScanner();

class _MobileBibScanner implements BibScanner {
  static const _frameEvery = Duration(milliseconds: 700);

  CameraController? _camera;
  TextRecognizer? _ocr;
  bool _running = false;
  bool _disposed = false;
  String? _error;

  @override
  bool get available => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  final ValueNotifier<ScannerPhase> phase = ValueNotifier(ScannerPhase.idle);

  @override
  String? get error => _error;

  @override
  Future<void> start(void Function(List<OcrHit> hits) onHits) async {
    if (!available || _running) return;
    _set(ScannerPhase.starting);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('No camera found');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await cam.initialize();
      if (_disposed) {
        await cam.dispose();
        return;
      }
      _camera = cam;
      _ocr = TextRecognizer(script: TextRecognitionScript.latin);
      _running = true;
      _set(ScannerPhase.running);
      unawaited(_loop(onHits));
    } catch (e) {
      _error = e is CameraException ? (e.description ?? e.code) : '$e';
      _set(ScannerPhase.error);
      await _release();
    }
  }

  Future<void> _loop(void Function(List<OcrHit> hits) onHits) async {
    while (_running && !_disposed) {
      final started = DateTime.now();
      final cam = _camera, ocr = _ocr;
      if (cam == null || ocr == null || !cam.value.isInitialized) break;
      try {
        if (!cam.value.isTakingPicture) {
          final shot = await cam.takePicture();
          final text = await ocr.processImage(InputImage.fromFilePath(shot.path));
          unawaited(File(shot.path).delete().then((_) {}, onError: (_) {}));
          final hits = extractBibs([
            for (final b in text.blocks)
              for (final l in b.lines)
                for (final e in l.elements) (text: e.text, height: e.boundingBox.height, confidence: e.confidence ?? l.confidence),
          ]);
          if (_running && !_disposed) onHits(hits);
        }
      } catch (_) {
        // A dropped frame is fine; try again on the next tick.
      }
      final wait = _frameEvery - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _release();
    _set(ScannerPhase.idle);
  }

  Future<void> _release() async {
    final cam = _camera, ocr = _ocr;
    _camera = null;
    _ocr = null;
    try {
      await cam?.dispose();
    } catch (_) {}
    try {
      await ocr?.close();
    } catch (_) {}
  }

  void _set(ScannerPhase p) {
    if (!_disposed) phase.value = p;
  }

  @override
  Widget preview() {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(cam);
  }

  @override
  void dispose() {
    _running = false;
    _disposed = true;
    _release();
    phase.dispose();
  }
}
