import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../home/home_data.dart';
import '../../home/widgets/route_painter.dart';
import '../organizer_session.dart';
import '../organizer_widgets.dart';

/// Event setup checklist (F02–F04, F03): what the organizer did before
/// race day. All done for the demo event.
class SetupTab extends StatelessWidget {
  const SetupTab({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final race = sim.race;
    final units = context.select<SettingsController, Units>((s) => s.units);
    final steps = <Widget>[
      _Step(
        n: 1,
        title: tr('Event created'),
        subtitle: '${sim.event.name} · ${fmtDate(sim.event.date)} · ${sim.event.city}',
      ),
      _Step(
        n: 2,
        title: tr('Route GPX uploaded'),
        subtitle: tr('{race} · {d} · {p} track points', {'race': tr(race.name), 'd': fmtDistance(race.distanceM, units), 'p': race.route.points.length}),
        extra: Container(
          height: 110,
          decoration: BoxDecoration(color: RL.navy, borderRadius: BorderRadius.circular(12)),
          child: RouteSilhouette(route: race.route, strokeWidth: 2.5, padding: 12, glow: true),
        ),
      ),
      _Step(
        n: 3,
        title: tr('{n} checkpoints placed', {'n': race.checkpoints.length - 1}),
        subtitle: tr('Every ~{d} plus the start line, as virtual geofences', {'d': fmtDistance(race.distanceM / 8, units)}),
        extra: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final c in race.checkpoints) _CpChip(label: cpLabel(c), name: c.name, color: c.type == CheckpointType.split ? RL.teal : RL.navy)],
        ),
      ),
      _Step(
        n: 4,
        title: tr('{n} bibs imported', {'n': fmtInt(sim.participants.length)}),
        subtitle: tr('{c} categories · gender, birth year and nationality per runner', {'c': race.categories.length}),
        extra: const _BibCsv(),
      ),
      const _Step(n: 5, title: '', subtitle: '', extra: _Staff()),
      _Step(
        n: 6,
        title: tr('Event published'),
        subtitle: tr('Visible in the app. Runners claim their bib with the verification code.'),
      ),
    ];
    return OrgTabList(
      children: [
        _Progress(done: steps.length, total: steps.length),
        ...steps,
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: done / total),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: v, strokeWidth: 7, color: RL.green, backgroundColor: RL.green.withValues(alpha: 0.15))),
                  Text('$done/$total', style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Event ready for race day'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: ink(context))),
                const SizedBox(height: 2),
                Text(tr('Everything below was set up in the admin web before race day.'), style: TextStyle(color: muted(context), fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.subtitle, this.extra});
  final int n;
  final String title;
  final String subtitle;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Tick(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: muted(context), height: 1.3)),
                    ],
                  ),
                ),
                Text('$n', style: TextStyle(fontWeight: FontWeight.w900, color: muted(context))),
              ],
            ),
          if (extra != null) ...[
            if (title.isNotEmpty) const SizedBox(height: 12),
            extra!,
          ],
        ],
      ),
    );
  }
}

/// Checkpoint chip that ellipsizes instead of overflowing on narrow phones.
class _CpChip extends StatelessWidget {
  const _CpChip({required this.label, required this.name, required this.color});
  final String label;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = dark && color == RL.navy ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: dark ? 0.3 : 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w900)),
          TextSpan(text: ' · $name'),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick();

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: RL.green, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
      );
}

class _BibCsv extends StatefulWidget {
  const _BibCsv();

  @override
  State<_BibCsv> createState() => _BibCsvState();
}

class _BibCsvState extends State<_BibCsv> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        context.read<OrganizerSession>().bibCsvReimported = true;
        setState(() => _running = false);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final session = context.read<OrganizerSession>();
    final total = sim.participants.length;
    final sample = StringBuffer('bib,name,gender,birth_year,nation,category\n');
    for (final p in sim.participants.take(5)) {
      sample.writeln('${p.bib},"${p.name}",${p.gender.code},${p.birthYear},${p.nation},${sim.race.categoryById(p.categoryId).name}');
    }
    sample.write('… ${tr('{n} more rows', {'n': fmtInt(total - 5)})}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CsvBlock(sample.toString()),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _running
              ? AnimatedBuilder(
                  key: const ValueKey('run'),
                  animation: _c,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr('Importing {n} / {t} bibs…', {'n': fmtInt((_c.value * total).round()), 't': fmtInt(total)}),
                        style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: _c.value, minHeight: 8, color: RL.teal)),
                    ],
                  ),
                )
              : Row(
                  key: const ValueKey('idle'),
                  children: [
                    Expanded(
                      child: Text(
                        session.bibCsvReimported
                            ? tr('{n} rows · 0 duplicates · 0 errors', {'n': fmtInt(total)})
                            : tr('bibs_klcity2026.csv · imported before race day'),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: session.bibCsvReimported ? RL.green : muted(context)),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('import-bibs'),
                      onPressed: () {
                        setState(() => _running = true);
                        _c.forward(from: 0);
                      },
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(tr('Import bib CSV')),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Staff extends StatelessWidget {
  const _Staff();

  @override
  Widget build(BuildContext context) {
    final staff = <(String, String, IconData)>[
      ('Aiman Hakim', tr('Checkpoint marshal lead · camera app'), Icons.photo_camera_rounded),
      ('Tan Mei Ling', tr('Timing & results'), Icons.timer_rounded),
      ('Dr. Priya Nair', tr('Medical lead · SOS queue'), Icons.medical_services_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Tick(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('{n} staff invited', {'n': staff.length}), style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                  const SizedBox(height: 2),
                  Text(tr('Organizer permission is granted per event'), style: TextStyle(fontSize: 12.5, color: muted(context))),
                ],
              ),
            ),
            Text('5', style: TextStyle(fontWeight: FontWeight.w900, color: muted(context))),
          ],
        ),
        const SizedBox(height: 10),
        for (final (name, role, icon) in staff)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                CircleAvatar(radius: 17, backgroundColor: RL.navy.withValues(alpha: 0.1), child: Icon(icon, size: 17, color: ink(context))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                      Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted(context))),
                    ],
                  ),
                ),
                Pill(tr('Joined'), color: RL.green),
              ],
            ),
          ),
      ],
    );
  }
}
