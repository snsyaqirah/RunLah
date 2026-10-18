import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// Language, units, theme, privacy defaults, results name, battery saver,
/// voice coach, cheers read aloud and target time.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  // Changing the language rebuilds the whole app (new navigator). The Me
  // tab re-opens this screen at the same scroll position right after.
  static bool _reopen = false;
  static double _offset = 0;

  /// Called by the Me tab after a rebuild: should Settings re-open?
  static bool consumeReopen() {
    final r = _reopen;
    _reopen = false;
    return r;
  }

  static Route<void> route({bool instant = false}) => instant
      ? PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, _, _) => const SettingsScreen(),
          transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
        )
      : MaterialPageRoute<void>(builder: (_) => const SettingsScreen());

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(initialScrollOffset: SettingsScreen._offset);
    SettingsScreen._offset = 0;
  }

  @override
  void dispose() {
    // Never leave a stale "re-open" request behind.
    SettingsScreen._reopen = false;
    _scroll.dispose();
    super.dispose();
  }

  void _setLang(SettingsController s, String lang) {
    if (lang == s.lang) return;
    SettingsScreen._reopen = true;
    SettingsScreen._offset = _scroll.hasClients ? _scroll.offset : 0;
    s.lang = lang;
  }

  void _setResultsName(SettingsController s, ResultsName v) {
    s.resultsName = v;
    final sim = context.read<RaceSim>();
    sim.you.resultsName = v;
    // Nudge listeners (results lists, maps) so the new name shows at once.
    sim.setSpeed(sim.speed);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final sim = context.read<RaceSim>();
    final you = sim.you;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _Group(
            icon: Icons.translate_rounded,
            title: tr('Language'),
            child: _Choices<String>(
              value: s.lang,
              options: const [('en', 'English'), ('ms', 'Bahasa Malaysia')],
              onChanged: (v) => _setLang(s, v),
            ),
          ),
          _Group(
            icon: Icons.straighten_rounded,
            title: tr('Units'),
            child: _Choices<Units>(
              value: s.units,
              options: [(Units.km, tr('Kilometres')), (Units.mi, tr('Miles'))],
              onChanged: (v) => s.units = v,
            ),
          ),
          _Group(
            icon: Icons.dark_mode_outlined,
            title: tr('Theme'),
            child: _Choices<ThemeMode>(
              value: s.themeMode,
              options: [(ThemeMode.system, tr('System')), (ThemeMode.light, tr('Light')), (ThemeMode.dark, tr('Dark'))],
              onChanged: (v) => s.themeMode = v,
            ),
          ),
          _Group(
            icon: Icons.visibility_outlined,
            title: tr('Default privacy for live tracking'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Choices<Privacy>(
                  value: s.privacy,
                  options: [(Privacy.public, tr('Public')), (Privacy.linkOnly, tr('Link only')), (Privacy.off, tr('Off'))],
                  onChanged: (v) => s.privacy = v,
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _Note(
                    key: ValueKey(s.privacy),
                    text: switch (s.privacy) {
                      Privacy.public => tr('Anyone can find you and follow your live position.'),
                      Privacy.linkOnly => tr('Only people with your link or QR code can follow you live.'),
                      Privacy.off => tr('Nobody sees your live position. Checkpoint times still appear in results.'),
                    },
                  ),
                ),
              ],
            ),
          ),
          _Group(
            icon: Icons.badge_outlined,
            title: tr('Name in public results'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Choices<ResultsName>(
                  value: s.resultsName,
                  options: [(ResultsName.full, tr('Full name')), (ResultsName.bibOnly, tr('Bib only'))],
                  onChanged: (v) => _setResultsName(s, v),
                ),
                const SizedBox(height: 10),
                _Note(
                  text: tr('Others see you as: {name}', {
                    'name': s.resultsName == ResultsName.bibOnly ? tr('Runner {bib}', {'bib': you.bib}) : you.name,
                  }),
                ),
              ],
            ),
          ),
          _Group(
            icon: Icons.directions_run_rounded,
            title: tr('While running'),
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
            child: Column(
              children: [
                SwitchListTile(
                  value: s.batterySaver,
                  onChanged: (v) => s.batterySaver = v,
                  title: Text(tr('Battery saver')),
                  subtitle: Text(tr('GPS every {n} s instead of 5 s', {'n': 15})),
                  secondary: const Icon(Icons.battery_saver_rounded),
                ),
                SwitchListTile(
                  value: s.voiceCoach,
                  onChanged: (v) => s.voiceCoach = v,
                  title: Text(tr('Voice coach')),
                  subtitle: Text(tr('Spoken km splits and pace')),
                  secondary: const Icon(Icons.record_voice_over_rounded),
                ),
                SwitchListTile(
                  value: s.readCheers,
                  onChanged: (v) => s.readCheers = v,
                  title: Text(tr('Read cheers aloud')),
                  subtitle: Text(tr('Hear messages from friends mid-run')),
                  secondary: const Icon(Icons.campaign_rounded),
                ),
                ListTile(
                  leading: const Icon(Icons.flag_rounded),
                  title: Text(tr('Target time')),
                  subtitle: Text(
                    '${fmtDuration(s.targetTimeS, forceHours: true)} · ${fmtPace(s.targetTimeS / (sim.race.distanceM / 1000), s.units)}',
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showTargetTimePicker(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.icon, required this.title, required this.child, this.padding = const EdgeInsets.all(16)});
  final IconData icon;
  final String title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RLCard(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding.left == 0 ? 16 : 0),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: RL.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontSize: 15))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: muted(context)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: muted(context), height: 1.3))),
      ],
    );
  }
}

/// Chips that wrap onto a second line on narrow phones (never overflow).
class _Choices<T> extends StatelessWidget {
  const _Choices({required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: v == value,
            showCheckmark: false,
            selectedColor: RL.amber,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: v == value ? Colors.white : ink(context)),
            onSelected: (_) => onChanged(v),
          ),
      ],
    );
  }
}

/// Bottom sheet to pick the race target time.
Future<void> showTargetTimePicker(BuildContext context) {
  final settings = context.read<SettingsController>();
  final distanceM = context.read<RaceSim>().race.distanceM;
  var value = settings.targetTimeS;
  const presets = [5400, 5700, 6000, 6300, 7200, 8100];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void bump(int d) => setState(() => value = (value + d).clamp(20 * 60, 6 * 3600));
        Widget step(String label, int d) => OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: () => bump(d),
              child: Text(label),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Target time'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink(context))),
                Text(tr('Used for target alerts and the "Target smashed" badge.'), style: TextStyle(color: muted(context), fontSize: 12.5)),
                const SizedBox(height: 16),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      fmtDuration(value, forceHours: true),
                      style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    tr('{pace} average over {dist}', {'pace': fmtPace(value / (distanceM / 1000), settings.units), 'dist': fmtDistance(distanceM, settings.units)}),
                    style: TextStyle(color: muted(context)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: step('−1 min', -60)),
                    const SizedBox(width: 8),
                    Expanded(child: step('−10 s', -10)),
                    const SizedBox(width: 8),
                    Expanded(child: step('+10 s', 10)),
                    const SizedBox(width: 8),
                    Expanded(child: step('+1 min', 60)),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in presets)
                      ChoiceChip(
                        label: Text(fmtDuration(p)),
                        selected: value == p,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => value = p),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () {
                    settings.targetTimeS = value;
                    Navigator.pop(context);
                  },
                  child: Text(tr('Save target')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
