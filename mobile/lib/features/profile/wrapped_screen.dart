import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/achievements.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'passport.dart';
import 'profile_widgets.dart';

/// Race Wrapped: the year in running as swipeable, auto-advancing stories
/// (tap right = next, tap left = back, hold = pause). The last page is a
/// shareable card.
class RaceWrappedScreen extends StatefulWidget {
  const RaceWrappedScreen({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => const RaceWrappedScreen(),
        transitionsBuilder: (_, a, _, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: c,
            child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(c), child: child),
          );
        },
      );

  @override
  State<RaceWrappedScreen> createState() => _RaceWrappedScreenState();
}

class _Page {
  const _Page(this.colors, this.build);
  final List<Color> colors;
  final Widget Function(bool active) build;
}

class _RaceWrappedScreenState extends State<RaceWrappedScreen> with SingleTickerProviderStateMixin {
  static const _pageDuration = Duration(seconds: 7);
  final _pages = PageController();
  final _shareKey = GlobalKey();
  late final AnimationController _timer = AnimationController(vsync: this, duration: _pageDuration)..addStatusListener(_onTimer);
  int _index = 0;
  int _count = 1;

  @override
  void initState() {
    super.initState();
    _timer.forward();
  }

  @override
  void dispose() {
    _timer.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onTimer(AnimationStatus s) {
    if (s == AnimationStatus.completed && _index < _count - 1) _next();
  }

  void _go(int i) {
    if (i < 0 || i >= _count || !_pages.hasClients) return;
    _pages.animateToPage(i, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  void _next() => _go(_index + 1);
  void _prev() => _go(_index - 1);

  void _onPage(int i) {
    setState(() => _index = i);
    _timer.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final sim = context.read<RaceSim>();
    final snap = context.watch<InsightsController>().snapshot;
    final ach = context.watch<Achievements>();
    final view = ach.view(snap, targetTimeS: settings.targetTimeS);
    final pages = _buildPages(context, view.wrapped, settings, sim);
    _count = pages.length;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) {
              final w = MediaQuery.sizeOf(context).width;
              d.localPosition.dx < w * 0.3 ? _prev() : _next();
            },
            onLongPressStart: (_) => _timer.stop(),
            onLongPressEnd: (_) {
              if (_index < _count - 1 || _timer.value < 1) _timer.forward();
            },
            child: PageView.builder(
              controller: _pages,
              itemCount: pages.length,
              onPageChanged: _onPage,
              itemBuilder: (_, i) => _StoryBackground(colors: pages[i].colors, child: pages[i].build(i == _index)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _timer,
                    builder: (_, _) => Row(
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          Expanded(
                            child: Container(
                              height: 3.5,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: i < _index ? 1 : (i == _index ? _timer.value : 0),
                                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  minHeight: 3.5,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const RunLahMark(size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('Race Wrapped {year}', {'year': view.year}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Close'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_Page> _buildPages(BuildContext context, WrappedStats w, SettingsController settings, RaceSim sim) {
    final units = settings.units;
    final name = settings.displayName;
    final race = sim.race;
    final eventName = sim.event.name;
    return [
      // 1. Intro
      _Page(const [Color(0xFF1B1446), Color(0xFF3B1F6E)], (active) {
        return _StoryColumn(
          active: active,
          children: [
            _Kicker(tr('Race Wrapped')),
            Hero(
              tag: 'wrapped-year',
              child: Material(
                type: MaterialType.transparency,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${w.year}', style: const TextStyle(color: Colors.white, fontSize: 112, fontWeight: FontWeight.w900, height: 1, letterSpacing: -4)),
                ),
              ),
            ),
            _Big(tr('Hey {name}, here\'s your year on the road.', {'name': name}), size: 26),
            if (!w.currentFinished) _Body(tr('{race} is still to come: finish it and your Wrapped fills in.', {'race': eventName})),
            const SizedBox(height: 20),
            _Body(tr('Tap to continue →'), alpha: 0.6),
          ],
        );
      }),

      // 2. Races + km
      _Page(const [Color(0xFFE8930C), Color(0xFFC2410C)], (active) {
        return _StoryColumn(
          active: active,
          children: [
            _Kicker(tr('This year you raced')),
            _Row2(
              _CountBig(value: w.races.length.toDouble(), active: active, format: (v) => '${v.round()}'),
              w.races.length == 1 ? tr('race') : tr('races'),
            ),
            _Row2(
              _CountBig(value: w.kmRacedM, active: active, format: (v) => fmtDistance(v, units, withUnit: false), size: 64),
              tr('{unit} on race day', {'unit': distUnit(units)}),
            ),
            const SizedBox(height: 8),
            for (final e in w.races)
              _GlassRow(
                leading: distanceLabel(e.distanceM),
                title: e.name,
                trailing: fmtDuration(e.netS),
              ),
            if (w.freeRunCount > 0)
              _Body(tr('+ {km} of free runs ({n} runs)', {'km': fmtDistance(w.freeRunM, units), 'n': w.freeRunCount})),
          ],
        );
      }),

      // 3. Best result
      if (w.best != null)
        _Page(const [Color(0xFF0F766E), Color(0xFF14213D)], (active) {
          final b = w.best!;
          return _StoryColumn(
            active: active,
            children: [
              _Kicker(tr('Your best result')),
              _CountBig(value: b.netS!, active: active, format: (v) => fmtDuration(v), size: 80),
              _Big(b.name, size: 22),
              if (b.place != null)
                _Body(tr('{place} of {n} · Top {pct}', {'place': ordinal(b.place!), 'n': fmtInt(b.of!), 'pct': fmtPct(b.topPct!)})),
              if (w.newPb != null && w.newPb!.entry?.id == b.id) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Pill(
                    tr('New PB · {gap} faster', {'gap': fmtDuration(w.newPb!.improvementS)}),
                    filled: true,
                    icon: Icons.bolt_rounded,
                  ),
                ),
              ],
            ],
          );
        }),

      // 4. Overtakes
      _Page(const [Color(0xFFBE185D), Color(0xFF581C87)], (active) {
        if (w.runnersPassed == null) {
          return _StoryColumn(
            active: active,
            children: [
              _Kicker(tr('Overtakes')),
              const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 72),
              _Big(tr('Unlocks on race day'), size: 34),
              _Body(tr('Finish {race} to see how many runners you passed.', {'race': eventName})),
            ],
          );
        }
        return _StoryColumn(
          active: active,
          children: [
            _Kicker(tr('You overtook')),
            _Row2(_CountBig(value: w.runnersPassed!.toDouble(), active: active, format: (v) => fmtInt(v.round())), tr('runners')),
            if (w.passedBeforeHalf != null) _Body(tr('{n} of them before halfway.', {'n': fmtInt(w.passedBeforeHalf!)})),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: AnimatedBuilder(
                animation: _timer,
                builder: (_, _) => CustomPaint(painter: _PassingPainter(active ? _timer.value : 0), size: Size.infinite),
              ),
            ),
          ],
        );
      }),

      // 5. Fastest quarter
      if (w.quarters.length == 4 && w.fastestQuarter != null)
        _Page(const [Color(0xFF15803D), Color(0xFF14532D)], (active) {
          final q = w.quarters[w.fastestQuarter!];
          final from = race.checkpoints[q.fromIndex].name, to = race.checkpoints[q.toIndex].name;
          return _StoryColumn(
            active: active,
            children: [
              _Kicker(tr('Your fastest quarter')),
              _Big('Q${w.fastestQuarter! + 1}', size: 104),
              _Big('${fmtSpeed(q.speedKph, units)} · ${fmtPace(q.paceSPerKm, units)}', size: 24),
              _Body(tr('{from} → {to}', {'from': from, 'to': to})),
              const SizedBox(height: 18),
              _QuarterBars(quarters: w.quarters, fastest: w.fastestQuarter!, active: active, units: units),
            ],
          );
        }),

      // 6. Cheers
      _Page(const [Color(0xFFDB2777), Color(0xFFF59E0B)], (active) {
        if (w.cheerFriend == null) {
          return _StoryColumn(
            active: active,
            children: [
              _Kicker(tr('Your crew')),
              const Icon(Icons.groups_rounded, color: Colors.white, size: 72),
              _Big(w.crew.join(' & '), size: 40),
              _Body(tr('They follow you live. Share your QR code so more friends can cheer you on race day.')),
            ],
          );
        }
        return _StoryColumn(
          active: active,
          children: [
            _Kicker(tr('Your #1 cheerleader')),
            _Big(w.cheerFriend!, size: 64),
            _Body(w.cheerCount == 1 ? tr('1 cheer on race day') : tr('{n} cheers on race day', {'n': w.cheerCount})),
            if (w.cheerQuote != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomRight: Radius.circular(20), bottomLeft: Radius.circular(4)),
                ),
                child: Text('“${w.cheerQuote}”', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1.3)),
              ),
            ],
            if (w.totalCheers > w.cheerCount)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _Body(tr('{n} cheers in total from your crew', {'n': w.totalCheers}), alpha: 0.8),
              ),
          ],
        );
      }),

      // 7. Share
      _Page(const [Color(0xFF14213D), Color(0xFF0B1220)], (active) {
        return _StoryColumn(
          active: active,
          children: [
            _Kicker(tr('That\'s a wrap!')),
            const SizedBox(height: 6),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: _shareKey,
                  child: _WrappedCard(w: w, name: name, units: units),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => shareBoundary(
                context,
                _shareKey,
                fileName: 'runlah-wrapped-${w.year}.png',
                text: tr('My Race Wrapped {year} on RunLah', {'year': w.year}),
              ),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(tr('Share my Wrapped')),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => _go(0),
              icon: const Icon(Icons.replay_rounded),
              label: Text(tr('Watch again')),
            ),
          ],
        );
      }),
    ];
  }
}

// ------------------------------------------------------------ story parts

class _StoryBackground extends StatelessWidget {
  const _StoryBackground({required this.colors, required this.child});
  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)),
      child: Stack(
        children: [
          Positioned(right: -80, top: 120, child: _Blob(size: 260, color: Colors.white.withValues(alpha: 0.06))),
          Positioned(left: -60, bottom: 60, child: _Blob(size: 200, color: Colors.black.withValues(alpha: 0.08))),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Vertically centred, scrollable when tall; children reveal one by one.
class _StoryColumn extends StatelessWidget {
  const _StoryColumn({required this.active, required this.children});
  final bool active;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, c.maxHeight - 104)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Reveal(index: i, active: active, offset: 0.3, child: children[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13),
      );
}

class _Big extends StatelessWidget {
  const _Big(this.text, {this.size = 40});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w900, height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.alpha = 0.88});
  final String text;
  final double alpha;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Colors.white.withValues(alpha: alpha), fontSize: 16, height: 1.35, fontWeight: FontWeight.w600));
}

class _CountBig extends StatelessWidget {
  const _CountBig({required this.value, required this.active, required this.format, this.size = 96});
  final double value;
  final bool active;
  final String Function(double) format;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: CountUp(
        value: value,
        active: active,
        format: format,
        duration: const Duration(milliseconds: 1500),
        style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w900, height: 1, letterSpacing: -2, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// Big number with a word after it ("2 races"), wrapping if needed.
class _Row2 extends StatelessWidget {
  const _Row2(this.number, this.word);
  final Widget number;
  final String word;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      children: [
        number,
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(word, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _GlassRow extends StatelessWidget {
  const _GlassRow({required this.leading, required this.title, required this.trailing});
  final String leading;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Text(leading, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            Text(trailing, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}

class _QuarterBars extends StatelessWidget {
  const _QuarterBars({required this.quarters, required this.fastest, required this.active, required this.units});
  final List<SectionResult> quarters;
  final int fastest;
  final bool active;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final speeds = [for (final q in quarters) q.speedKph];
    final lo = speeds.reduce(math.min) * 0.9, hi = speeds.reduce(math.max);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutBack,
      builder: (_, t, _) => SizedBox(
        height: 190,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < quarters.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(fmtSpeed(speeds[i], units, withUnit: false), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: math.max(4, 120 * ((speeds[i] - lo) / (hi - lo)).clamp(0.05, 1.0) * t),
                        decoration: BoxDecoration(
                          color: i == fastest ? RL.amber : Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Q${i + 1}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The field streaming backwards past you (the amber dot) as you overtake.
class _PassingPainter extends CustomPainter {
  _PassingPainter(this.t);
  final double t;

  static final List<(double, int, double)> _dots = () {
    final r = math.Random(34144);
    return [for (var i = 0; i < 110; i++) (r.nextDouble() * 1.7, r.nextInt(7), 0.75 + r.nextDouble() * 0.5)];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    const lanes = 7;
    final laneH = size.height / lanes;
    final youX = size.width * 0.32;
    for (final (x0, lane, k) in _dots) {
      final x = (x0 - t * 1.25 * k) * size.width + youX;
      if (x < -6 || x > size.width + 6) continue;
      final y = laneH * (lane + 0.5);
      final passed = x < youX;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.white.withValues(alpha: passed ? 0.28 : 0.85));
    }
    final you = Offset(youX, laneH * 3.5);
    canvas.drawCircle(you, 16, Paint()..color = RL.amber.withValues(alpha: 0.25));
    canvas.drawCircle(you, 8, Paint()..color = RL.amber);
    canvas.drawCircle(
      you,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PassingPainter old) => old.t != t;
}

/// The shareable summary card (fixed size so the PNG looks the same everywhere).
class _WrappedCard extends StatelessWidget {
  const _WrappedCard({required this.w, required this.name, required this.units});
  final WrappedStats w;
  final String name;
  final Units units;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
                ),
                const SizedBox(height: 2),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
              ],
            ),
          ),
        );
    final q = w.fastestQuarter == null ? null : w.quarters[w.fastestQuarter!];
    return Container(
      width: 320,
      height: 430,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B1F6E), Color(0xFF7A2E8F), RL.amber], stops: [0, 0.65, 1]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RunLahMark(size: 15),
          const SizedBox(height: 14),
          Text(tr('RACE WRAPPED'), style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 11)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${w.year}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 56, height: 1, letterSpacing: -2)),
          ),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          const Spacer(),
          Row(
            children: [
              stat('${w.races.length}', tr('Races')),
              stat(fmtDistance(w.kmRacedM, units), tr('Raced')),
            ],
          ),
          Row(
            children: [
              stat(w.best == null ? '–' : fmtDuration(w.best!.netS), tr('Best result')),
              stat(w.runnersPassed == null ? '–' : fmtInt(w.runnersPassed!), tr('Runners passed')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            q == null ? '#RunLah' : '${tr('Fastest quarter')}: Q${w.fastestQuarter! + 1} · ${fmtSpeed(q.speedKph, units)}  #RunLah',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
