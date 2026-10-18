import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/notification_center.dart';
import 'cheer_widgets.dart';
import 'runner_detail_screen.dart';

/// Bell with unread badge; opens the notification feed.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationCenter, int>((n) => n.unread);
    return IconButton(
      tooltip: tr('Notifications'),
      onPressed: () => showNotificationsSheet(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: RL.red,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}

/// The in-app notification feed. Everything is marked read on close.
Future<void> showNotificationsSheet(BuildContext context) async {
  final center = context.read<NotificationCenter>();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _FeedSheet(),
  );
  if (center.unread > 0) center.markAllRead();
}

class _FeedSheet extends StatelessWidget {
  const _FeedSheet();

  @override
  Widget build(BuildContext context) {
    final center = context.watch<NotificationCenter>();
    final feed = center.feed;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('Notifications'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context))),
                ),
                TextButton.icon(
                  onPressed: center.unread == 0 ? null : center.markAllRead,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(tr('Mark all read')),
                ),
              ],
            ),
          ),
          if (feed.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                children: [
                  Icon(Icons.notifications_none_rounded, size: 44, color: muted(context)),
                  const SizedBox(height: 8),
                  Text(
                    tr('Nothing yet. Checkpoint passes, finishes and cheers show up here.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted(context)),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: feed.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) => Appear(index: i, child: _NoticeTile(notice: feed[i])),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notice});
  final AppNotice notice;

  void _open(BuildContext context) {
    final nav = Navigator.of(context);
    final follows = context.read<FollowsController>();
    final pid = notice.participantId;
    nav.pop();
    switch (notice.kind) {
      case NoticeKind.finish || NoticeKind.results:
        openInsights(nav.context, pid ?? follows.sim.youId);
      case NoticeKind.checkpoint || NoticeKind.cheer:
        if (pid != null) nav.push(MaterialPageRoute(builder: (_) => RunnerDetailScreen(participantId: pid)));
      case NoticeKind.sos:
        openOrganizer(nav.context);
      case NoticeKind.race:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = notice;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: n.read ? Colors.transparent : RL.amber.withValues(alpha: dark ? 0.1 : 0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: n.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                child: Icon(n.icon, color: n.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                        ),
                        const SizedBox(width: 6),
                        Text(fmtClock(n.at), style: TextStyle(fontSize: 11.5, color: muted(context))),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context))),
                  ],
                ),
              ),
              if (!n.read) ...[
                const SizedBox(width: 6),
                Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: RL.amber, shape: BoxShape.circle)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
