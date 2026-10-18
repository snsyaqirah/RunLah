import 'package:latlong2/latlong.dart';

import '../core/geo.dart';

/// Data model. Mirrors the ERD in "PRD, ERD & API Contract (v2)", section 14.
/// Times inside a race are seconds since the gun ("race time"), so the
/// simulator, the insights engine and the API all share one clock.

enum Gender { m, f }

extension GenderX on Gender {
  String get code => this == Gender.m ? 'M' : 'F';
}

enum CheckpointType { start, split, finish }

enum PassSource { gps, ocr, manual, import }

enum RankBasis { net, gun }

enum ResultsName { full, bibOnly }

enum Privacy { public, linkOnly, off }

enum RaceStatus { preRace, live, closed }

class Checkpoint {
  const Checkpoint({required this.id, required this.index, required this.name, required this.type, required this.distanceM, required this.location});
  final int id;

  /// Position in the race's ordered checkpoint list (0 = start).
  final int index;
  final String name;
  final CheckpointType type;
  final double distanceM;
  final LatLng location;

  String get shortLabel => type == CheckpointType.start
      ? 'Start'
      : type == CheckpointType.finish
          ? 'Finish'
          : '${(distanceM / 1000).toStringAsFixed(distanceM % 1000 == 0 ? 0 : 1)}K';
}

class Category {
  const Category({required this.id, required this.name, required this.gender, required this.ageMin, required this.ageMax});
  final int id;
  final String name; // "M 20-29"
  final Gender gender;
  final int ageMin;
  final int ageMax;
}

/// A named place drawn on maps and in the 3D scenes.
class Landmark {
  const Landmark({required this.name, required this.location, this.heightM = 0, this.kind = 'building'});
  final String name;
  final LatLng location;
  final double heightM;

  /// building | twin | tower | mosque | park
  final String kind;
}

class Race {
  Race({
    required this.id,
    required this.eventId,
    required this.name,
    required this.distanceM,
    required this.scheduledStart,
    required this.cutoffS,
    required this.route,
    required this.checkpoints,
    required this.categories,
    required this.landmarks,
    this.rankBasis = RankBasis.net,
  });
  final int id;
  final int eventId;
  final String name;
  final double distanceM;

  /// Planned gun time (local clock).
  final DateTime scheduledStart;
  final int cutoffS;
  final RoutePath route;

  /// Ordered start -> finish.
  final List<Checkpoint> checkpoints;
  final List<Category> categories;
  final List<Landmark> landmarks;
  RankBasis rankBasis;

  Checkpoint get start => checkpoints.first;
  Checkpoint get finish => checkpoints.last;

  /// Index of the checkpoint closest to [fraction] of the distance (0.5 = halfway).
  int checkpointNear(double fraction) {
    var best = 0;
    var bestDiff = double.infinity;
    for (final c in checkpoints) {
      final diff = (c.distanceM - distanceM * fraction).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = c.index;
      }
    }
    return best;
  }

  Category categoryById(int id) => categories.firstWhere((c) => c.id == id);
}

class RaceEvent {
  const RaceEvent({
    required this.id,
    required this.name,
    required this.slug,
    required this.city,
    required this.date,
    required this.races,
    required this.organizer,
    this.blurb = '',
    this.isDemo = false,
  });
  final int id;
  final String name;
  final String slug;
  final String city;
  final DateTime date;
  final List<Race> races;
  final String organizer;
  final String blurb;
  final bool isDemo;
}

class Participant {
  Participant({
    required this.id,
    required this.raceId,
    required this.bib,
    required this.name,
    required this.gender,
    required this.birthYear,
    required this.nation,
    required this.categoryId,
    this.resultsName = ResultsName.full,
    this.hasGps = false,
    this.verifyCode = '',
  });
  final int id;
  final int raceId;
  final String bib;
  final String name;
  final Gender gender;
  final int birthYear;

  /// ISO 3166 alpha-3, e.g. "MAS".
  final String nation;
  final int categoryId;
  ResultsName resultsName;

  /// Carries a phone or LTE watch (exact live position) vs. checkpoint-only.
  final bool hasGps;
  final String verifyCode;

  /// Name as other people see it in results (respects bib-only setting).
  String get displayName => resultsName == ResultsName.bibOnly ? 'Runner $bib' : name;

  String get firstName => name.split(' ').first == 'Muhammad' || name.split(' ').first == 'Nur'
      ? (name.split(' ').length > 1 ? name.split(' ')[1] : name)
      : name.split(' ').first;
}

/// How the simulator moves one runner: start delay after the gun and the
/// net time at a list of distance marks along the course.
/// `cumS[k]` = net seconds to reach `marksM[k]` metres; the last mark is the
/// finish. Marks are usually every kilometre.
class RunnerPlan {
  RunnerPlan({required this.startDelayS, required this.cumS, required this.marksM, this.dnfAtM})
      : assert(cumS.length == marksM.length);
  final double startDelayS;
  final List<double> cumS;
  final List<double> marksM;

  /// Distance where this runner drops out, if they do.
  final double? dnfAtM;

  double get netS => cumS.last;

  /// Every whole km plus the finish: [0, 1000, ..., 21000, 21097.5].
  static List<double> kmMarks(double distanceM) {
    final full = (distanceM / 1000).floor();
    return [for (var k = 0; k <= full; k++) k * 1000.0, if (distanceM > full * 1000) distanceM];
  }
}

class CheckpointPass {
  const CheckpointPass({required this.participantId, required this.checkpointIndex, required this.raceTimeS, required this.source, this.confidence = 1});
  final int participantId;
  final int checkpointIndex;

  /// Seconds since the gun.
  final double raceTimeS;
  final PassSource source;
  final double confidence;
}

enum ResultStatus { finished, onCourse, dnf, dns }

class PlaceInfo {
  const PlaceInfo({required this.place, required this.of, required this.behind});
  final int place;
  final int of;
  final int behind;

  /// Share of the group ahead of you, 0–100.
  double get topPct => of == 0 ? 0 : (place - 1) / of * 100;
}

class ResultRow {
  ResultRow({
    required this.participantId,
    required this.status,
    this.netS,
    this.gunS,
    this.startDelayS,
    this.overall,
    this.gender,
    this.category,
    this.nation,
    this.otherGenderAheadPct,
    this.avgPaceSPerKm,
    this.avgKph,
  });
  final int participantId;
  final ResultStatus status;
  final double? netS;
  final double? gunS;
  final double? startDelayS;
  final PlaceInfo? overall;
  final PlaceInfo? gender;
  final PlaceInfo? category;
  final PlaceInfo? nation;

  /// % of finishers of the other gender with a slower time than you.
  final double? otherGenderAheadPct;
  final double? avgPaceSPerKm;
  final double? avgKph;
}

class SectionResult {
  const SectionResult({
    required this.fromIndex,
    required this.toIndex,
    required this.distanceM,
    required this.durationS,
    required this.passed,
    required this.passedBy,
    required this.placeAtEnd,
    required this.basedOn,
  });
  final int fromIndex;
  final int toIndex;
  final double distanceM;
  final double durationS;
  final int passed;
  final int passedBy;

  /// Clock-order place when crossing the section end.
  final int placeAtEnd;

  /// Number of runners with a pass at both ends (denominator of the counts).
  final int basedOn;

  double get speedKph => durationS <= 0 ? 0 : distanceM / durationS * 3.6;
  double get paceSPerKm => distanceM <= 0 ? 0 : durationS / (distanceM / 1000);
}

class GroupStats {
  const GroupStats({required this.scope, required this.finishers, required this.medianNetS, required this.histogram, required this.histStartS, required this.histBinS, required this.female, required this.male, this.fastestNetS});
  final String scope; // overall | gender:F | category:12 | nation:MAS
  final int finishers;
  final double medianNetS;

  /// Finisher counts per bin of [histBinS] seconds starting at [histStartS].
  final List<int> histogram;
  final double histStartS;
  final double histBinS;
  final int female;
  final int male;
  final double? fastestNetS;
}

class CheerMessage {
  CheerMessage({required this.from, required this.body, required this.at, this.toParticipantId, this.read = false});
  final String from;
  final String body;
  final DateTime at;
  final int? toParticipantId;
  bool read;
}

class SosAlert {
  SosAlert({required this.id, required this.participantId, required this.location, required this.raceTimeS, required this.reason, this.status = 'open'});
  final int id;
  final int participantId;
  final LatLng location;
  final double raceTimeS;
  final String reason;

  /// open | acknowledged | closed
  String status;
}
