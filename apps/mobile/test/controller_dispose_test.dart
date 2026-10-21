import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'appearance_journey_test.dart' as fixture;

class DelayedCollaboration extends CollaborationService {
  DelayedCollaboration() : super(ApiClient(), fixture.MemoryReports());
  final entered = Completer<void>(), release = Completer<void>();
  int pendingReads = 0;
  @override
  Future<bool> flush({required bool Function() isCurrent}) async {
    entered.complete();
    await release.future;
    return isCurrent();
  }

  @override
  Future<List<Json>> pending() async {
    pendingReads++;
    return [];
  }
}

class DelayedOperations extends ApiClient {
  final entered = Completer<void>(), release = Completer<Json>();
  int requests = 0;
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) {
    requests++;
    expect(route, 'mobile/operations');
    entered.complete();
    return release.future;
  }
}

class DisposalController extends fixture.DesignController {
  final delayedCollaboration = DelayedCollaboration();
  final delayedOperations = DelayedOperations();
  @override
  CollaborationService get collaboration => delayedCollaboration;
  @override
  ApiClient get api => delayedOperations;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fails in [false, true]) {
    test(
      'disposed collaboration ignores a late ${fails ? 'error' : 'reply'}',
      () async {
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(DisposalController.new)],
        );
        container.read(appProvider);
        final controller =
            container.read(appProvider.notifier) as DisposalController;
        final refresh = controller.refreshCollaboration(quiet: true);
        await controller.delayedCollaboration.entered.future;
        container.dispose();
        if (fails) {
          controller.delayedCollaboration.release.completeError(
            StateError('Synthetic delayed error'),
          );
        } else {
          controller.delayedCollaboration.release.complete();
        }
        await expectLater(refresh, completes);
        expect(controller.delayedOperations.requests, 0);
        expect(controller.delayedCollaboration.pendingReads, 0);
      },
    );
  }
  test(
    'disposed operations ignores a late snapshot before reading the repository',
    () async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(DisposalController.new)],
      );
      container.read(appProvider);
      final controller =
          container.read(appProvider.notifier) as DisposalController;
      final refresh = controller.refreshOperations(quiet: true);
      await controller.delayedOperations.entered.future;
      container.dispose();
      controller.delayedOperations.release.complete({});
      await expectLater(refresh, completes);
      expect(controller.delayedCollaboration.pendingReads, 0);
    },
  );
}
