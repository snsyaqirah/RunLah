import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/achievements.dart';
import '../../data/models.dart';
import 'profile_widgets.dart';

Color distanceColor(double metres) => switch (pbDistanceFor(metres)) {
      PbDistance.k5 => RL.teal,
      PbDistance.k10 => const Color(0xFF8B5CF6),
      PbDistance.half => RL.amber,
      PbDistance.full => RL.red,
      null => RL.slate,
    };

String distanceLabel(double metres) => pbDistanceFor(metres)?.label ?? '${(metres / 1000).toStringAsFixed(1)}K';

/// Status pill for the race tracked with RunLah.
Widget currentRacePill(PassportEntry e) {
  return switch (e.status) {
    ResultStatus.finished => e.official ? Pill(tr('Official'), color: RL.green, icon: Icons.verified_rounded) : Pill(tr('Provisional'), color: RL.amber),
    ResultStatus.onCourse => Pill(tr('Live'), color: RL.green, filled: true),
    ResultStatus.dnf => Pill(tr('DNF'), color: RL.red),
    _ => Pill(tr('Upcoming'), color: RL.teal),
  };
}

// ---------------------------------------------------------- personal bests

class PersonalBestGrid extends StatelessWidget {
  const PersonalBestGrid({super.key, required this.bests});
  final Map<PbDistance, PersonalBest> bests;

  @override
  Widget build(BuildContext context) {
    Widget row(PbDistance a, PbDistance b, int i) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Reveal(index: i, child: _PbTile(pb: bests[a]!))),
              const SizedBox(width: 10),
              Expanded(child: Reveal(index: i + 1, child: _PbTile(pb: bests[b]!))),
            ],
          ),
        );
    return Column(
      children: [
        row(PbDistance.k5, PbDistance.k10, 0),
        const SizedBox(height: 10),
        row(PbDistance.half, PbDistance.full, 2),
      ],
    );
  }
}

class _PbTile extends StatelessWidget {
  const _PbTile({required this.pb});
  final PersonalBest pb;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = distanceColor(pb.distance.metres);
    final e = pb.entry;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pb.isNew ? (dark ? const Color(0xFF2A2112) : RL.amberSoft) : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(RL.radius),
        border: Border.all(color: pb.isNew ? RL.amber : (dark ? const Color(0xFF1F2937) : RL.line), width: pb.isNew ? 1.6 : 1),
        boxShadow: pb.isNew ? [BoxShadow(color: RL.amber.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 6))] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(pb.distance.label, style: TextStyle(fontWeight: FontWeight.w900, color: ink(context), fontSize: 13)),
              ),
              if (pb.isNew) Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Pill(tr('New PB'), filled: true, icon: Icons.bolt_rounded))),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              e == null ? '–' : fmtDuration(e.netS),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1.05,
                color: pb.isNew ? RL.amber : ink(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            e == null
                ? (pb.distance == PbDistance.full ? tr('Your first full marathon awaits') : tr('Not raced yet'))
                : (pb.fromFreeRun ? '${tr('Free run')} · ${e.name}' : e.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted(context), height: 1.25),
          ),
          if (pb.isNew && pb.improvementS != null) ...[
            const SizedBox(height: 6),
            Text(
              tr('{gap} faster than {old}', {'gap': fmtDuration(pb.improvementS), 'old': fmtDuration(pb.previous!.netS)}),
              style: const TextStyle(fontSize: 12, color: RL.green, fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
    return pb.isNew
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: card,
          )
        : card;
  }
}

// ------------------------------------------------------------------ passport

/// Timeline of races, newest first, grouped by year, with passport stamps.
class RacePassport extends StatelessWidget {
  const RacePassport({super.key, required this.entries, this.newPbEntryId});
  final List<PassportEntry> entries;
  final String? newPbEntryId;

  static const _tilt = [-0.12, 0.08, -0.05, 0.11, -0.09, 0.04];

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    int? year;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.date.year != year) {
        year = e.date.year;
        children.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 6, bottom: 8, left: 4),
          child: Text('$year', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: muted(context), letterSpacing: 0.5)),
        ));
      }
      final last = i == entries.length - 1;
      children.add(Reveal(
        index: i,
        child: _PassportRow(entry: e, tilt: _tilt[i % _tilt.length], last: last, newPb: e.id == newPbEntryId),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _PassportRow extends StatelessWidget {
  const _PassportRow({required this.entry, required this.tilt, required this.last, required this.newPb});
  final PassportEntry entry;
  final double tilt;
  final bool last;
  final bool newPb;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = distanceColor(entry.distanceM);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 62,
            child: Column(
              children: [
                Transform.rotate(
                  angle: tilt,
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: CustomPaint(
                      painter: StampPainter(color: entry.finished || entry.isCurrent ? color : RL.slate),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(distanceLabel(entry.distanceM), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
                                Text(
                                  fmtDate(entry.date).split(' ').skip(1).join(' ').toUpperCase(),
                                  style: TextStyle(color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w800, fontSize: 7.5, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(color: dark ? Colors.white12 : RL.line, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 12),
              child: entry.isCurrent ? _CurrentCard(entry: entry, newPb: newPb) : _HistoryCard(entry: entry),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});
  final PassportEntry entry;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), height: 1.2)),
          const SizedBox(height: 2),
          Text(
            [fmtDate(entry.date), ?entry.city, ?entry.subtitle].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(
                fmtDuration(entry.netS),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              if (entry.place != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    tr('{place} of {n}', {'place': ordinal(entry.place!), 'n': fmtInt(entry.of!)}),
                    style: TextStyle(fontSize: 12.5, color: muted(context), fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.download_done_rounded, size: 14, color: muted(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(tr('Imported result'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: muted(context))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.entry, required this.newPb});
  final PassportEntry entry;
  final bool newPb;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status = entry.status;
    final hint = switch (status) {
      ResultStatus.finished => tr('Tap for your Race Insights'),
      ResultStatus.onCourse => tr('On course now · tap to follow live'),
      ResultStatus.dnf => tr('Did not finish · tap for details'),
      _ => tr('Race day · tap for live tracking'),
    };
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(RL.radius),
          border: Border.all(color: RL.amber, width: 1.6),
          boxShadow: [BoxShadow(color: RL.amber.withValues(alpha: dark ? 0.12 : 0.18), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(RL.radius),
          onTap: () => openInsights(context, entry.participantId!),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    currentRacePill(entry),
                    Pill('RunLah', color: RL.navySoft, icon: Icons.directions_run_rounded),
                    if (newPb) Pill(tr('New PB'), filled: true, icon: Icons.bolt_rounded),
                  ],
                ),
                const SizedBox(height: 8),
                Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), height: 1.2)),
                const SizedBox(height: 2),
                Text(
                  [fmtDate(entry.date), ?entry.city, ?entry.subtitle].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
                if (entry.finished) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      CountUp(
                        value: entry.netS!,
                        format: (v) => fmtDuration(v),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: RL.amber, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      if (entry.place != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            tr('{place} of {n} · Top {pct}', {'place': ordinal(entry.place!), 'n': fmtInt(entry.of!), 'pct': fmtPct(entry.topPct!)}),
                            style: TextStyle(fontSize: 12.5, color: ink(context), fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(hint, style: const TextStyle(fontSize: 12.5, color: RL.amber, fontWeight: FontWeight.w800)),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: RL.amber),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
