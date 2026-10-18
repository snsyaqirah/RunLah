import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/achievements.dart';
import '../../data/app_state.dart';
import '../../data/sim/race_sim.dart';
import 'profile_widgets.dart';

/// "My QR code": friends scan it to follow you live (`runlah://follow/{bib}`).
Future<void> showMyQrSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _QrSheet(),
    );

class _QrSheet extends StatefulWidget {
  const _QrSheet();

  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  final _card = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final ach = context.read<Achievements>();
    final you = context.read<RaceSim>().you;
    final link = ach.followLink;
    final shareText = tr('Follow me live on RunLah: {link}', {'link': link});
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('My QR code'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink(context))),
            Text(tr('Friends scan this in the Cheer tab to follow you live.'), style: TextStyle(color: muted(context), fontSize: 13)),
            const SizedBox(height: 16),
            Center(
              child: RepaintBoundary(
                key: _card,
                child: Container(
                  width: 280,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: RL.line),
                    boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const RunLahMark(color: RL.navy, size: 15),
                      const SizedBox(height: 12),
                      QrImageView(
                        data: link,
                        size: 200,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: RL.navy),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: RL.navy),
                        semanticsLabel: tr('QR code to follow {name}', {'name': settings.displayName}),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        settings.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: RL.navy),
                      ),
                      Text(
                        tr('Bib {bib}', {'bib': you.bib}),
                        style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 6),
                      Text(tr('Scan to follow me live'), textAlign: TextAlign.center, style: const TextStyle(color: RL.slate, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: SelectableText(link, style: TextStyle(color: muted(context), fontSize: 12.5, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (context.mounted) showProfileSnack(context, tr('Link copied'));
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: Text(tr('Copy link'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => shareBoundary(context, _card, fileName: 'runlah-follow-${you.bib}.png', text: shareText),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(tr('Share'), maxLines: 1, overflow: TextOverflow.ellipsis),
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
