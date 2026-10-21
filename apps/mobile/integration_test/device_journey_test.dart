import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('physical device: provision encrypted storage and recover a draft', (
    tester,
  ) async {
    const email = String.fromEnvironment('TEST_ENGINEER_EMAIL'),
        password = String.fromEnvironment('TEST_ENGINEER_PASSWORD');
    expect(
      email,
      isNotEmpty,
      reason:
          'Supply test-only credentials at build time; never commit passwords.',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final app = container.read(appProvider.notifier);
    // The operator must authorize the real OS biometric/passcode prompt.
    await app.signIn(email, password);
    expect(container.read(appProvider).stage, AccessStage.ready);
    expect(app.repository.cipherVersion, isNotEmpty);
    expect(
      container.read(appProvider).voiceReady,
      isTrue,
      reason: 'No inference double is enabled in this test.',
    );
    final report = await app.startReport();
    expect(report.state, ReportState.draft);
    await app.repository.save(report.id, {});
    await app.lock();
    expect(container.read(appProvider).stage, AccessStage.locked);
    await app.unlock();
    expect((await app.repository.get(report.id)).id, report.id);
    // Airplane mode, force termination and recovery must be executed by the operator
    // using docs/demo.md; a Flutter test alone cannot certify the network is disabled.
    expect(Platform.isIOS || Platform.isAndroid, isTrue);
  });
}
