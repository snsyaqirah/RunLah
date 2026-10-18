import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/i18n.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// Outcome of "Join with bib" (F06).
enum ClaimResult { success, invalid, unknownBib, wrongCode, alreadyYours, claimedByOther }

/// Bibs this device has claimed with bib + verification code (F06).
/// Stands in for `POST /participants/claim`; persisted in SharedPreferences.
class BibClaims extends ChangeNotifier {
  BibClaims._(this._prefs) : _claimed = {...?_prefs.getStringList(_key)};

  static const _key = 'home.claimedBibs';
  static final _cache = Expando<BibClaims>();

  /// One instance per SharedPreferences (tests get a fresh one each time).
  static BibClaims of(SharedPreferences prefs) => _cache[prefs] ??= BibClaims._(prefs);

  final SharedPreferences _prefs;
  final Set<String> _claimed;

  bool isClaimed(String bib) => _claimed.contains(bib);

  /// Checks the bib against the start list and its verification code.
  /// Friends' bibs count as claimed by their own RunLah accounts.
  ClaimResult claim(RaceSim sim, String rawBib, String rawCode) {
    final bib = rawBib.trim();
    final code = rawCode.trim();
    if (!RegExp(r'^\d{3,6}$').hasMatch(bib) || !RegExp(r'^\d{6}$').hasMatch(code)) return ClaimResult.invalid;
    final p = sim.byBib(bib);
    if (p == null) return ClaimResult.unknownBib;
    if (p.verifyCode != code) return ClaimResult.wrongCode;
    if (_claimed.contains(bib)) return ClaimResult.alreadyYours;
    if (sim.friendIds.contains(p.id)) return ClaimResult.claimedByOther;
    _claimed.add(bib);
    _prefs.setStringList(_key, _claimed.toList());
    notifyListeners();
    return ClaimResult.success;
  }
}

/// Start corral, from the seeding the organizer did with expected times
/// (in the demo: the runner's start delay behind the gun).
String corralFor(RaceSim sim, int participantId) {
  final d = sim.plan(participantId).startDelayS;
  if (d < 90) return 'A';
  if (d < 240) return 'B';
  if (d < 480) return 'C';
  if (d < 720) return 'D';
  return 'E';
}

/// Fictional upcoming events shown under "Upcoming" (demo content).
class UpcomingEvent {
  const UpcomingEvent({
    required this.name,
    required this.city,
    required this.distance,
    required this.date,
    required this.gun,
    required this.colors,
    required this.icon,
    required this.blurb,
    required this.capacity,
  });
  final String name;
  final String city;
  final String distance;
  final DateTime date;
  final String gun;
  final List<Color> colors;
  final IconData icon;
  final String blurb;
  final int capacity;
}

List<UpcomingEvent> upcomingEvents(DateTime from) {
  DateTime day(int plus) {
    final d = DateTime(from.year, from.month, from.day).add(Duration(days: plus));
    // Races are on Sundays.
    return d.add(Duration(days: (DateTime.sunday - d.weekday) % 7));
  }

  return [
    UpcomingEvent(
      name: 'Putrajaya Lakeside 10K',
      city: 'Putrajaya',
      distance: '10K',
      date: day(26),
      gun: '06:30',
      colors: const [Color(0xFF0F766E), Color(0xFF2A9DB5)],
      icon: Icons.water_rounded,
      blurb: tr('A flat, fast loop around the lake and the bridges. Good for a 10K personal best.'),
      capacity: 6000,
    ),
    UpcomingEvent(
      name: 'Penang Heritage Night Run',
      city: 'George Town',
      distance: '12K',
      date: day(54),
      gun: '20:00',
      colors: const [Color(0xFF4C1D95), Color(0xFFDB2777)],
      icon: Icons.nightlight_round,
      blurb: tr('Through the lit-up heritage streets of George Town, finishing at the Esplanade.'),
      capacity: 4500,
    ),
    UpcomingEvent(
      name: 'Kota Kinabalu Sunrise Half',
      city: 'Kota Kinabalu',
      distance: '21.1K',
      date: day(89),
      gun: '05:00',
      colors: const [Color(0xFFB45309), Color(0xFFE8930C)],
      icon: Icons.wb_twilight_rounded,
      blurb: tr('Along the waterfront at first light, with Mount Kinabalu on a clear morning.'),
      capacity: 5000,
    ),
  ];
}

/// Localised short label for a checkpoint ("Start", "2.6K", "Finish").
String cpLabel(Checkpoint c) => switch (c.type) {
      CheckpointType.start => tr('Start'),
      CheckpointType.finish => tr('Finish'),
      CheckpointType.split => c.shortLabel,
    };
