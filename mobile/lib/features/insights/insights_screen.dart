import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'common.dart';
import 'compare_tab.dart';
import 'finish_tab.dart';
import 'speed_tab.dart';
import 'where_tab.dart';

/// Race Insights for one runner (PRD §6): Finish · Speed · Where · Compare.
/// Provisional while the race is live, Official once results are published.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key, required this.participantId, this.initialTab = 0});
  final int participantId;

  /// 0 Finish · 1 Speed · 2 Where · 3 Compare
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    context.watch<SettingsController>();
    final p = sim.participant(participantId);
    final isYou = p.id == sim.youId;
    final top = MediaQuery.paddingOf(context).top;
    return DefaultTabController(
      length: 4,
      initialIndex: initialTab.clamp(0, 3),
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, inner) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                pinned: true,
                expandedHeight: 200,
                forceElevated: inner,
                backgroundColor: RL.navy,
                foregroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                titleTextStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                title: Text(tr('Race Insights')),
                actions: [
                  IconButton(
                    tooltip: tr('Share card'),
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => openShareCard(context, participantId),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0E1830), RL.navy, Color(0xFF2A3D66)],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(16, top + kToolbarHeight + 2, 16, 52),
                    child: Row(
                      children: [
                        RunnerAvatar(name: nameOf(context, p), color: isYou ? RL.amber : RL.series[1], size: 54, icon: p.resultsName == ResultsName.bibOnly && !isYou ? Icons.person_rounded : null),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      nameOf(context, p),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  if (isYou) ...[const SizedBox(width: 6), Pill(tr('You'), color: RL.amber, filled: true)],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '#${p.bib} · ${categoryName(sim.race, p)} · ${nationName(p.nation)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${sim.event.name} · ${tr(sim.race.name)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              const ResultsStatusPill(filled: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                bottom: TabBar(
                  indicatorColor: RL.amber,
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white60,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  tabs: [
                    for (final t in [tr('Finish'), tr('Speed'), tr('Where'), tr('Compare')])
                      Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(t, maxLines: 1))),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              FinishTab(participantId: participantId),
              SpeedTab(participantId: participantId),
              WhereTab(participantId: participantId),
              CompareTab(participantId: participantId),
            ],
          ),
        ),
      ),
    );
  }
}
