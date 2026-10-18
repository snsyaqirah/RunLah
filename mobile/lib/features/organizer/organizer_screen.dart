import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/sim/race_sim.dart';
import '../shell/demo_director.dart';
import 'field_ticker.dart';
import 'organizer_session.dart';
import 'tabs/camera_tab.dart';
import 'tabs/heatmap_tab.dart';
import 'tabs/race_control_tab.dart';
import 'tabs/results_tab.dart';
import 'tabs/setup_tab.dart';
import 'tabs/sos_tab.dart';

/// Organizer console (PRD "Organizer" role): race control, course heatmap,
/// SOS queue, checkpoint camera, results, event setup.
class OrganizerScreen extends StatefulWidget {
  const OrganizerScreen({super.key});

  @override
  State<OrganizerScreen> createState() => _OrganizerScreenState();
}

class _OrganizerScreenState extends State<OrganizerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 6, vsync: this);
  late final RaceSim _sim = context.read<RaceSim>();
  late final FieldTicker _ticker = FieldTicker(_sim, withFinishRate: true);
  late final OrganizerSession _session = OrganizerSession.of(_sim)..syncWithSim();
  StreamSubscription<SimEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _sim.events.listen(_onEvent);
    _session.addListener(_onSession);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  void _onEvent(SimEvent e) {
    if (e is! SosRaised || !mounted) return;
    final p = _sim.participant(e.alert.participantId);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RL.red,
      content: Text(tr('New SOS · bib {bib} · {reason}', {'bib': p.bib, 'reason': tr(e.alert.reason)})),
      action: _tabs.index == 2 ? null : SnackBarAction(label: tr('View'), textColor: Colors.white, onPressed: () => _tabs.animateTo(2)),
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.removeListener(_onSession);
    _ticker.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openSos = context.select<RaceSim, int>((s) => s.sosAlerts.where((a) => a.status == 'open').length);
    final review = _session.review.length;
    Tab tab(IconData icon, String label, {int badge = 0}) => Tab(
          height: 56,
          icon: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, size: 22)),
          text: label,
        );
    return ChangeNotifierProvider<OrganizerSession>.value(
      value: _session,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Organizer console')),
              Text(
                _sim.event.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted(context)),
              ),
            ],
          ),
          actions: [
            IconButton(tooltip: tr('Demo director'), onPressed: () => showDemoDirector(context), icon: const Icon(Icons.tune_rounded)),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            indicatorColor: RL.amber,
            indicatorWeight: 3,
            tabs: [
              tab(Icons.flag_rounded, tr('Race control')),
              tab(Icons.local_fire_department_rounded, tr('Heatmap')),
              tab(Icons.sos_rounded, tr('SOS'), badge: openSos),
              tab(Icons.document_scanner_rounded, tr('Camera'), badge: review),
              tab(Icons.emoji_events_rounded, tr('Results')),
              tab(Icons.checklist_rounded, tr('Setup')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          // Maps live inside the tabs; swiping would fight with them.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            RaceControlTab(ticker: _ticker, onOpenTab: _tabs.animateTo),
            HeatmapTab(ticker: _ticker),
            const SosTab(),
            const CameraTab(),
            const ResultsTab(),
            const SetupTab(),
          ],
        ),
      ),
    );
  }
}
