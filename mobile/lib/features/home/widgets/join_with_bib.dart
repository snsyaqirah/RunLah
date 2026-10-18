import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/i18n.dart';
import '../../../core/nav.dart';
import '../../../core/theme.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../home_data.dart';
import 'motion.dart';

/// "Join with bib" (F06): bib number + verification code from the race
/// confirmation email, checked against the start list.
class JoinWithBibCard extends StatefulWidget {
  const JoinWithBibCard({super.key});

  @override
  State<JoinWithBibCard> createState() => _JoinWithBibCardState();
}

enum _View { form, linked, success }

class _JoinWithBibCardState extends State<JoinWithBibCard> {
  final _bib = TextEditingController();
  final _code = TextEditingController();
  ClaimResult? _error;
  String _errorBib = '';
  int _shake = 0;
  bool _busy = false;
  Participant? _joined;
  bool _wantsAnother = false;

  @override
  void dispose() {
    _bib.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    // Stands in for POST /participants/claim.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final sim = context.read<RaceSim>();
    final claims = BibClaims.of(context.read<SettingsController>().prefs);
    final result = claims.claim(sim, _bib.text, _code.text);
    setState(() {
      _busy = false;
      if (result == ClaimResult.success) {
        _joined = sim.byBib(_bib.text.trim());
        _wantsAnother = false;
      } else {
        _error = result;
        _errorBib = _bib.text.trim();
        _shake++;
      }
    });
  }

  String _errorText(ClaimResult r) => switch (r) {
        ClaimResult.invalid => tr('Enter your bib number and the 6-digit verification code.'),
        ClaimResult.unknownBib => tr('Bib {bib} is not on the start list for this race.', {'bib': _errorBib}),
        ClaimResult.wrongCode => tr('That code doesn\'t match bib {bib}. Check your race confirmation email.', {'bib': _errorBib}),
        ClaimResult.alreadyYours => tr('Bib {bib} is already linked to your account.', {'bib': _errorBib}),
        ClaimResult.claimedByOther => tr('Bib {bib} was already claimed by another RunLah account. Contact the organizer if it is yours.', {'bib': _errorBib}),
        ClaimResult.success => '',
      };

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final claims = BibClaims.of(context.read<SettingsController>().prefs);
    final view = _joined != null
        ? _View.success
        : (claims.isClaimed(sim.you.bib) && !_wantsAnother)
            ? _View.linked
            : _View.form;
    return RLCard(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(a), child: child)),
          child: switch (view) {
            _View.success => _Success(key: const ValueKey('success'), p: _joined!, onDone: () => setState(() => _joined = null)),
            _View.linked => _Linked(key: const ValueKey('linked'), onAnother: () => setState(() => _wantsAnother = true)),
            _View.form => _form(context),
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(tr('Join with bib')),
        Text(
          tr('Link your race entry to RunLah for live tracking, splits and Race Insights.'),
          style: TextStyle(color: muted(context), fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 14),
        Shake(
          trigger: _shake,
          child: Column(
            children: [
              TextField(
                key: const Key('join-bib'),
                controller: _bib,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [...digits, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: tr('Bib number'), prefixIcon: const Icon(Icons.tag_rounded)),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('join-code'),
                controller: _code,
                keyboardType: TextInputType.number,
                inputFormatters: [...digits, LengthLimitingTextInputFormatter(6)],
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: tr('Verification code'),
                  helperText: tr('6 digits, from your race confirmation email'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  key: ValueKey('err$_shake'),
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: RL.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_error == ClaimResult.alreadyYours ? Icons.info_outline_rounded : Icons.error_outline_rounded, color: RL.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorText(_error!), style: const TextStyle(color: RL.red, fontWeight: FontWeight.w700, fontSize: 13, height: 1.3))),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _bib.text = '34144';
            _code.text = '261004';
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: RL.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, color: RL.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Demo: bib 34144 · code 261004'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: ink(context)),
                  ),
                ),
                Text(tr('Fill in'), style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900, fontSize: 12.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('join-submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                    const SizedBox(width: 10),
                    Flexible(child: Text(tr('Checking start list…'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                )
              : Text(tr('Join race')),
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({super.key, required this.p, required this.onDone});
  final Participant p;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return Column(
      children: [
        const SizedBox(height: 6),
        const DrawnCheck(size: 84),
        const SizedBox(height: 10),
        Text(tr('You\'re in!'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: ink(context))),
        const SizedBox(height: 4),
        Text(
          tr('Bib {bib} · {name}', {'bib': p.bib, 'name': p.name}),
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Pill(sim.race.categoryById(p.categoryId).name, color: RL.navy),
            Pill(tr('Corral {c}', {'c': corralFor(sim, p.id)}), color: RL.amber),
            Pill(tr('Verified'), color: RL.green, icon: Icons.verified_rounded),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          tr('Live tracking, splits and Race Insights are now linked to this bib.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: muted(context), fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: onDone, child: Text(tr('Done')))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => goToTab(context, AppTab.run),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(tr('Start run'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Linked extends StatelessWidget {
  const _Linked({super.key, required this.onAnother});
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final you = sim.you;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(tr('Join with bib')),
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: RL.green.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, color: RL.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('You\'re in · bib {bib}', {'bib': you.bib}), style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                  Text(
                    tr('{cat} · Corral {c} · verified', {'cat': sim.race.categoryById(you.categoryId).name, 'c': corralFor(sim, you.id)}),
                    style: TextStyle(color: muted(context), fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onAnother, child: Text(tr('Link another bib'))),
        ),
      ],
    );
  }
}
