// Picks the platform host for the three.js page:
// web -> <iframe> platform view, mobile/desktop -> webview_flutter.
export 'race3d_host_stub.dart'
    if (dart.library.js_interop) 'race3d_host_web.dart'
    if (dart.library.io) 'race3d_host_io.dart';
