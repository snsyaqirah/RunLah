import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../home/widgets/motion.dart';
import '../organizer_session.dart';
import '../organizer_widgets.dart';

const _csvName = 'klcity2026_official_timing.csv';

/// Results: import the timing company's CSV (F27), publish official results
/// (F33), share the CSV.
class ResultsTab extends StatefulWidget {
  const ResultsTab({super.key});

  @override
  State<ResultsTab> createState() => _ResultsTabState();
}

enum _Import { ready, running, done }

class _ResultsTabState extends State<ResultsTab> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final AnimationController _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  _Import _state = _Import.ready;
  late final String _csv;
  late final List<String> _lines;

  @override
  void initState() {
    super.initState();
    _csv = context.read<OrganizerSession>().timingCsv;
    _lines = const LineSplitter().convert(_csv).where((l) => l.isNotEmpty).toList();
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        context.read<RaceSim>().publishOfficial(fromImport: true);
        setState(() => _state = _Import.done);
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  int get _rows => _lines.length - 1;

  Future<void> _import() async {
    final sim = context.read<RaceSim>();
    if (sim.status != RaceStatus.closed) {
      final ok = await confirmAction(
        context,
        title: tr('Race is still running'),
        body: tr('Importing the official timing closes the race now and publishes the imported times as official results.'),
        confirm: tr('Import & publish'),
        icon: Icons.upload_file_rounded,
        confirmKey: const Key('confirm-import'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _state = _Import.running);
    _progress.forward(from: 0);
  }

  Future<void> _publishOnly() async {
    final ok = await confirmAction(
      context,
      title: tr('Publish official results?'),
      body: tr('Publishes the results RunLah measured (GPS, camera and manual passes) as official. Runners get a push and their Race Insights turn official.'),
      confirm: tr('Publish'),
      color: RL.green,
      icon: Icons.verified_rounded,
      confirmKey: const Key('confirm-publish'),
    );
    if (ok && mounted) context.read<RaceSim>().publishOfficial();
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(_csv), mimeType: 'text/csv', name: _csvName)],
        fileNameOverrides: const [_csvName],
        subject: tr('Official timing · {event}', {'event': context.read<RaceSim>().event.name}),
        sharePositionOrigin: origin,
      ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Sharing isn\'t available on this device.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sim = context.watch<RaceSim>();
    return OrgTabList(
      children: [
        _StatusCard(sim: sim),
        _importCard(context, sim),
        _publishCard(context, sim),
        if (sim.status == RaceStatus.closed) const _Podium(),
      ],
    );
  }

  Widget _importCard(BuildContext context, RaceSim sim) {
    final preview = _lines.take(6).map((l) => l.split(',')).toList();
    final kb = (_csv.length / 1024).round();
    final already = sim.official && _state != _Import.done;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Import official timing'), trailing: const Pill('F27', color: RL.slate)),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: RL.green.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.table_chart_rounded, color: RL.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_csvName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                    Text(tr('{rows} rows · {kb} KB · from the timing company', {'rows': fmtInt(_rows), 'kb': fmtInt(kb)}), maxLines: 2, style: TextStyle(fontSize: 12, color: muted(context))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PreviewTable(rows: preview),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: switch (_state) {
              _Import.ready => FilledButton.icon(
                  key: const Key('import-csv'),
                  onPressed: already ? null : _import,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(already ? tr('Results already published') : tr('Import {n} rows', {'n': fmtInt(_rows)}), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              _Import.running => AnimatedBuilder(
                  key: const ValueKey('running'),
                  animation: _progress,
                  builder: (context, _) {
                    final v = Curves.easeInOutCubic.transform(_progress.value);
                    final phase = v < 0.35 ? tr('Validating rows…') : (v < 0.75 ? tr('Matching bibs to the start list…') : tr('Writing passes (source: import)…'));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(phase, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)))),
                            Text(
                              '${fmtInt((v * _rows).round())} / ${fmtInt(_rows)}',
                              style: TextStyle(fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: v, minHeight: 10, color: RL.green, backgroundColor: RL.green.withValues(alpha: 0.15)),
                        ),
                      ],
                    );
                  },
                ),
              _Import.done => Container(
                  key: const ValueKey('done'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: RL.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const DrawnCheck(size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('{n} rows imported · 0 errors', {'n': fmtInt(_rows)}), style: const TextStyle(fontWeight: FontWeight.w900, color: RL.green)),
                            Text(tr('Imported times win over GPS, camera and manual passes. Results are now official.'), style: TextStyle(fontSize: 12.5, color: ink(context))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }

  Widget _publishCard(BuildContext context, RaceSim sim) {
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Publish & share'), trailing: const Pill('F33', color: RL.slate)),
          Text(
            tr('No timing company? Publish what RunLah measured. Either way, e-certificates and official Race Insights go out to every finisher.'),
            style: TextStyle(color: muted(context), fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('publish-official'),
            onPressed: sim.official || _state == _Import.running ? null : _publishOnly,
            icon: const Icon(Icons.verified_rounded),
            label: Text(sim.official ? tr('Official results published') : tr('Publish without import'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (context) => OutlinedButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(tr('Share / download CSV'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.sim});
  final RaceSim sim;

  @override
  Widget build(BuildContext context) {
    final official = sim.official;
    final closed = sim.status == RaceStatus.closed;
    final color = official ? RL.green : (closed ? RL.amber : RL.slate);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(RL.radius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(official ? Icons.verified_rounded : Icons.hourglass_top_rounded, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill(official ? tr('Official') : tr('Provisional'), color: color, filled: true),
                const SizedBox(height: 6),
                Text(
                  official
                      ? (sim.timingImported ? tr('Published from the imported timing CSV') : tr('Published from RunLah\'s own timing'))
                      : closed
                          ? tr('Race closed. Review, then import or publish.')
                          : tr('Results update live while the race runs.'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.rows});
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    const cols = [0, 1, 2, 3, 6];
    final dark = Theme.of(context).brightness == Brightness.dark;
    String cell(List<String> r, int c, bool header) {
      if (c >= r.length) return '';
      var v = r[c].replaceAll('"', '');
      if (!header && c == 6) v = fmtDuration(double.tryParse(v));
      return v;
    }

    return Container(
      decoration: BoxDecoration(color: dark ? const Color(0xFF0B1220) : RL.bg, borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(10),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var i = 0; i < rows.length; i++)
              TableRow(
                children: [
                  for (final c in cols)
                    Padding(
                      padding: const EdgeInsets.only(right: 14, bottom: 4),
                      child: Text(
                        cell(rows[i], c, i == 0),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: i == 0 ? FontWeight.w900 : FontWeight.w600,
                          color: i == 0 ? muted(context) : ink(context),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium();

  @override
  Widget build(BuildContext context) {
    final snap = context.watch<InsightsController>().snapshot;
    final sim = context.read<RaceSim>();
    final men = snap.ranking(gender: Gender.m).take(3).toList();
    final women = snap.ranking(gender: Gender.f).take(3).toList();
    if (men.isEmpty && women.isEmpty) return const SizedBox.shrink();
    Widget column(String title, List<int> ids, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
              const SizedBox(height: 6),
              for (var i = 0; i < ids.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: [const Color(0xFFD4A017), const Color(0xFF9CA3AF), const Color(0xFFB87333)][i])),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sim.participant(ids[i]).displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: ink(context))),
                            Text(fmtDuration(snap.result(ids[i]).netS), style: TextStyle(fontSize: 12, color: muted(context), fontFeatures: const [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Podium · net time'), trailing: Text(tr('{n} finishers', {'n': fmtInt(snap.finishers)}), style: TextStyle(fontSize: 12, color: muted(context)))),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(tr('Men'), men, RL.male),
              const SizedBox(width: 12),
              column(tr('Women'), women, RL.female),
            ],
          ),
        ],
      ),
    );
  }
}
