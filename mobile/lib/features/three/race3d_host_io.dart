import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'race3d_host_api.dart';

/// Android / iOS / macOS: the bundled HTML in a WebView.
Widget buildRace3DHost(Race3DHostCallbacks callbacks) => _WebViewHost(callbacks: callbacks);

const _asset = 'assets/three/race3d.html';

class _WebViewHost extends StatefulWidget {
  const _WebViewHost({required this.callbacks});
  final Race3DHostCallbacks callbacks;

  @override
  State<_WebViewHost> createState() => _WebViewHostState();
}

class _WebViewHostState extends State<_WebViewHost> {
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    // No WebView implementation registered: widget tests, Linux, Windows.
    if (WebViewPlatform.instance == null) return;
    final cb = widget.callbacks;
    final web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B1220))
      ..addJavaScriptChannel('RunLah', onMessageReceived: (m) => cb.onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => cb.onPageStarted(),
        onPageFinished: (_) => cb.onPageFinished(),
        // The scene is fully local; never navigate away from it.
        onNavigationRequest: (r) => r.url.startsWith('file:') || r.url.startsWith('about:') ? NavigationDecision.navigate : NavigationDecision.prevent,
      ));
    if (kDebugMode) {
      web.setOnConsoleMessage((m) => debugPrint('race3d console: ${m.message}'));
    }
    web.loadFlutterAsset(_asset);
    cb.onAttach((json) async {
      try {
        await web.runJavaScript('window.runlah&&window.runlah.receive(${jsonEncode(json)})');
      } catch (e) {
        if (kDebugMode) debugPrint('race3d: $e');
      }
    });
    _web = web;
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    if (web == null) return Race3DPlaceholder(message: race3dUnsupportedMessage());
    return WebViewWidget(
      controller: web,
      // Orbit / pinch / tap all belong to the scene.
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    );
  }
}
