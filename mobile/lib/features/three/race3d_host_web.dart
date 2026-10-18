import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'race3d_host_api.dart';

/// Flutter web: the bundled HTML in an <iframe>, talking through postMessage.
Widget buildRace3DHost(Race3DHostCallbacks callbacks) => _IframeHost(callbacks: callbacks);

int _seq = 0;

class _IframeHost extends StatefulWidget {
  const _IframeHost({required this.callbacks});
  final Race3DHostCallbacks callbacks;

  @override
  State<_IframeHost> createState() => _IframeHostState();
}

class _IframeHostState extends State<_IframeHost> {
  late final String _viewType;
  late final String _channel;
  web.HTMLIFrameElement? _iframe;
  StreamSubscription<web.MessageEvent>? _messages;

  @override
  void initState() {
    super.initState();
    _seq++;
    _channel = 'rl3d$_seq';
    _viewType = 'runlah-race3d-$_seq';
    final cb = widget.callbacks;
    // The page tags every message with ?ch= so several views can coexist.
    final src = '${ui_web.assetManager.getAssetUrl('assets/three/race3d.html')}?ch=$_channel';
    _messages = web.window.onMessage.listen((e) {
      final data = e.data;
      if (data == null || !data.isA<JSString>()) return;
      final json = (data as JSString).toDart;
      if (!json.contains('"ch":"$_channel"')) return;
      cb.onMessage(json);
    });
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = web.HTMLIFrameElement()
        ..src = src
        ..setAttribute('title', 'RunLah 3D');
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%'
        ..display = 'block';
      frame.onLoad.listen((_) => cb.onPageFinished());
      _iframe = frame;
      return frame;
    });
    cb.onAttach((json) async {
      _iframe?.contentWindow?.postMessage(json.toJS, '*'.toJS);
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
