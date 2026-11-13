import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/closure/visit_summary_submission.dart';

void main() {
  test(
    'offline confirmation survives reopen and retries identical payload after a lost response',
    () async {
      final store = <String, Object>{}, sent = <Json>[];
      var offline = true;
      VisitSummaryOutbox create() => VisitSummaryOutbox(
        read: (k) async => store[k],
        write: (k, v) async {
          store[k] = v;
        },
        assertAccess: () async {},
        send: (body) async {
          sent.add(body);
          if (offline) {
            throw const ServiceFailure(
              'NETWORK',
              'Unavailable',
              retryable: true,
            );
          }
          return {'id': 'server-receipt'};
        },
      );
      final queue = create(),
          values = <String, Answer?>{
            'actual_work': const TextAnswer('Installed ONT'),
            'claimed_outcome': const TextAnswer('completed'),
          };
      final first = await queue.enqueue(
        reportId: 'report',
        workOrderId: 'job',
        values: values,
        sources: {},
      );
      expect(first['status'], 'waiting');
      expect(sent, isEmpty);
      expect(await queue.flush(), false);
      expect((await queue.list()).single['status'], 'waiting');
      final reopened = create(),
          again = await reopened.enqueue(
            reportId: 'report',
            workOrderId: 'job',
            values: values,
            sources: {},
          );
      expect(again['id'], first['id']);
      offline = false;
      expect(await reopened.flush(), true);
      expect(sent[0], sent[1]);
      expect((await reopened.list()).single['receipt']['id'], 'server-receipt');
      await reopened.enqueue(
        reportId: 'report',
        workOrderId: 'job',
        values: values,
        sources: {},
      );
      await reopened.flush();
      expect(sent, hasLength(2));
    },
  );
  test('edited summaries preserve both confirmed queued revisions', () async {
    final store = <String, Object>{}, sent = <Json>[];
    final queue = VisitSummaryOutbox(
      read: (k) async => store[k],
      write: (k, v) async {
        store[k] = v;
      },
      assertAccess: () async {},
      send: (p) async {
        sent.add(p);
        return {'id': p['clientSummaryId']};
      },
    );
    final a = await queue.enqueue(
      reportId: 'report',
      workOrderId: null,
      values: {'actual_work': const TextAnswer('Original')},
      sources: {},
    );
    final b = await queue.enqueue(
      reportId: 'report',
      workOrderId: null,
      values: {'actual_work': const TextAnswer('Corrected')},
      sources: {},
    );
    expect(a['id'], isNot(b['id']));
    expect(await queue.list(), hasLength(2));
    await queue.flush();
    expect(sent, hasLength(2));
  });
  test(
    'validation rejection stays visible and does not retry automatically',
    () async {
      final store = <String, Object>{};
      var attempts = 0;
      final queue = VisitSummaryOutbox(
        read: (k) async => store[k],
        write: (k, v) async {
          store[k] = v;
        },
        assertAccess: () async {},
        send: (_) async {
          attempts++;
          throw const ServiceFailure(
            'VALIDATION',
            'Add next action',
            status: 422,
          );
        },
      );
      await queue.enqueue(
        reportId: 'report',
        workOrderId: null,
        values: {},
        sources: {},
      );
      await queue.flush();
      await queue.flush();
      expect(attempts, 1);
      expect((await queue.list()).single['status'], 'attention');
      await queue.flush(manual: true);
      expect(attempts, 2);
    },
  );
  test(
    'workspace switch after server acceptance cannot write a receipt into another account',
    () async {
      final store = <String, Object>{};
      var active = true, writes = 0;
      final queue = VisitSummaryOutbox(
        read: (k) async => store[k],
        write: (k, v) async {
          store[k] = v;
          writes++;
        },
        assertAccess: () async {
          if (!active) throw StateError('Changed workspace');
        },
        send: (_) async {
          active = false;
          return {'id': 'receipt'};
        },
      );
      await queue.enqueue(
        reportId: 'report',
        workOrderId: null,
        values: {},
        sources: {},
      );
      await expectLater(queue.flush(), throwsStateError);
      expect(writes, 1);
    },
  );
  test('legacy received receipt is migrated without another upload', () async {
    final store = <String, Object>{
      'closure-summary-submission:report': {
        'payload': {
          'clientSummaryId': 'original',
          'clientReportId': 'report',
          'workOrderId': null,
          'values': {},
          'sources': {},
          'confirmedAt': '2026-10-22T00:00:00Z',
        },
        'receipt': {'id': 'existing'},
      },
    };
    final queue = VisitSummaryOutbox(
      read: (k) async => store[k],
      write: (k, v) async {
        store[k] = v;
      },
      assertAccess: () async {},
      send: (_) async => throw StateError('Must not send'),
    );
    expect(
      (await queue.enqueue(
        reportId: 'report',
        workOrderId: null,
        values: {},
        sources: {},
      ))['receipt']['id'],
      'existing',
    );
    expect(await queue.flush(), true);
  });
  test(
    'concurrent confirmations serialize without losing another report',
    () async {
      final store = <String, Object>{};
      final queue = VisitSummaryOutbox(
        read: (k) async => store[k],
        write: (k, v) async {
          await Future<void>.delayed(Duration.zero);
          store[k] = v;
        },
        assertAccess: () async {},
        send: (_) async => {},
      );
      await Future.wait([
        for (final id in ['a', 'b', 'c'])
          queue.enqueue(
            reportId: id,
            workOrderId: null,
            values: {},
            sources: {},
          ),
      ]);
      expect(await queue.list(), hasLength(3));
    },
  );
}
