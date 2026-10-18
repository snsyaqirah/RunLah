import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'cheer_widgets.dart';
import 'runner_detail_screen.dart';
import 'runner_view.dart';

/// Pulls a bib out of a follow code: `runlah://follow/<bib>`,
/// `https://runlah.app/r/<bib>` (any host, path `/r/<bib>`), or a plain bib. Returns null if nothing usable is in [raw].
String? parseFollowCode(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{1,7}$').hasMatch(s)) return s;
  final uri = Uri.tryParse(s);
  if (uri != null) {
    final segs = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (uri.scheme == 'runlah') {
      // runlah://follow/34144 → host "follow", path "/34144".
      final parts = [if (uri.host.isNotEmpty) uri.host, ...segs];
      final i = parts.indexOf('follow');
      if (i >= 0 && i + 1 < parts.length && RegExp(r'^\d+$').hasMatch(parts[i + 1])) return parts[i + 1];
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final i = segs.indexOf('r');
      if (i >= 0 && i + 1 < segs.length && RegExp(r'^\d+$').hasMatch(segs[i + 1])) return segs[i + 1];
    }
  }
  // A link somewhere inside a longer shared message.
  final m = RegExp(r'(?:runlah://follow/|runlah\.app/r/)(\d+)').firstMatch(s);
  return m?.group(1);
}

/// Bottom sheet: find a runner by name or bib, scan their QR, or paste
/// their share link, then follow them.
Future<void> showAddRunnerSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const AddRunnerSheet(),
    );

class AddRunnerSheet extends StatefulWidget {
  const AddRunnerSheet({super.key});

  @override
  State<AddRunnerSheet> createState() => _AddRunnerSheetState();
}

class _AddRunnerSheetState extends State<AddRunnerSheet> {
  final _q = TextEditingController();
  List<Participant> _results = const [];
  String? _note;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    final sim = context.read<RaceSim>();
    final bib = parseFollowCode(q);
    setState(() {
      _note = null;
      _results = bib != null && q.contains('/') ? [?sim.byBib(bib)] : sim.search(q, limit: 25);
    });
  }

  void _useCode(String? raw) {
    if (raw == null) return;
    final bib = parseFollowCode(raw);
    final sim = context.read<RaceSim>();
    final p = bib == null ? null : sim.byBib(bib);
    setState(() {
      _q.text = bib ?? raw;
      _results = p == null ? const [] : [p];
      _note = p == null ? tr('No runner found for that code.') : tr('Found bib {bib}', {'bib': p.bib});
    });
  }

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {}
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _note = tr('Clipboard is empty. Copy a RunLah link first.'));
      return;
    }
    _useCode(text);
  }

  Future<void> _scan() async {
    final raw = (kIsWeb) ? await _manualCode(context) : await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (mounted) _useCode(raw);
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final follows = context.watch<FollowsController>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('Follow a runner'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context))),
                  const SizedBox(height: 2),
                  Text(
                    tr('Search by name or bib, scan their QR, or paste their link.'),
                    style: TextStyle(fontSize: 12.5, color: muted(context)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('cheer-search'),
                    controller: _q,
                    onChanged: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: tr('Name or bib, e.g. 20417'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _q.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: tr('Clear'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _q.clear();
                                _search('');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scan,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Scan QR'))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Paste link'))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: tr('My QR'),
                        onPressed: () => showMyQr(context),
                        icon: const Icon(Icons.qr_code_2_rounded),
                      ),
                    ],
                  ),
                  if (_note != null) ...[
                    const SizedBox(height: 8),
                    Text(_note!, style: TextStyle(fontSize: 12.5, color: muted(context), fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Flexible(
              child: _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: _q.text.trim().isEmpty
                          ? _Suggestions(onPick: (bib) {
                              _q.text = bib;
                              _search(bib);
                            })
                          : Text(tr('No runners match "{q}".', {'q': _q.text.trim()}), style: TextStyle(color: muted(context))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final p = _results[i];
                        return _ResultTile(
                          participant: p,
                          you: p.id == sim.youId,
                          following: follows.isFollowing(p.id),
                          color: runnerColor(sim, follows.ids, p.id),
                          onFollow: () {
                            HapticFeedback.selectionClick();
                            follows.isFollowing(p.id) ? follows.unfollow(p.id) : follows.follow(p.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});
  final void Function(String bib) onPick;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(tr('Try')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in [...sim.friendIds, sim.youId])
              ActionChip(
                avatar: const Icon(Icons.person_search_rounded, size: 16),
                label: Text('${shortName(sim.participant(id))} · ${sim.participant(id).bib}'),
                onPressed: () => onPick(sim.participant(id).bib),
              ),
          ],
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.participant, required this.you, required this.following, required this.color, required this.onFollow});
  final Participant participant;
  final bool you;
  final bool following;
  final Color color;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = participant;
    final cat = sim.race.categoryById(p.categoryId).name;
    return ListTile(
      onTap: () => openRunnerDetail(context, p.id),
      leading: RunnerAvatar(participant: p, color: color, size: 40),
      title: Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(tr('Bib {bib} · {cat}', {'bib': p.bib, 'cat': cat}), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: you
          ? Pill(tr('You'), color: RL.amber)
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: following
                  ? OutlinedButton.icon(
                      key: const ValueKey('following'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
                      onPressed: onFollow,
                      icon: const Icon(Icons.check_rounded, size: 16, color: RL.green),
                      label: Text(tr('Following')),
                    )
                  : FilledButton(
                      key: const ValueKey('follow'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
                      onPressed: onFollow,
                      child: Text(tr('Follow')),
                    ),
            ),
    );
  }
}

/// Manual entry dialog (web, or when the camera isn't available).
Future<String?> _manualCode(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Enter bib or link')),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: tr('e.g. 20417 or runlah.app/r/20417')),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Find'))),
      ],
    ),
  ).whenComplete(c.dispose);
}

/// "Show my QR" so a friend can follow you by scanning.
Future<void> showMyQr(BuildContext context) {
  final sim = context.read<RaceSim>();
  final you = sim.you;
  final link = shareLinkFor(you);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Your follow code')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 200,
              height: 200,
              child: QrImageView(
                data: link,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: RL.navy),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: RL.navy),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(tr('Bib {bib}', {'bib': you.bib}), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text(link, style: TextStyle(fontSize: 12, color: muted(ctx))),
        ],
      ),
      actions: [
        TextButton(onPressed: () => shareRunnerLink(ctx, you), child: Text(tr('Share link'))),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
      ],
    ),
  );
}

/// Camera QR scanner. Pops with the raw code. If the camera can't start it
/// shows a manual entry field instead.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _controller;
  final _manual = TextEditingController();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    try {
      _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    } catch (_) {
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose().catchError((_) {});
    _manual.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && parseFollowCode(raw) != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  Widget _fallback(BuildContext context, [Object? error]) => Container(
        color: RL.navy,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_rounded, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              tr('Camera not available. Type the bib or paste the link below.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('Scan runner QR')),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (c == null)
                  _fallback(context)
                else
                  MobileScanner(
                    controller: c,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => _fallback(context, error),
                  ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border: Border.all(color: RL.amber, width: 4),
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Text(
                    tr('Point at the QR on their phone or race bib'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manual,
                    decoration: InputDecoration(hintText: tr('Or type bib / paste link'), isDense: true),
                    onSubmitted: (v) => Navigator.of(context).pop(v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.of(context).pop(_manual.text), child: Text(tr('Find'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
