import 'package:flutter/material.dart';

import '../../core/l10n/i18n.dart';
import 'race3d_mode.dart';

/// Placeholder — replaced by the feature implementation.
class Race3DScreen extends StatelessWidget {
  const Race3DScreen({super.key, required this.mode, this.focusParticipantId, this.atRaceTime});
  final Race3DMode mode;

  /// Runner the camera follows / highlights (defaults to you).
  final int? focusParticipantId;

  /// Race time to start the playback at (e.g. a "Where were you" moment).
  final double? atRaceTime;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(tr('3D view'))));
}
