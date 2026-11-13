import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'closure_journey_test.dart' as closure;
import 'visit_completion_test.dart' as fixture;

class RestoredRecords extends fixture.VisitRecords {
  @override
  Future<List<LocalReport>> list() async => [fixture.report()];
}

class RestoredController extends AppController {
  RestoredController(this.initialStage);
  final AccessStage initialStage;
  final records = RestoredRecords();
  @override
  SecureReportRepository get repository => records;
  @override
  AppState build() => AppState(
    stage: initialStage,
    form: closure.closureForm,
    user: EngineerIdentity(
      id: 'test-owner',
      name: 'Synthetic engineer',
      email: 'closure@fieldassist.demo',
      organizationId: 'test-org',
      typeId: closure.closureForm.typeId,
      typeName: 'FTTP demo',
      assignmentRevision: 1,
    ),
  );
}

void main() {
  for (final stage in [
    AccessStage.ready,
    AccessStage.provisioning,
    AccessStage.locked,
  ]) {
    test(
      '${stage.name} restores reports and compact answers only in an open authorized workspace',
      () async {
        final container = ProviderContainer(
          overrides: [
            appProvider.overrideWith(() => RestoredController(stage)),
          ],
        );
        addTearDown(container.dispose);
        final app = container.read(appProvider.notifier) as RestoredController;
        app.records.data['closure-demo-summary:closure-test'] = {
          'values': fixture.summaryValues,
          'sources': {},
        };
        await app.reloadReports();
        final state = container.read(appProvider);
        if (stage == AccessStage.locked) {
          expect(state.reports, isEmpty);
          expect(state.summaryDrafts, isEmpty);
        } else {
          expect(state.reports.single.id, 'closure-test');
          expect(
            state.summaryDrafts['closure-test']!['values'],
            fixture.summaryValues,
          );
        }
      },
    );
  }
}
