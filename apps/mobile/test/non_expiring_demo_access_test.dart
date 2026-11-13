import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/offline_access/entitlement.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../fixtures/non-expiring-demo-entitlement.json',
            ).readAsStringSync(),
          )
          as Json;
  final claims = fixture['claims'] as Json;
  final tokens = fixture['tokens'] as Json;
  Future<OfflineLease> verify({
    String variant = 'valid',
    String? email = 'closure@fieldassist.demo',
    String? owner,
    String? device,
    DateTime? now,
    DateTime? observed,
    String? token,
  }) => OfflineLease.verify(
    token ?? tokens[variant] as String,
    fixture['publicJwk'] as Json,
    keyId: 'non-expiring-fixture',
    now: now ?? DateTime.utc(2050),
    lastObserved: observed,
    userId: owner ?? claims['userId'] as String,
    deviceId: device ?? claims['deviceId'] as String,
    nonExpiringDemoEmail: email,
  );

  test(
    'signed synthetic demo remains usable years later without renewal',
    () async {
      for (final year in [2026, 2050, 2100]) {
        final lease = await verify(now: DateTime.utc(year, 12));
        expect(lease.expiresAt, isNull);
        expect(lease.nonExpiringDemo, true);
        expect(lease.id, claims['entitlementId']);
      }
    },
  );

  test(
    'normal account/build verification cannot accept non-expiring access',
    () async {
      await expectLater(verify(email: null), throwsFormatException);
      await expectLater(
        verify(email: 'engineer@example.com'),
        throwsFormatException,
      );
      await expectLater(
        verify(email: 'fibre@fieldassist.demo'),
        throwsFormatException,
      );
    },
  );

  for (final variant in [
    'missingMarker',
    'wrongEmail',
    'wrongOrganization',
    'wrongTemplate',
    'nullExp',
    'missingExpiry',
    'wrongIssuedAt',
  ]) {
    test('signed $variant grant is still rejected', () async {
      await expectLater(verify(variant: variant), throwsFormatException);
    });
  }

  test('signature and account/device bindings remain mandatory', () async {
    await expectLater(verify(owner: 'another-owner'), throwsFormatException);
    await expectLater(verify(device: 'another-device'), throwsFormatException);
    final parts = (tokens['valid'] as String).split('.');
    final altered = {...claims, 'userId': 'altered-user'};
    parts[1] = base64Url
        .encode(utf8.encode(jsonEncode(altered)))
        .replaceAll('=', '');
    await expectLater(verify(token: parts.join('.')), throwsFormatException);
  });

  test(
    'removing expiration does not allow clock rollback or future-issued access',
    () async {
      await expectLater(
        verify(now: DateTime.utc(2026, 11, 12)),
        throwsFormatException,
      );
      await expectLater(
        verify(now: DateTime.utc(2050), observed: DateTime.utc(2050, 1, 2)),
        throwsFormatException,
      );
    },
  );

  test(
    'an ordinary expiring lease still expires in a configured demo build',
    () async {
      final normal =
          jsonDecode(File('../../fixtures/entitlement.json').readAsStringSync())
              as Json;
      await expectLater(
        OfflineLease.verify(
          normal['token'] as String,
          normal['publicJwk'] as Json,
          keyId: 'fixture-key',
          now: DateTime.utc(2050),
          userId: (normal['claims'] as Json)['userId'] as String,
          deviceId: (normal['claims'] as Json)['deviceId'] as String,
          nonExpiringDemoEmail: 'closure@fieldassist.demo',
        ),
        throwsFormatException,
      );
    },
  );
}
