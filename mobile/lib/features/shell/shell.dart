import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/notification_center.dart';
import '../cheer/cheer_screen.dart';
import '../home/home_screen.dart';
import '../insights/results_screen.dart';
import '../profile/profile_screen.dart';
import '../run/run_screen.dart';
import 'demo_director.dart';

/// Bottom-nav shell: Home · Run · Cheer · Results · Me, plus the in-app
/// notification banner and the demo director overlay.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  StreamSubscription<AppNotice>? _sub;
  AppNotice? _banner;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _sub = context.read<NotificationCenter>().banners.listen((n) {
      _hide?.cancel();
      setState(() => _banner = n);
      _hide = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _banner = null);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  void _openBanner(AppNotice n) {
    setState(() => _banner = null);
    switch (n.kind) {
      case NoticeKind.finish || NoticeKind.results:
        openInsights(context, n.participantId ?? context.read<FollowsController>().sim.youId);
      case NoticeKind.checkpoint:
        context.read<ShellController>().tab = AppTab.cheer;
      case NoticeKind.cheer:
        context.read<ShellController>().tab = AppTab.run;
      case NoticeKind.sos:
        openOrganizer(context);
      case NoticeKind.race:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final unread = context.select<NotificationCenter, int>((n) => n.unread);
    const screens = [HomeScreen(), RunScreen(), CheerScreen(), ResultsScreen(), ProfileScreen()];
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: shell.tab.index, children: screens),
          const DemoDirectorButton(),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            left: 12,
            right: 12,
            top: _banner == null ? -140 : MediaQuery.of(context).padding.top + 8,
            child: _banner == null ? const SizedBox.shrink() : _Banner(notice: _banner!, onTap: () => _openBanner(_banner!)),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.tab.index,
        onDestinationSelected: (i) => shell.tab = AppTab.values[i],
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr('Home')),
          NavigationDestination(icon: const Icon(Icons.directions_run_outlined), selectedIcon: const Icon(Icons.directions_run_rounded), label: tr('Run')),
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.campaign_outlined)),
            selectedIcon: const Icon(Icons.campaign_rounded),
            label: tr('Cheer'),
          ),
          NavigationDestination(icon: const Icon(Icons.emoji_events_outlined), selectedIcon: const Icon(Icons.emoji_events_rounded), label: tr('Results')),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: tr('Me')),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.notice, required this.onTap});
  final AppNotice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onTap,
        onVerticalDragEnd: (_) => onTap(),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: notice.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(notice.icon, color: notice.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(notice.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                    const SizedBox(height: 2),
                    Text(notice.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context))),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text('RunLah', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: RL.amber.withValues(alpha: 0.9))),
            ],
          ),
        ),
      ),
    );
  }
}
