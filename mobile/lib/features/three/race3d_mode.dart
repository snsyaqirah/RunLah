/// Which three.js scene to open.
enum Race3DMode {
  /// Whole race animated on a 3D KL course, all runners as glowing dots.
  replay,

  /// Low camera at the finish arch: runners finishing within ±60 s of you.
  drone,

  /// Camera flies along the course before the race (course preview).
  flyover,
}
