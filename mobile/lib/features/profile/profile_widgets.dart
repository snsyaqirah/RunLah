import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';

/// "Arep" -> "A", "Nur Syaqirah" -> "NS".
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
}

/// Round avatar with initials inside a gradient ring.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.size = 76});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.045),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [RL.amber, Color(0xFFEC4899), RL.teal, RL.amber]),
      ),
      child: Container(
        padding: EdgeInsets.all(size * 0.035),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: RL.navy),
        child: Container(
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2B3F6B), RL.navySoft]),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                initialsOf(name),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.36, letterSpacing: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Number that counts up from 0 the first time it's shown (and whenever
/// [active] turns true).
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 1100),
    this.active = true,
    this.textAlign,
  });
  final double value;
  final String Function(double v) format;
  final TextStyle? style;
  final Duration duration;
  final bool active;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? value : 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(format(v), style: style, textAlign: textAlign),
    );
  }
}

/// Fade + slide-up entrance. [index] staggers siblings; turning [active]
/// on (again) replays it.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.active = true, this.offset = 0.12});
  final Widget child;
  final int index;
  final bool active;
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _base = 420, _step = 70;
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: _base + _step * widget.index.clamp(0, 12)));
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(_step * widget.index.clamp(0, 12) / (_base + _step * widget.index.clamp(0, 12)), 1, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.forward();
  }

  @override
  void didUpdateWidget(covariant Reveal old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: Offset(0, widget.offset), end: Offset.zero).animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// Small RunLah wordmark for share cards and frames.
class RunLahMark extends StatelessWidget {
  const RunLahMark({super.key, this.color = Colors.white, this.size = 16, this.showText = true});
  final Color color;
  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 1.35,
          height: size * 1.35,
          decoration: const BoxDecoration(color: RL.amber, shape: BoxShape.circle),
          child: Icon(Icons.directions_run_rounded, size: size, color: Colors.white),
        ),
        if (showText) ...[
          SizedBox(width: size * 0.35),
          Text('RunLah', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: size, letterSpacing: -0.2)),
        ],
      ],
    );
  }
}

/// Passport stamp: dashed double ring with a label in the middle.
class StampPainter extends CustomPainter {
  StampPainter({required this.color, this.dashes = 28});
  final Color color;
  final int dashes;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1.5;
    final dashed = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * sweep, sweep * 0.55, false, dashed);
    }
    canvas.drawCircle(
      c,
      r - 5,
      Paint()
        ..color = color.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(c, r - 6, Paint()..color = color.withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(StampPainter old) => old.color != color || old.dashes != dashes;
}

/// Thin rounded progress bar.
class SlimProgress extends StatelessWidget {
  const SlimProgress({super.key, required this.value, this.color = RL.amber, this.height = 5});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: dark ? Colors.white12 : RL.line),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- sharing

/// Render the [RepaintBoundary] behind [key] to PNG bytes.
Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 3}) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) return null;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void showProfileSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

/// Capture [key] and open the share sheet with the PNG (download on web).
/// Never throws: failures end in a snackbar.
Future<void> shareBoundary(BuildContext context, GlobalKey key, {required String fileName, String? text}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final bytes = await capturePng(key);
    if (bytes == null) throw StateError('nothing to capture');
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
      text: text,
    ));
  } catch (_) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Sharing isn\'t available here. Try a screenshot instead.')), behavior: SnackBarBehavior.floating));
  }
}

/// Share a text file (e.g. a JSON export). Returns false if sharing failed.
Future<bool> shareTextFile(String content, {required String fileName, required String mimeType}) async {
  try {
    final bytes = Uint8List.fromList(utf8.encode(content));
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      fileNameOverrides: [fileName],
    ));
    return true;
  } catch (_) {
    return false;
  }
}

/// Share a short text or link. Falls back to copying it.
Future<void> shareTextOrCopy(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SharePlus.instance.share(ShareParams(text: text));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Copied to clipboard')), behavior: SnackBarBehavior.floating));
  }
}
