import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../organizer/field_ticker.dart';
import '../shell/demo_director.dart';
import '../three/race3d_mode.dart';
import 'event_detail_screen.dart';
import 'home_data.dart';
import 'widgets/bib_card.dart';
import 'widgets/motion.dart';
import 'widgets/race_hero_card.dart';
import 'widgets/route_painter.dart';
import 'widgets/weather_card.dart';

/// Home tab: greeting, race-day hero, quick actions, your bib, weather and
/// heat alert, events.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final FieldTicker _ticker = FieldTicker(context.read<RaceSim>(), withPlace: true);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ticker.active = context.select<ShellController, bool>((s) => s.tab == AppTab.home);
    final children = <Widget>[
      const _Greeting(),
      RaceHeroCard(ticker: _ticker),
      const _QuickActions(),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SectionLabel(tr('Your bib')), const BibCard()]),
      const WeatherCard(),
      const _Events(),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
          itemCount: children.length,
          separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 14 : 18),
          itemBuilder: (_, i) => FadeSlideIn(index: i, child: children[i]),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final name = context.select<SettingsController, String>((s) => s.displayName);
    final now = DateTime.now();
    final hello = switch (now.hour) {
      < 12 => tr('Good morning,'),
      < 15 => tr('Good afternoon,'),
      < 19 => tr('Good evening,'),
      _ => tr('Good night,'),
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hello, style: TextStyle(color: muted(context), fontWeight: FontWeight.w600)),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w900, color: ink(context)),
              ),
              Text(fmtDate(now), style: TextStyle(color: muted(context), fontSize: 12.5)),
            ],
          ),
        ),
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.read<ShellController>().tab = AppTab.me,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [RL.amber, Color(0xFFF2B33D)]),
              boxShadow: [BoxShadow(color: RL.amber.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ quick actions

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, Color, VoidCallback)>[
      (Icons.directions_run_rounded, tr('Start run'), RL.amber, () => goToTab(context, AppTab.run)),
      (Icons.campaign_rounded, tr('Cheer'), const Color(0xFFEC4899), () => goToTab(context, AppTab.cheer)),
      (Icons.emoji_events_rounded, tr('Results'), RL.green, () => goToTab(context, AppTab.results)),
      (Icons.threed_rotation_rounded, tr('3D flyover'), RL.teal, () => openRace3D(context, Race3DMode.flyover)),
      (Icons.admin_panel_settings_rounded, tr('Organizer'), const Color(0xFF4A6FA5), () => openOrganizer(context)),
      (Icons.tune_rounded, tr('Demo director'), RL.slate, () => showDemoDirector(context)),
    ];
    Widget row(int from) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = from; i < from + 3; i++) ...[
                Expanded(child: _ActionTile(icon: actions[i].$1, label: actions[i].$2, color: actions[i].$3, onTap: actions[i].$4)),
                if (i < from + 2) const SizedBox(width: 10),
              ],
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionLabel(tr('Quick actions')), row(0), const SizedBox(height: 10), row(3)],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w800, color: ink(context)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ events

class _Events extends StatelessWidget {
  const _Events();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final upcoming = upcomingEvents(sim.event.date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(tr('Your events')),
        const _DemoEventTile(),
        const SizedBox(height: 18),
        SectionLabel(tr('Upcoming')),
        for (final e in upcoming) ...[
          _UpcomingTile(e: e),
          const SizedBox(height: 10),
        ],
        Text(
          tr('Upcoming events are fictional, for the demo.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: muted(context), fontSize: 11.5),
        ),
      ],
    );
  }
}

class _DemoEventTile extends StatelessWidget {
  const _DemoEventTile();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final official = context.select<RaceSim, bool>((s) => s.official);
    final race = sim.race;
    return RLCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventDetailScreen())),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [RL.navy, Color(0xFF26467E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: RouteSilhouette(route: race.route, strokeWidth: 2, padding: 10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                switch (status) {
                  RaceStatus.preRace => Pill(tr('Today'), color: RL.amber),
                  RaceStatus.live => Pill(tr('Live'), color: RL.red, icon: Icons.circle),
                  RaceStatus.closed => Pill(official ? tr('Official') : tr('Provisional'), color: official ? RL.green : RL.amber),
                },
                const SizedBox(height: 5),
                Text(sim.event.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: ink(context), height: 1.2)),
                const SizedBox(height: 3),
                Text(
                  '${fmtClock(race.scheduledStart)} · ${sim.event.city} · ${tr('{n} runners', {'n': fmtInt(sim.participants.length)})}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: muted(context)),
        ],
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.e});
  final UpcomingEvent e;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _showUpcoming(context, e),
      child: Row(
        children: [
          _EventBadge(e: e, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                const SizedBox(height: 3),
                Text('${fmtDate(e.date)} · ${e.city}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted(context))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pill(e.distance, color: e.colors.last),
        ],
      ),
    );
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge({required this.e, required this.size});
  final UpcomingEvent e;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: e.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(e.icon, color: Colors.white, size: size * 0.45),
      );
}

void _showUpcoming(BuildContext context, UpcomingEvent e) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _UpcomingSheet(e: e),
  );
}

class _UpcomingSheet extends StatefulWidget {
  const _UpcomingSheet({required this.e});
  final UpcomingEvent e;

  @override
  State<_UpcomingSheet> createState() => _UpcomingSheetState();
}

class _UpcomingSheetState extends State<_UpcomingSheet> {
  bool _remind = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.e;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _EventBadge(e: e, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: ink(context))),
                      Text('${fmtDate(e.date)} · ${tr('Gun {t}', {'t': e.gun})}', style: TextStyle(color: muted(context))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(e.blurb, style: TextStyle(color: ink(context), height: 1.4)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Pill(e.distance, color: e.colors.last),
                Pill(e.city, color: RL.navy),
                Pill(tr('{n} places', {'n': fmtInt(e.capacity)}), color: RL.slate),
                Pill(tr('Fictional'), color: RL.slate),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _remind
                    ? OutlinedButton.icon(
                        key: const ValueKey('on'),
                        onPressed: () => setState(() => _remind = false),
                        icon: const Icon(Icons.notifications_active_rounded, color: RL.green),
                        label: Text(tr('We\'ll remind you when registration opens')),
                      )
                    : FilledButton.icon(
                        key: const ValueKey('off'),
                        onPressed: () => setState(() => _remind = true),
                        icon: const Icon(Icons.notifications_none_rounded),
                        label: Text(tr('Remind me when registration opens')),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
