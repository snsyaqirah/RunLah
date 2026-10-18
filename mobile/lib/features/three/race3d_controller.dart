import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'race3d_mode.dart';

/// Something the three.js page told Flutter.
sealed class Race3DEvent {
  const Race3DEvent();
}

/// The page loaded (and whether WebGL 2 is available).
class Race3DReady extends Race3DEvent {
  const Race3DReady({required this.webgl});
  final bool webgl;
}

/// Playback position, about 4 times a second. [t] is race time (seconds
/// since the gun), or seconds into the loop in flyover mode, where
/// [distance] is the course distance under the camera.
class Race3DTime extends Race3DEvent {
  const Race3DTime(this.t, {required this.playing, this.distance});
  final double t;
  final bool playing;
  final double? distance;
}

/// The user tapped a runner ([id]) or empty space (null).
class Race3DPick extends Race3DEvent {
  const Race3DPick(this.id);
  final int? id;
}

class Race3DError extends Race3DEvent {
  const Race3DError(this.message);
  final String message;
}

/// Drives the three.js scene in `assets/three/race3d.html`.
///
/// Commands go to `window.runlah.receive(json)`; events come back through
/// the `RunLah` JavaScript channel (mobile) or `postMessage` (web iframe).
/// The scene is (re)initialised with [Race3DView.initPayload] every time the
/// page reports `ready`, so commands sent before that are simply dropped —
/// the init message carries the current state.
class Race3DController {
  final _events = StreamController<Race3DEvent>.broadcast();
  Stream<Race3DEvent> get events => _events.stream;

  Future<void> Function(String json)? _send;
  Map<String, Object?> Function()? _init;
  bool _initSent = false;
  bool _disposed = false;

  /// True once the page has received its init message.
  bool get isReady => _initSent;

  void play() => _command({'type': 'play'});
  void pause() => _command({'type': 'pause'});
  void seek(double t) => _command({'type': 'seek', 't': t});
  void setSpeed(double x) => _command({'type': 'speed', 'x': x});

  /// Chase-cam a runner (replay), or null to go back to the overview.
  void follow(int? id) => _command({'type': 'follow', 'id': id});

  void setMode(Race3DMode mode, {double? t, double? speed}) => _command({
        'type': 'mode',
        'mode': mode.name,
        't': ?t,
        'speed': ?speed,
      });

  void _command(Map<String, Object?> m) {
    if (!_initSent || _send == null) return;
    _send!(jsonEncode(m));
  }

  // ------------------------------------------------------------ host side

  /// Called by the platform host once it can talk to the page.
  void attach({required Future<void> Function(String json) send, required Map<String, Object?> Function() init}) {
    _send = send;
    _init = init;
  }

  void detach() {
    _send = null;
  }

  /// A new page load started: it needs a fresh init.
  void pageStarted() => _initSent = false;

  /// Fallback for hosts whose `ready` message can arrive late.
  void pageFinished() {
    if (!_initSent) _sendInit();
  }

  /// Raw JSON from the page.
  void handleMessage(String raw) {
    if (_disposed) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    switch (decoded['type']) {
      case 'ready':
        _sendInit();
        _events.add(Race3DReady(webgl: decoded['webgl'] != false));
      case 'time':
        final t = decoded['t'];
        if (t is num) {
          final d = decoded['d'];
          _events.add(Race3DTime(t.toDouble(), playing: decoded['playing'] == true, distance: d is num ? d.toDouble() : null));
        }
      case 'pick':
        final id = decoded['id'];
        _events.add(Race3DPick(id is num ? id.toInt() : null));
      case 'error':
        _events.add(Race3DError('${decoded['reason'] ?? decoded['message'] ?? 'error'}'));
        if (kDebugMode) debugPrint('race3d: ${decoded['reason'] ?? decoded['message']}');
    }
  }

  void _sendInit() {
    final send = _send;
    final init = _init;
    if (send == null || init == null) return;
    _initSent = true;
    send(jsonEncode({'type': 'init', 'data': init()}));
  }

  void dispose() {
    _disposed = true;
    _send = null;
    _events.close();
  }
}
