import 'iframe_helper_stub.dart'
    if (dart.library.html) 'iframe_helper_web.dart';

/// Conditional entrypoint to toggle pointer-events on iframe views on Web.
void setWebIframePointerEvents(bool ignore) {
  setIframePointerEvents(ignore);
}
