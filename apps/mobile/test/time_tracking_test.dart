import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'package:field_assist/features/time_tracking/time_tracking.dart';
import 'package:field_assist/features/time_tracking/site_time_card.dart';
import 'package:field_assist/features/settings/avatar_picker.dart';
import 'package:field_assist/core/design_system/profile_avatar.dart';
import 'jobs_test.dart' as fixture;

Map<String, dynamic> event(String action, int sequence, String at) => {
  'requestId': 'event-$sequence',
  'action': action,
  'sequence': sequence,
  'occurredAt': '2026-10-16T$at:00Z',
};

class BoundDatabase implements Database {
  final saved = <Map<String, Object?>>[];
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    saved.add(values);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SwappingRepository extends SecureReportRepository {
  SwappingRepository() : super(const FlutterSecureStorage());
  final original = BoundDatabase(), next = BoundDatabase();
  bool switched = false;
  @override
  Database get database => switched ? next : original;
  @override
  Future<void> checkStorage({int minimumBytes = 2097152}) async {
    switched = true;
  }
}

void main() {
  test(
    'enqueue remains bound to the original encrypted database during account changes',
    () async {
      final repo = SwappingRepository(),
          service = CollaborationService(ApiClient(), repo);
      await service.enqueue(
        'original-owner',
        'time',
        'work-orders/job/time-events',
        {'sequence': 1},
      );
      expect(repo.original.saved.length, 1);
      expect(repo.original.saved.single['owner_id'], 'original-owner');
      expect(repo.next.saved, isEmpty);
    },
  );

  test(
    'timestamps recover elapsed work and breaks without a running timer',
    () {
      final events = [
        event('check_in', 1, '08:00'),
        event('break_start', 2, '09:00'),
        event('break_end', 3, '09:15'),
        event('check_out', 4, '10:00'),
      ];
      expect(visitDurations(events, now: DateTime.utc(2026, 10, 17)), {
        'workSeconds': 6300,
        'breakSeconds': 900,
        'siteSeconds': 7200,
      });
    },
  );
  test('open break elapsed duration survives a closed application', () {
    expect(
      visitDurations([
        event('check_in', 1, '08:00'),
        event('break_start', 2, '08:30'),
      ], now: DateTime.utc(2026, 10, 16, 9)),
      {'workSeconds': 1800, 'breakSeconds': 1800, 'siteSeconds': 3600},
    );
  });
  test('queued time actions overlay server receipt once by request ID', () {
    final start = event('check_in', 1, '08:00'),
        end = {
          ...event('check_out', 2, '09:00'),
          'visitId': 'visit',
          'assignmentRevision': 1,
        };
    final state = CollaborationState(
      visits: [
        {
          'id': 'visit',
          'workOrderId': fixture.job().id,
          'startedAt': start['occurredAt'],
          'state': 'working',
          'events': [start],
        },
      ],
      pending: [
        {
          'kind': 'time',
          'route': 'work-orders/${fixture.job().id}/time-events',
          'blocked': 0,
          'payload': jsonEncode(end),
        },
      ],
    );
    final visit = effectiveVisits(state).single;
    expect(visit['state'], 'closed');
    expect(visit['queued'], true);
    expect(visit['siteSeconds'], 3600);
    expect((visit['events'] as List).length, 2);
    final acknowledged = effectiveVisits(
      state.copy(
        visits: [
          {
            ...state.visits.single,
            'events': [start, end],
          },
        ],
      ),
    ).single;
    expect((acknowledged['events'] as List).length, 2);
  });
  test('blocked time actions remain visible and recover on account reopen', () {
    final start = {
      ...event('check_in', 1, '08:00'),
      'visitId': 'visit',
      'assignmentRevision': 1,
    };
    final json = CollaborationState(
      pending: [
        {
          'kind': 'time',
          'route': 'work-orders/job/time-events',
          'blocked': 1,
          'payload': jsonEncode(start),
          'error': 'Assignment changed',
        },
      ],
    ).toJson();
    final visit = effectiveVisits(CollaborationState.fromJson(json)).single;
    expect(visit['blocked'], true);
    expect(visit['state'], 'working');
    expect((visit['events'] as List).single['error'], 'Assignment changed');
  });
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      '${brightness.name} site controls and avatar picker fit a narrow phone',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(fixture.JobController.new)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: fieldTheme(brightness: brightness),
              home: Scaffold(
                body: ListView(
                  children: [
                    SiteTimeCard(job: fixture.job()),
                    const AvatarPicker(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Check in'), findsOneWidget);
        expect(find.text('Time on site'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Save avatar'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byType(ProfileAvatar), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
