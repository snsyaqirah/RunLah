import 'package:flutter/material.dart';

import 'race3d_controller.dart';
import 'race3d_host.dart';
import 'race3d_host_api.dart';

/// Hosts the three.js race scene (`assets/three/race3d.html`, built from
/// `three_src/`). Mobile and desktop use webview_flutter; the web build
/// embeds it in an iframe. In widget tests a placeholder is shown.
///
/// [initPayload] is called whenever the page (re)loads and must return the
/// `init` data (see [Race3DPayload.build]) for the current state.
class Race3DView extends StatefulWidget {
  const Race3DView({super.key, required this.controller, required this.initPayload});
  final Race3DController controller;
  final Map<String, Object?> Function() initPayload;

  @override
  State<Race3DView> createState() => _Race3DViewState();
}

class _Race3DViewState extends State<Race3DView> {
  late final Widget _host = buildRace3DHost(Race3DHostCallbacks(
    onMessage: (json) => widget.controller.handleMessage(json),
    onAttach: (send) => widget.controller.attach(send: send, init: () => widget.initPayload()),
    onPageStarted: () => widget.controller.pageStarted(),
    onPageFinished: () => widget.controller.pageFinished(),
  ));

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(color: const Color(0xFF0B1220), child: _host);
}
