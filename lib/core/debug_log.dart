import 'package:flutter/foundation.dart';

/// Logs only in debug builds. Messages can contain spoken commands and contact names, and Flutter's
/// plain `print` still writes to the system log in release builds.
void debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}
