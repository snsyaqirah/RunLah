import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/activity_store.dart';

/// Result of `POST /activities/{id}/points` (PRD 15.3): how many points the
/// server stored and the timestamp of the last one, so the app can clear its
/// offline queue up to there.
typedef PointsAck = ({int accepted, DateTime? lastT});

/// Where GPS points go. The tracking service drains the offline queue into
/// a sink in batches of at most [maxBatch] points.
abstract class PointsSink {
  static const maxBatch = 500;

  /// `$API_BASE_URL` set at build time (`--dart-define=API_BASE_URL=...`)
  /// talks to the real Laravel API; otherwise the demo sink.
  factory PointsSink.fromEnvironment() {
    const base = String.fromEnvironment('API_BASE_URL');
    const token = String.fromEnvironment('API_TOKEN');
    return base.isEmpty ? DemoPointsSink() : ApiPointsSink(base, token: token.isEmpty ? null : token);
  }

  /// Human name shown in the upload status ("Demo server", "api.runlah.app").
  String get label;

  /// Uploads one batch for the local activity [activityId]. Throws on failure.
  Future<PointsAck> upload(String activityId, List<TrackPoint> points, {String source = 'phone'});
}

/// Pretends to upload: waits a moment like a network call and accepts
/// everything. Used in demo mode so the offline queue is visible.
class DemoPointsSink implements PointsSink {
  DemoPointsSink({this.latency = const Duration(milliseconds: 350)});
  final Duration latency;

  /// Every batch body "sent", newest last (handy in tests and the debug UI).
  final List<Map<String, Object>> sent = [];

  @override
  String get label => 'Demo server';

  @override
  Future<PointsAck> upload(String activityId, List<TrackPoint> points, {String source = 'phone'}) async {
    if (points.length > PointsSink.maxBatch) throw ArgumentError('Batch too large');
    final body = {'source': source, 'points': [for (final p in points) p.toApiJson()]};
    await Future<void>.delayed(latency);
    sent.add(body);
    if (sent.length > 20) sent.removeAt(0);
    return (accepted: points.length, lastT: points.isEmpty ? null : points.last.t);
  }
}

/// Real API: `POST {base}/api/v1/activities/{id}/points` with a Sanctum
/// bearer token. Creates the server-side activity on first upload.
class ApiPointsSink implements PointsSink {
  ApiPointsSink(this.baseUrl, {this.token, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _client;

  /// Local activity id -> server activity id.
  final Map<String, String> _serverIds = {};

  @override
  String get label => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1$path');

  Future<String> _serverId(String localId) async {
    final known = _serverIds[localId];
    if (known != null) return known;
    final res = await _client
        .post(_uri('/activities'), headers: _headers, body: jsonEncode({'mode': 'free', 'client_id': localId}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 300) throw http.ClientException('POST /activities ${res.statusCode}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (j['data'] as Map<String, dynamic>?) ?? j;
    final id = '${data['id']}';
    _serverIds[localId] = id;
    return id;
  }

  @override
  Future<PointsAck> upload(String activityId, List<TrackPoint> points, {String source = 'phone'}) async {
    if (points.length > PointsSink.maxBatch) throw ArgumentError('Batch too large');
    final id = await _serverId(activityId);
    final res = await _client
        .post(
          _uri('/activities/$id/points'),
          headers: _headers,
          body: jsonEncode({'source': source, 'points': [for (final p in points) p.toApiJson()]}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 429) throw http.ClientException('Rate limited (Retry-After ${res.headers['retry-after'] ?? '?'})');
    if (res.statusCode >= 300) throw http.ClientException('Upload failed (${res.statusCode})');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final lastT = j['last_t'] == null ? null : DateTime.tryParse('${j['last_t']}');
    return (accepted: (j['accepted'] as num?)?.toInt() ?? points.length, lastT: lastT ?? points.last.t);
  }
}
