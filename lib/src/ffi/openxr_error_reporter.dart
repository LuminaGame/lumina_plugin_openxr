import 'package:logging/logging.dart';

final _log = Logger('OpenXR');

/// Where failures at the native boundary (FFI calls into the OpenXR bridge)
/// are reported. A game logs them; the editor's plugin process sets
/// [handler] to the plugin crash reporter, so Lumina Studio shows the crash
/// screen with the plugin named instead of the process dying.
abstract final class OpenXrErrorReporter {
  /// Receives every reported failure. Null: log only.
  static void Function(Object error, StackTrace stack, String context)? handler;

  /// Reports [error] at [context] and logs it.
  static void report(Object error, StackTrace stack, String context) {
    _log.warning('$context: $error');
    final h = handler;
    if (h != null) h(error, stack, context);
  }

  /// Runs [call]; a throw is reported and [fallback] returned.
  static T guard<T>(String context, T Function() call, T fallback) {
    try {
      return call();
    } catch (e, stack) {
      report(e, stack, context);
      return fallback;
    }
  }
}
