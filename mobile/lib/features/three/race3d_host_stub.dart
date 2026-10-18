import 'package:flutter/widgets.dart';

import 'race3d_host_api.dart';

/// Fallback for platforms with neither dart:io nor JS interop.
Widget buildRace3DHost(Race3DHostCallbacks callbacks) => Race3DPlaceholder(message: race3dUnsupportedMessage());
