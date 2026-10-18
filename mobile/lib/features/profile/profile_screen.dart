import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/achievements.dart';
import '../../data/app_state.dart';
import '../../data/sim/race_sim.dart';
import 'badges.dart';
import 'passport.dart';
import 'privacy_screen.dart';
import 'profile_widgets.dart';
import 'qr_sheet.dart';
import 'selfie_frame_screen.dart';
import 'settings_screen.dart';
import 'wrapped_screen.dart';

/// The "Me" tab: profile header, Race Wrapped, quick actions, badges,
/// personal bests, race passport and links to settings / privacy.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Switching language rebuilds the whole app (MaterialApp is keyed on it).
  // Remember where we were so the new Me tab opens at the same spot.
  static double? _restoreOffset;
  static DateTime? _restoreAt;

  late final ScrollController _scroll;
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    final fresh = _restoreAt != null && DateTime.now().difference(_restoreAt!) < const Duration(seconds: 3);
    _scroll = ScrollController(initialScrollOffset: fresh ? (_restoreOffset ?? 0) : 0);
    _restoreOffset = null;
    _restoreAt = null;
    if (SettingsScreen.consumeReopen()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).push(SettingsScreen.route(instant: true));
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setLang(String lang) {
    _restoreOffset = _scroll.hasClients ? _scroll.offset : 0;
    _restoreAt = DateTime.now();
    context.read<SettingsController>().lang = lang;
  }

  /// Celebrate newly unlocked badges, but only while the Me tab is what
  /// the user is looking at (the shell keeps hidden tabs alive).
  void _maybeCelebrate(ProfileView view) {
    final visible = Visibility.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    if (!visible || _celebrating) return;
    final fresh = view.unseen;
    if (fresh.isEmpty) return;
    _celebrating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final achievements = context.read<Achievements>();
      await showBadgeCelebration(context, fresh);
      achievements.markSeen(fresh.map((b) => b.id));
      _celebrating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final sim = context.watch<RaceSim>();
    final snap = context.watch<InsightsController>().snapshot;
    final ach = context.watch<Achievements>();
    final view = ach.view(snap, targetTimeS: settings.targetTimeS);
    _maybeCelebrate(view);

    var i = 0;
    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: _Header(view: view, settings: settings, sim: sim, club: ach.club, onLang: _setLang),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            sliver: SliverList.list(
              children: [
                Reveal(index: i++, child: _WrappedCard(year: view.year, ready: view.wrapped.currentFinished)),
                const SizedBox(height: 12),
                Reveal(index: i++, child: _QuickActions(view: view)),
                const SizedBox(height: 22),
                SectionLabel(
                  tr('Badges'),
                  trailing: Text(
                    tr('{n} of {total}', {'n': view.unlockedCount, 'total': view.badges.length}),
                    style: TextStyle(fontWeight: FontWeight.w800, color: muted(context), fontSize: 12),
                  ),
                ),
                RLCard(padding: const EdgeInsets.fromLTRB(10, 14, 10, 10), child: BadgeGrid(badges: view.badges)),
                const SizedBox(height: 22),
                SectionLabel(tr('Personal bests')),
                PersonalBestGrid(bests: view.bests),
                const SizedBox(height: 22),
                SectionLabel(tr('Race passport'), trailing: Pill(tr('Demo history'), color: RL.slate)),
                RacePassport(entries: view.passport, newPbEntryId: view.wrapped.newPb?.entry?.id),
                const SizedBox(height: 22),
                SectionLabel(tr('Settings & privacy')),
                const _SettingsLinks(),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    tr('RunLah {v} · Demo mode', {'v': Achievements.appVersion}),
                    style: TextStyle(color: muted(context), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ header

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.settings, required this.sim, required this.club, required this.onLang});
  final ProfileView view;
  final SettingsController settings;
  final RaceSim sim;
  final String club;
  final ValueChanged<String> onLang;

  @override
  Widget build(BuildContext context) {
    final you = sim.you;
    final cat = sim.race.categoryById(you.categoryId).name;
    final halfPb = view.halfPb;
    final units = settings.units;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [RL.navy, Color(0xFF1C2D55), Color(0xFF2A2350)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(tr('Me'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  _LangToggle(lang: settings.lang, onChanged: onLang),
                  IconButton(
                    tooltip: tr('My QR code'),
                    onPressed: () => showMyQrSheet(context),
                    icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: tr('Settings'),
                    onPressed: () => Navigator.of(context).push(SettingsScreen.route()),
                    icon: const Icon(Icons.settings_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    ProfileAvatar(name: settings.displayName),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => showEditProfile(context),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    settings.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.edit_rounded, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr('Bib {bib} · {cat}', {'bib': you.bib, 'cat': cat}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.groups_rounded, size: 15, color: Colors.white.withValues(alpha: 0.65)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  club,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _HeadStat(
                            label: tr('Races'),
                            child: CountUp(value: view.racesTotal.toDouble(), format: (v) => '${v.round()}', style: _HeadStat.valueStyle),
                          ),
                        ),
                        const _VDivider(),
                        Expanded(
                          child: _HeadStat(
                            label: tr('{unit} raced in {year}', {'unit': distUnit(units), 'year': view.year}),
                            child: CountUp(
                              value: view.kmThisYearM,
                              format: (v) => fmtDistance(v, units, withUnit: false),
                              style: _HeadStat.valueStyle,
                            ),
                          ),
                        ),
                        const _VDivider(),
                        Expanded(
                          child: _HeadStat(
                            label: tr('Half PB'),
                            badge: halfPb.isNew ? Pill(tr('New PB'), filled: true) : null,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                              child: Text(
                                fmtDuration(halfPb.timeS),
                                key: ValueKey(halfPb.timeS),
                                style: _HeadStat.valueStyle.copyWith(color: halfPb.isNew ? RL.amber : Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadStat extends StatelessWidget {
  const _HeadStat({required this.label, required this.child, this.badge});
  final String label;
  final Widget child;
  final Widget? badge;

  static const valueStyle = TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: child),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11.5, height: 1.2),
          ),
          if (badge != null) ...[
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: badge),
          ],
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: Colors.white.withValues(alpha: 0.12));
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.lang, required this.onChanged});
  final String lang;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String code, String label) {
      final on = lang == code;
      return Semantics(
        button: true,
        selected: on,
        label: code == 'en' ? 'English' : 'Bahasa Malaysia',
        child: GestureDetector(
          onTap: on ? null : () => onChanged(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: on ? RL.amber : Colors.transparent, borderRadius: BorderRadius.circular(99)),
            child: Text(label, style: TextStyle(color: on ? Colors.white : Colors.white70, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('en', 'EN'), seg('ms', 'BM')]),
    );
  }
}

/// Edit display name and club.
Future<void> showEditProfile(BuildContext context) {
  final settings = context.read<SettingsController>();
  final ach = context.read<Achievements>();
  final name = TextEditingController(text: settings.displayName);
  final club = TextEditingController(text: ach.club);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Edit profile')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('Display name')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: club,
              textCapitalization: TextCapitalization.words,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('Running club')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () {
            final n = name.text.trim();
            if (n.isNotEmpty) settings.displayName = n;
            ach.club = club.text;
            Navigator.pop(context);
          },
          child: Text(tr('Save')),
        ),
      ],
    ),
  ).whenComplete(() {
    name.dispose();
    club.dispose();
  });
}

// ------------------------------------------------------------ wrapped card

class _WrappedCard extends StatelessWidget {
  const _WrappedCard({required this.year, required this.ready});
  final int year;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RL.radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B1F6E), Color(0xFF7A2E8F), RL.amber], stops: [0, 0.6, 1]),
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(RaceWrappedScreen.route()),
          child: Stack(
            children: [
              Positioned(right: -30, top: -30, child: _Ring(size: 150, alpha: 0.12)),
              Positioned(right: 30, bottom: -50, child: _Ring(size: 120, alpha: 0.08)),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Pill(ready ? tr('Ready') : tr('Season so far'), color: Colors.white),
                          const SizedBox(height: 10),
                          Text(tr('Race Wrapped'), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          Hero(
                            tag: 'wrapped-year',
                            child: Material(
                              type: MaterialType.transparency,
                              child: Text(
                                '$year',
                                style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr('Your year on the road, story by story'),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 18)),
      );
}

// ----------------------------------------------------------- quick actions

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.view});
  final ProfileView view;

  @override
  Widget build(BuildContext context) {
    final finished = view.current.finished;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Action(
              icon: Icons.photo_camera_front_rounded,
              color: const Color(0xFFEC4899),
              label: tr('Selfie frame'),
              onTap: () => Navigator.of(context).push(SelfieFrameScreen.route()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Action(
              icon: Icons.qr_code_2_rounded,
              color: RL.teal,
              label: tr('My QR code'),
              onTap: () => showMyQrSheet(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Action(
              icon: Icons.ios_share_rounded,
              color: RL.amber,
              label: tr('Share result'),
              dimmed: !finished,
              onTap: () => finished
                  ? openShareCard(context, view.current.participantId!)
                  : showProfileSnack(context, tr('Your result card unlocks when you finish.')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.color, required this.label, required this.onTap, this.dimmed = false});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink(context), height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- settings links

class _SettingsLinks extends StatelessWidget {
  const _SettingsLinks();

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: ink(context)),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: ink(context))),
          subtitle: Text(subtitle, style: TextStyle(color: muted(context), fontSize: 12.5)),
          trailing: Icon(Icons.chevron_right_rounded, color: muted(context)),
          onTap: onTap,
        );
    return RLCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          tile(Icons.tune_rounded, tr('Settings'), tr('Language, units, theme, privacy, voice'), () => Navigator.of(context).push(SettingsScreen.route())),
          const Divider(indent: 16, endIndent: 16),
          tile(Icons.shield_outlined, tr('Privacy & data'), tr('What we collect, export, delete'), () => Navigator.of(context).push(PrivacyScreen.route())),
          const Divider(indent: 16, endIndent: 16),
          tile(Icons.info_outline_rounded, tr('About RunLah'), tr('Version {v} · demo mode', {'v': Achievements.appVersion}), () => showRunLahAbout(context)),
        ],
      ),
    );
  }
}
