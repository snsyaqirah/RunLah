import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// Why a checkpoint read is waiting for a marshal.
enum ReviewReason { lowConfidence, notInStartList }

/// A camera read the marshal must confirm or reject.
class ReviewItem {
  ReviewItem({required this.bib, required this.checkpointIndex, required this.raceTimeS, required this.confidence, required this.reason});
  final String bib;
  final int checkpointIndex;
  final double raceTimeS;
  final double confidence;
  final ReviewReason reason;
}

/// Reads below this confidence (or with an unknown bib) go to review.
const double kOcrAcceptConfidence = 0.80;

/// Organizer console state that outlives the screen (review queue, medic
/// dispatches, imports). One per [RaceSim]; cleared when the demo resets.
class OrganizerSession extends ChangeNotifier {
  OrganizerSession._(this.sim);

  static final _cache = Expando<OrganizerSession>();
  static OrganizerSession of(RaceSim sim) => _cache[sim] ??= OrganizerSession._(sim);

  final RaceSim sim;
  final List<ReviewItem> review = [];

  /// SOS alert ids a medic team has been sent to.
  final Map<int, int> dispatched = {};

  /// Checkpoint the camera / keypad records at.
  int checkpoint = 1;

  /// Cached official timing CSV (built once; it's 11,664 rows).
  String? _csv;
  String get timingCsv => _csv ??= sim.exportTimingCsv();

  bool bibCsvReimported = false;
  final _rng = math.Random(31);

  /// Called when the console opens: a reset demo starts with a clean slate.
  void syncWithSim() {
    if (sim.status == RaceStatus.preRace && sim.staffReads.isEmpty && sim.sosAlerts.isEmpty) {
      review.clear();
      dispatched.clear();
    }
  }

  void setCheckpoint(int i) {
    checkpoint = i;
    notifyListeners();
  }

  /// Applies the confidence threshold: good reads are recorded, the rest
  /// wait in [review]. Returns the recorded read, or null if queued.
  StaffRead? submitOcr(String bib, double confidence, {int? checkpointIndex}) {
    final cp = checkpointIndex ?? checkpoint;
    final known = sim.byBib(bib) != null;
    if (known && confidence >= kOcrAcceptConfidence) {
      return sim.recordRead(bib, cp, source: PassSource.ocr, confidence: confidence);
    }
    review.insert(
      0,
      ReviewItem(
        bib: bib,
        checkpointIndex: cp,
        raceTimeS: sim.raceTime,
        confidence: confidence,
        reason: known ? ReviewReason.lowConfidence : ReviewReason.notInStartList,
      ),
    );
    notifyListeners();
    return null;
  }

  /// Marshal confirms a read (optionally with a corrected bib).
  /// Returns false if the bib still isn't on the start list.
  bool confirm(ReviewItem item, {String? correctedBib}) {
    final bib = (correctedBib ?? item.bib).trim();
    if (sim.byBib(bib) == null) return false;
    review.remove(item);
    sim.recordRead(bib, item.checkpointIndex, source: correctedBib == null ? PassSource.ocr : PassSource.manual, confidence: correctedBib == null ? item.confidence : 1);
    notifyListeners();
    return true;
  }

  void reject(ReviewItem item) {
    review.remove(item);
    notifyListeners();
  }

  void dispatchMedic(SosAlert alert) {
    dispatched[alert.id] = 1 + (alert.id * 7) % 5;
    if (alert.status == 'open') {
      sim.updateSos(alert, 'acknowledged');
    }
    notifyListeners();
  }

  bool hasRead(String bib, int cp) => sim.staffReads.any((r) => r.bib == bib && r.checkpointIndex == cp);

  /// Demo stand-in for the camera: a runner who crossed [cp] in the last
  /// ~90 s is "seen". Most reads are clean; some come back with low
  /// confidence or a misread number so the review queue has work.
  ({String bib, double confidence, Participant? truth})? simulateCameraRead(int cp) {
    if (sim.status == RaceStatus.preRace) return null;
    final t = sim.raceTime;
    final times = sim.crossingTable.times[cp];
    final runners = sim.crossingTable.runners;
    final candidates = <int>[];
    for (final window in const [90.0, 300.0, 900.0]) {
      for (var i = 0; i < times.length; i++) {
        final c = times[i];
        if (!c.isNaN && c <= t && c > t - window && !hasRead(runners[i].bib, cp)) candidates.add(i);
      }
      if (candidates.isNotEmpty) break;
    }
    if (candidates.isEmpty) return null;
    final p = runners[candidates[_rng.nextInt(candidates.length)]];
    final roll = _rng.nextDouble();
    if (roll < 0.66) {
      return (bib: p.bib, confidence: 0.88 + _rng.nextDouble() * 0.11, truth: p);
    }
    if (roll < 0.84) {
      return (bib: p.bib, confidence: 0.52 + _rng.nextDouble() * 0.22, truth: p);
    }
    // Misread: a smudged first digit reads as 8 (no 8xxxx bibs exist).
    final wrong = '8${p.bib.substring(1)}';
    return (bib: sim.byBib(wrong) == null ? wrong : '${p.bib}7', confidence: 0.6 + _rng.nextDouble() * 0.2, truth: p);
  }
}
