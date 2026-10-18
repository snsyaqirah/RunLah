import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_state.dart';
import '../features/insights/insights_screen.dart';
import '../features/insights/share_card_screen.dart';
import '../features/organizer/organizer_screen.dart';
import '../features/three/race3d_mode.dart';
import '../features/three/race3d_screen.dart';

/// Cross-feature navigation. Features call these instead of importing each
/// other's screens, so every feature can be built independently.

Future<void> openInsights(BuildContext context, int participantId, {int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InsightsScreen(participantId: participantId, initialTab: tab)));

Future<void> openShareCard(BuildContext context, int participantId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShareCardScreen(participantId: participantId)));

Future<void> openRace3D(BuildContext context, Race3DMode mode, {int? focusParticipantId, double? atRaceTime}) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Race3DScreen(mode: mode, focusParticipantId: focusParticipantId, atRaceTime: atRaceTime)),
    );

Future<void> openOrganizer(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OrganizerScreen()));

/// Switch bottom-nav tab and pop back to the shell.
void goToTab(BuildContext context, AppTab tab) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  context.read<ShellController>().tab = tab;
}
