import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../data/app_state.dart';
import '../../../data/sim/race_sim.dart';
import '../event_detail_screen.dart';
import '../home_data.dart';

/// Deep link printed as a QR on the bib: kit check-in and Cheer scan-to-follow.
String followLink(String bib) => 'runlah://follow/$bib';

/// "Your bib" — looks like the paper bib: number, name, category, corral
/// and the QR code. Stays white in dark mode, like the real thing.
class BibCard extends StatelessWidget {
  const BibCard({super.key});

  static const _ink = RL.navy;
  static const _muted = RL.slate;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final you = sim.you;
    final claims = BibClaims.of(context.read<SettingsController>().prefs);
    final category = sim.race.categoryById(you.categoryId).name;
    final corral = corralFor(sim, you.id);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(RL.radius),
        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.transparent : RL.line),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Sponsor-style strip across the top of the bib.
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [RL.amber, Color(0xFFF2B33D)])),
            child: Row(
              children: [
                const Icon(Icons.directions_run_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sim.event.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 58,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            you.bib,
                            style: const TextStyle(fontSize: 56, height: 1, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                      ),
                      Text(
                        you.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _Tag(tr(sim.race.name)),
                          _Tag(category),
                          _Tag(tr('Corral {c}', {'c': corral}), strong: true),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showBigQr(context, you.bib, you.name),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(border: Border.all(color: RL.line), borderRadius: BorderRadius.circular(10)),
                        child: QrImageView(
                          data: followLink(you.bib),
                          size: 92,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
                          semanticsLabel: tr('QR code for bib {bib}', {'bib': you.bib}),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 100,
                        child: Text(
                          tr('Tap to enlarge'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: _muted, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RL.line),
          ListenableBuilder(
            listenable: claims,
            builder: (context, _) {
              final linked = claims.isClaimed(you.bib);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(linked ? Icons.verified_rounded : Icons.link_rounded, size: 18, color: linked ? RL.green : RL.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        linked ? tr('Linked to your account · kit check-in ready') : tr('Link this bib with your verification code'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: linked ? RL.green : _ink),
                      ),
                    ),
                    if (!linked)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventDetailScreen(focusJoin: true))),
                        style: TextButton.styleFrom(foregroundColor: RL.amber, textStyle: const TextStyle(fontWeight: FontWeight.w800)),
                        child: Text(tr('Link bib')),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static void _showBigQr(BuildContext context, String bib, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(bib, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _ink, fontFeatures: [FontFeature.tabularFigures()])),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _muted)),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (_, c) {
                  final size = c.maxWidth.clamp(120.0, 240.0);
                  return QrImageView(
                    data: followLink(bib),
                    size: size,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                tr('Show this at kit collection. Friends can scan it in Cheer to follow you live.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 6),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: strong ? RL.navy : RL.bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: strong ? Colors.white : RL.navy)),
      );
}
