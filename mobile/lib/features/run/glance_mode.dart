import 'package:flutter/material.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';

/// One number in glance mode.
class GlanceMetric {
  const GlanceMetric(this.value, this.label, {this.color = Colors.white});
  final String value;
  final String label;
  final Color color;
}

/// Full-screen, high-contrast numbers you can read mid-stride. Tap anywhere
/// to go back. [listenable] drives rebuilds (the race clock, or the tracker).
class GlanceModeScreen extends StatelessWidget {
  const GlanceModeScreen({super.key, required this.listenable, required this.hero, required this.metrics, this.footer});
  final Listenable listenable;
  final GlanceMetric Function() hero;
  final List<GlanceMetric> Function() metrics;
  final String Function()? footer;

  static Future<void> open(BuildContext context, {required Listenable listenable, required GlanceMetric Function() hero, required List<GlanceMetric> Function() metrics, String Function()? footer}) =>
      Navigator.of(context).push(PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => GlanceModeScreen(listenable: listenable, hero: hero, metrics: metrics, footer: footer),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(a), child: child)),
      ));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: ListenableBuilder(
              listenable: listenable,
              builder: (context, _) {
                final h = hero();
                final m = metrics();
                final f = footer?.call();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.visibility_rounded, color: RL.amber, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr('Glance mode'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800))),
                        Text(tr('Tap to exit'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                    Expanded(flex: 5, child: _Big(metric: h, scale: 1)),
                    const Divider(color: Colors.white12),
                    for (var i = 0; i < m.length; i += 2)
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Expanded(child: _Big(metric: m[i], scale: 0.55)),
                            if (i + 1 < m.length) ...[
                              Container(width: 1, color: Colors.white12, margin: const EdgeInsets.symmetric(vertical: 16)),
                              Expanded(child: _Big(metric: m[i + 1], scale: 0.55)),
                            ],
                          ],
                        ),
                      ),
                    if (f != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(f, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.metric, required this.scale});
  final GlanceMetric metric;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              metric.value,
              maxLines: 1,
              style: TextStyle(
                color: metric.color,
                fontSize: 120 * scale,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: -2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(metric.label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontSize: 12)),
      ],
    );
  }
}
