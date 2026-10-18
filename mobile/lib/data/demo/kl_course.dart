import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../models.dart';

/// Demo half marathon around Kuala Lumpur. The line follows real roads
/// roughly (Dataran Merdeka → Chow Kit → Jalan Ampang → KLCC → Bukit Bintang
/// → Brickfields → Lake Gardens → Dataran Merdeka) but it is a demo course,
/// not an official route.
const _waypoints = <List<double>>[
  [3.1478, 101.6936], [3.1488, 101.6953], [3.1497, 101.6962], [3.1530, 101.6968], [3.1570, 101.6970],
  [3.1610, 101.6975], [3.1650, 101.6982], [3.1668, 101.6995], [3.1655, 101.7010], [3.1625, 101.7030],
  [3.1600, 101.7045], [3.1585, 101.7068], [3.1588, 101.7095], [3.1592, 101.7130], [3.1598, 101.7170],
  [3.1605, 101.7215], [3.1612, 101.7262], [3.1618, 101.7300], [3.1622, 101.7360], [3.1628, 101.7425],
  [3.1605, 101.7432], [3.1592, 101.7365], [3.1585, 101.7298], [3.1545, 101.7275], [3.1505, 101.7240],
  [3.1470, 101.7215], [3.1440, 101.7190], [3.1452, 101.7150], [3.1466, 101.7110], [3.1478, 101.7085],
  [3.1500, 101.7062], [3.1525, 101.7050], [3.1510, 101.7025], [3.1475, 101.7012], [3.1440, 101.7005],
  [3.1410, 101.7000], [3.1385, 101.6985], [3.1365, 101.6955], [3.1345, 101.6920], [3.1325, 101.6890],
  [3.1300, 101.6865], [3.1275, 101.6845], [3.1290, 101.6830], [3.1325, 101.6840], [3.1360, 101.6850],
  [3.1395, 101.6855], [3.1418, 101.6872], [3.1440, 101.6860], [3.1470, 101.6845], [3.1500, 101.6850],
  [3.1525, 101.6870], [3.1530, 101.6900], [3.1510, 101.6925], [3.1490, 101.6930], [3.1478, 101.6936],
];

const halfMarathonM = 21097.5;

final klLandmarks = <Landmark>[
  const Landmark(name: 'Petronas Twin Towers', location: LatLng(3.1579, 101.7116), heightM: 452, kind: 'twin'),
  const Landmark(name: 'KL Tower', location: LatLng(3.1528, 101.7038), heightM: 421, kind: 'tower'),
  const Landmark(name: 'Merdeka 118', location: LatLng(3.1416, 101.7006), heightM: 679, kind: 'tower'),
  const Landmark(name: 'Sultan Abdul Samad Building', location: LatLng(3.1486, 101.6945), heightM: 41, kind: 'building'),
  const Landmark(name: 'Masjid Negara', location: LatLng(3.1418, 101.6918), heightM: 73, kind: 'mosque'),
  const Landmark(name: 'KLCC Park', location: LatLng(3.1554, 101.7140), kind: 'park'),
  const Landmark(name: 'Perdana Botanical Garden', location: LatLng(3.1435, 101.6845), kind: 'park'),
];

RoutePath buildKlRoute() => RoutePath([for (final w in _waypoints) LatLng(w[0], w[1])], nominalLength: halfMarathonM);

List<Checkpoint> buildKlCheckpoints(RoutePath route) {
  const names = [
    'Dataran Merdeka',
    'Jalan Sultan Ismail',
    'Jalan Ampang',
    'Ampang U-turn',
    'Jalan Tun Razak',
    'KL Tower',
    'Brickfields',
    'Lake Gardens',
    'Dataran Merdeka',
  ];
  return [
    for (var k = 0; k <= 8; k++)
      Checkpoint(
        id: 100 + k,
        index: k,
        name: names[k],
        type: k == 0 ? CheckpointType.start : (k == 8 ? CheckpointType.finish : CheckpointType.split),
        distanceM: halfMarathonM * k / 8,
        location: route.at(halfMarathonM * k / 8),
      ),
  ];
}

List<Category> buildCategories() {
  final out = <Category>[];
  var id = 1;
  for (final g in Gender.values) {
    for (final band in const [(18, 29), (30, 39), (40, 49), (50, 99)]) {
      final label = band.$2 == 99 ? '${band.$1}+' : '${band.$1 == 18 ? 20 : band.$1}-${band.$2}';
      out.add(Category(id: id++, name: '${g.code} $label', gender: g, ageMin: band.$1, ageMax: band.$2));
    }
  }
  return out;
}

/// The demo event. Gun at 04:45 like the KLSCM half marathon.
RaceEvent buildDemoEvent({DateTime? raceDay}) {
  final day = raceDay ?? DateTime.now();
  final route = buildKlRoute();
  final race = Race(
    id: 21,
    eventId: 1,
    name: 'Half Marathon',
    distanceM: halfMarathonM,
    scheduledStart: DateTime(day.year, day.month, day.day, 4, 45),
    cutoffS: 4 * 3600 + 30 * 60,
    route: route,
    checkpoints: buildKlCheckpoints(route),
    categories: buildCategories(),
    landmarks: klLandmarks,
  );
  return RaceEvent(
    id: 1,
    name: 'KL City Night-to-Dawn Run 2026',
    slug: 'kl-city-run-2026',
    city: 'Kuala Lumpur',
    date: day,
    races: [race],
    organizer: 'RunLah Demo Events',
    blurb: 'A 21.1 km loop from Dataran Merdeka past KLCC, Bukit Bintang and Lake Gardens. Demo event with a simulated field of 11,760 runners.',
    isDemo: true,
  );
}
