import 'package:flutter/material.dart';

/// RunLah brand colours. Same palette as the PRD diagrams.
class RL {
  static const navy = Color(0xFF14213D);
  static const navySoft = Color(0xFF243458);
  static const amber = Color(0xFFE8930C);
  static const amberSoft = Color(0xFFFFF3DC);
  static const slate = Color(0xFF5B6577);
  static const line = Color(0xFFE1E5EC);
  static const bg = Color(0xFFF3F5F9);
  static const green = Color(0xFF2FA866);
  static const teal = Color(0xFF2A9DB5);
  static const red = Color(0xFFD64545);
  static const changed = Color(0xFF4A6FA5);

  /// Series colours for charts and map dots (you, friend 1, friend 2, ...).
  static const series = [amber, Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF14B8A6)];

  /// Female / male colours used in Who's who and drone view.
  static const female = Color(0xFF2FBF71);
  static const male = Color(0xFF2E5C8A);

  static const radius = 18.0;
  static const gap = 12.0;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: RL.navy,
    brightness: brightness,
    primary: dark ? const Color(0xFF9DB4E8) : RL.navy,
    secondary: RL.amber,
    surface: dark ? const Color(0xFF111827) : Colors.white,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0B1220) : RL.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0B1220) : RL.bg,
      foregroundColor: dark ? Colors.white : RL.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: dark ? Colors.white : RL.navy),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF111827) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RL.radius),
        side: BorderSide(color: dark ? const Color(0xFF1F2937) : RL.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RL.amber,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: dark ? Colors.white : RL.navy,
        side: BorderSide(color: dark ? const Color(0xFF374151) : RL.line, width: 1.5),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: dark ? const Color(0xFF374151) : RL.line),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF111827) : Colors.white,
      indicatorColor: RL.amber.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600),
      ),
    ),
    dividerTheme: DividerThemeData(color: dark ? const Color(0xFF1F2937) : RL.line, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF111827) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: RL.line)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? const Color(0xFF374151) : RL.line),
      ),
    ),
  );
}

/// Small uppercase label used as a card heading ("YOUR PLACE").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : RL.slate,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Rounded white card with standard padding.
class RLCard extends StatelessWidget {
  const RLCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    return card;
  }
}

/// Pill badge: NEW, LIVE, PROVISIONAL, OFFICIAL...
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = RL.amber, this.filled = false, this.icon});
  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: filled ? Colors.white : color), const SizedBox(width: 4)],
          Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: filled ? Colors.white : color),
          ),
        ],
      ),
    );
  }
}

/// Big number with a caption underneath ("4:34" / "avg /km").
class StatBlock extends StatelessWidget {
  const StatBlock({super.key, required this.value, required this.label, this.size = 28, this.color, this.align = CrossAxisAlignment.center});
  final String value;
  final String label;
  final double size;
  final Color? color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            height: 1.05,
            color: color ?? (dark ? Colors.white : RL.navy),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 12, color: dark ? Colors.white60 : RL.slate)),
      ],
    );
  }
}

/// Colour for text that should read as "navy" in light mode and white in dark.
Color ink(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white : RL.navy;
Color muted(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? Colors.white60 : RL.slate;
