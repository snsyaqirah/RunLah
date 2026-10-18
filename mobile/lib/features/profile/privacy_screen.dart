import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/achievements.dart';
import '../../data/app_state.dart';
import 'profile_widgets.dart';

/// PDPA: what RunLah collects, export my data, delete my data, about.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const PrivacyScreen());

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.person_outline_rounded, tr('Profile'), tr('Your display name, club, bib number and race category.')),
      (Icons.my_location_rounded, tr('Live location'), tr('Only while you track a run or race: one GPS point every 5 s (15 s in battery saver). Never in the background after you stop.')),
      (Icons.timer_outlined, tr('Race results'), tr('Checkpoint and finish times from the organiser\'s timing, used for places and Race Insights.')),
      (Icons.campaign_outlined, tr('Cheers'), tr('Messages friends send you, and the ones you send.')),
      (Icons.phone_android_rounded, tr('This device'), tr('Your settings, the runners you follow and a notification token.')),
    ];
    final rights = [
      tr('See and export everything we hold about you.'),
      tr('Correct your name or hide it behind your bib number.'),
      tr('Turn off live tracking at any time.'),
      tr('Delete your data from this device.'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Privacy & data'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          RLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(tr('What RunLah collects')),
                for (final (icon, title, body) in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: RL.teal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: Icon(icon, size: 19, color: RL.teal),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                              const SizedBox(height: 2),
                              Text(body, style: TextStyle(fontSize: 12.5, color: muted(context), height: 1.35)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          RLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel(tr('Your rights (PDPA 2010)')),
                Text(
                  tr('Under Malaysia\'s Personal Data Protection Act 2010 you can:'),
                  style: TextStyle(color: ink(context), height: 1.35),
                ),
                const SizedBox(height: 6),
                for (final r in rights)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_rounded, size: 16, color: RL.green),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(r, style: TextStyle(color: muted(context), fontSize: 13, height: 1.3))),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  tr('We never sell your data. Your live position is shared only as your privacy setting allows.'),
                  style: TextStyle(color: muted(context), fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _export(context),
            icon: const Icon(Icons.download_rounded),
            label: Text(tr('Export my data')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: RL.red, side: const BorderSide(color: RL.red, width: 1.5)),
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(tr('Delete my data')),
          ),
          const SizedBox(height: 18),
          const _AboutCard(),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final ach = context.read<Achievements>();
    final view = ach.view(context.read<InsightsController>().snapshot, targetTimeS: settings.targetTimeS);
    final json = ach.exportJson(view, settings);
    final ok = await shareTextFile(json, fileName: 'runlah-my-data.json', mimeType: 'application/json');
    if (ok || !context.mounted) return;
    // No share sheet (tests, some desktops): show the JSON with a copy button.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Your data')),
        content: SizedBox(
          width: 480,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(tr('Copy')),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: RL.red),
        title: Text(tr('Delete my data?')),
        content: Text(tr('This removes your profile, settings, follows, badges and saved runs from this device. It can\'t be undone.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RL.red, minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final follows = context.read<FollowsController>();
    await context.read<Achievements>().deleteAllData(context.read<SettingsController>());
    follows.clearAll();
    if (context.mounted) showProfileSnack(context, tr('Your data was deleted from this device.'));
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(tr('About')),
          Row(
            children: [
              const RunLahMark(color: RL.amber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Version {v} (demo)', {'v': Achievements.appVersion}),
                  style: TextStyle(color: muted(context), fontWeight: FontWeight.w700),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_demoNote(), style: TextStyle(color: muted(context), fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }
}

String _demoNote() => tr('Demo mode: the race is simulated on this device. Connect the Laravel API with --dart-define=API_BASE_URL=…');

/// About dialog with version, demo note and open-source licences.
void showRunLahAbout(BuildContext context) => showAboutDialog(
      context: context,
      applicationName: 'RunLah',
      applicationVersion: tr('Version {v} (demo)', {'v': Achievements.appVersion}),
      applicationIcon: const RunLahMark(size: 26, showText: false),
      children: [
        Text(tr('Live race tracking and Race Insights for Malaysian runners.')),
        const SizedBox(height: 10),
        Text(_demoNote(), style: const TextStyle(fontSize: 12.5)),
      ],
    );
