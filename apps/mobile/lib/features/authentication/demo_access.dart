import 'package:flutter/foundation.dart';

/// Explicit demo builds can enter the synthetic account automatically. Normal,
/// profile and release builds keep authentication and device presence checks.
class DemoAccess {
  const DemoAccess({
    this.requested = false,
    this.email = '',
    this.password = '',
    this.bundled = false,
  });
  const DemoAccess.fromEnvironment()
    : requested = const bool.fromEnvironment('DEMO_AUTO_LOGIN'),
      email = const String.fromEnvironment('DEMO_ENGINEER_EMAIL'),
      password = const String.fromEnvironment('DEMO_ENGINEER_PASSWORD'),
      bundled = const bool.fromEnvironment('DEMO_BUNDLED_OFFLINE');

  final bool requested;
  final bool bundled;
  final String email, password;
  static bool allowed({
    required bool requested,
    bool debugBuild = kDebugMode,
  }) => requested && debugBuild;
  bool get enabled => allowed(requested: requested);
  bool get offlinePackage => configured && bundled;
  bool get nonExpiringOfflineAccess =>
      offlinePackage && email.toLowerCase() == 'closure@fieldassist.demo';
  bool get configured =>
      enabled &&
      email.toLowerCase().endsWith('@fieldassist.demo') &&
      password.isNotEmpty;
  bool matches(String? accountEmail) =>
      configured && accountEmail?.toLowerCase() == email.toLowerCase();
}
