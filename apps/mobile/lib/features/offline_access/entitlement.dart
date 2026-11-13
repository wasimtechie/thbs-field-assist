import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:jose/jose.dart';
import '../../core/contracts.dart';

class OfflineLease {
  const OfflineLease({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.deviceId,
    required this.typeId,
    required this.allowedTemplates,
    required this.assignmentRevision,
    required this.issuedAt,
    required this.expiresAt,
  });
  final String id, userId, organizationId, deviceId, typeId;
  final List<String> allowedTemplates;
  final int assignmentRevision;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  bool get nonExpiringDemo => expiresAt == null;
  static Future<OfflineLease> verify(
    String token,
    Json publicJwk, {
    required String keyId,
    required DateTime now,
    DateTime? lastObserved,
    String? userId,
    String? deviceId,
    String? nonExpiringDemoEmail,
  }) async {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid offline entitlement');
    }
    final h =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))))
            as Json;
    if (h['alg'] != 'ES256' ||
        h['kid'] != keyId ||
        publicJwk['kty'] != 'EC' ||
        publicJwk['crv'] != 'P-256') {
      throw const FormatException('Untrusted offline signing key');
    }
    final signature = JsonWebSignature.fromCompactSerialization(token);
    final keys = JsonWebKeyStore()
      ..addKey(
        JsonWebKey.fromJson({
          ...publicJwk,
          'kid': keyId,
          'alg': 'ES256',
          'use': 'sig',
        }),
      );
    if (!await signature.verify(keys)) {
      throw const FormatException('Offline signature verification failed');
    }
    final j =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Json;
    if (j['iss'] != 'field-assist' ||
        j['aud'] != 'field-assist-offline' ||
        userId != null && j['userId'] != userId ||
        deviceId != null && j['deviceId'] != deviceId) {
      throw const FormatException(
        'Offline entitlement does not match this account and device',
      );
    }
    final issued = DateTime.parse(j['issuedAt'] as String);
    final expiry = j['expiresAt'] is String
        ? DateTime.parse(j['expiresAt'] as String)
        : null;
    // Only an explicitly configured synthetic debug build may accept a signed
    // grant without expiry. Missing expiry is invalid for ordinary accounts.
    final demoWithoutExpiry =
        kDebugMode &&
        nonExpiringDemoEmail == 'closure@fieldassist.demo' &&
        userId != null &&
        deviceId != null &&
        j['offlineAccess'] == 'non-expiring-synthetic-demo' &&
        j['demoAccount'] == nonExpiringDemoEmail &&
        j['organizationId'] == '10000000-0000-4000-8000-000000000001' &&
        j.containsKey('expiresAt') &&
        j['expiresAt'] == null &&
        !j.containsKey('exp') &&
        j['allowedTemplateIds'] is List &&
        (j['allowedTemplateIds'] as List).length == 1 &&
        (j['allowedTemplateIds'] as List).single ==
            '40000000-0000-4000-8000-000000000006';
    if (expiry == null && !demoWithoutExpiry) {
      throw const FormatException(
        'Offline expiry is missing or not authorised',
      );
    }
    if (expiry != null &&
            (j['exp'] is! num ||
                (j['exp'] as num).toInt() !=
                    expiry.millisecondsSinceEpoch ~/ 1000 ||
                now.isAfter(expiry)) ||
        j['iat'] is! num ||
        (j['iat'] as num).toInt() != issued.millisecondsSinceEpoch ~/ 1000 ||
        now.isBefore(issued.subtract(const Duration(minutes: 2))) ||
        lastObserved != null &&
            now.isBefore(lastObserved.subtract(const Duration(minutes: 2)))) {
      throw const FormatException(
        'Reconnect to validate access. The offline lease expired or the device clock cannot be trusted.',
      );
    }
    return OfflineLease(
      id: j['entitlementId'] as String,
      userId: j['userId'] as String,
      organizationId: j['organizationId'] as String,
      deviceId: j['deviceId'] as String,
      typeId: j['engineerTypeId'] as String,
      allowedTemplates: (j['allowedTemplateIds'] as List).cast<String>(),
      assignmentRevision: j['assignmentRevision'] as int,
      issuedAt: issued,
      expiresAt: expiry,
    );
  }
}
