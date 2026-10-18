import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// The base map used by every map in the app: OpenStreetMap tiles, with
/// flutter_map's dark-mode filter in dark theme. Keep tile settings here so
/// all maps switch together (production should move to a paid or
/// self-hosted tile server — OSM's public tiles are for light use only).
TileLayer runlahTileLayer(BuildContext context, {TileProvider? tileProvider}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.runlah.runlah',
    maxNativeZoom: 19,
    tileProvider: tileProvider,
    tileBuilder: dark ? darkModeTileBuilder : null,
  );
}

/// Required credit for OpenStreetMap tiles.
const mapAttribution = '© OpenStreetMap contributors';
