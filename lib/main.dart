import 'package:flutter/material.dart';

import 'dev/plate_workbench.dart';

/// Entry point.
///
/// Until the product shell exists, `flutter run` opens the plate workbench —
/// the hero canvas driven by the real domain engine, so the geometry, the
/// macro ring and the balance lock can all be inspected on a device.
void main() => runApp(const PlateWorkbenchApp());
