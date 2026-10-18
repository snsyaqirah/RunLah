import 'dart:async';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/l10n/i18n.dart';
import '../core/theme.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../data/sim/race_sim.dart';

enum NoticeKind { checkpoint, finish, cheer, sos, race, results }

class AppNotice {
  AppNotice({required this.kind, required this.title, required this.body, required this.at, this.participantId});
  final NoticeKind kind;
  final String title;
  final String body;
  final DateTime at;
  final int? participantId;
  bool read = false;

  IconData get icon => switch (kind) {
        NoticeKind.checkpoint => Icons.flag_circle_rounded,
        NoticeKind.finish => Icons.sports_score_rounded,
        NoticeKind.cheer => Icons.campaign_rounded,
        NoticeKind.sos => Icons.sos_rounded,
        NoticeKind.race => Icons.timer_rounded,
        NoticeKind.results => Icons.emoji_events_rounded,
      };

  Color get color => switch (kind) {
        NoticeKind.checkpoint => RL.teal,
        NoticeKind.finish => RL.amber,
        NoticeKind.cheer => const Color(0xFFEC4899),
        NoticeKind.sos => RL.red,
        NoticeKind.race => RL.navy,
        NoticeKind.results => RL.green,
      };
}

/// Hook for real OS notifications (local notifications on device, FCM in
/// production). Set by services/push_service.dart at startup.
typedef PlatformNotifier = Future<void> Function(AppNotice notice);

/// Turns simulator / server events into notices: an in-app feed, a banner
/// stream for the shell, and OS notifications through [platformNotifier].
class NotificationCenter extends ChangeNotifier {
  NotificationCenter(this.sim, this.follows) {
    _sub = sim.events.listen(_onEvent);
  }

  final RaceSim sim;
  final FollowsController follows;
  late final StreamSubscription<SimEvent> _sub;
  PlatformNotifier? platformNotifier;

  final List<AppNotice> feed = [];
  final _banners = StreamController<AppNotice>.broadcast();

  /// In-app banners (the shell shows these at the top of the screen).
  Stream<AppNotice> get banners => _banners.stream;

  int get unread => feed.where((n) => !n.read).length;

  void markAllRead() {
    for (final n in feed) {
      n.read = true;
    }
    notifyListeners();
  }

  void post(AppNotice n, {bool banner = true, bool platform = true}) {
    feed.insert(0, n);
    if (feed.length > 200) feed.removeLast();
    if (banner) _banners.add(n);
    if (platform) platformNotifier?.call(n);
    notifyListeners();
  }

  void _onEvent(SimEvent e) {
    final at = sim.wallClockAt(e.raceTimeS);
    switch (e) {
      case GunFired():
        post(AppNotice(kind: NoticeKind.race, title: tr('Gun! The race is live'), body: tr('{race} started at {time}', {'race': sim.race.name, 'time': fmtClock(at)}), at: at));
      case CheckpointPassed(:final participantId, :final checkpointIndex):
        if (participantId == sim.youId || !follows.notifies(participantId)) return;
        final p = sim.participant(participantId);
        final cp = sim.race.checkpoints[checkpointIndex];
        final eta = sim.etaToDistance(participantId, sim.race.distanceM, e.raceTimeS);
        post(AppNotice(
          kind: NoticeKind.checkpoint,
          participantId: participantId,
          title: tr('{name} passed {cp}', {'name': p.firstName, 'cp': cp.shortLabel}),
          body: tr('{place} · {time} elapsed · finish ETA {eta}', {
            'place': cp.name,
            'time': fmtDuration(sim.elapsedAt(participantId, e.raceTimeS)),
            'eta': eta == null ? '–' : fmtClock(sim.wallClockAt(eta)),
          }),
          at: at,
        ));
      case RunnerFinished(:final participantId):
        if (participantId != sim.youId && !follows.notifies(participantId)) return;
        final p = sim.participant(participantId);
        final you = participantId == sim.youId;
        post(AppNotice(
          kind: NoticeKind.finish,
          participantId: participantId,
          title: you ? tr('You finished! 🎉') : tr('{name} finished! 🎉', {'name': p.firstName}),
          body: tr('Net time {net}. Tap to see Race Insights.', {'net': fmtDuration(sim.plan(participantId).netS)}),
          at: at,
        ));
      case CheerReceived(:final message):
        post(AppNotice(kind: NoticeKind.cheer, participantId: sim.youId, title: tr('Cheer from {name}', {'name': message.from}), body: message.body, at: at));
      case SosRaised(:final alert):
        final p = sim.participant(alert.participantId);
        post(
          AppNotice(kind: NoticeKind.sos, participantId: alert.participantId, title: tr('SOS · bib {bib}', {'bib': p.bib}), body: alert.reason, at: at),
          platform: false,
        );
      case RaceStatusChanged(:final status):
        if (status == RaceStatus.closed) {
          post(AppNotice(kind: NoticeKind.race, title: tr('Race closed'), body: tr('Cutoff reached. Provisional results are ready.'), at: at), platform: false);
        }
      case ResultsPublished():
        post(AppNotice(kind: NoticeKind.results, title: tr('Official results are out'), body: tr('Race Insights are now official. Share your card!'), at: at));
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _banners.close();
    super.dispose();
  }
}
