import 'dart:convert';
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
  final DateTime issuedAt, expiresAt;
  static Future<OfflineLease> verify(
    String token,
    Json publicJwk, {
    required String keyId,
    required DateTime now,
    DateTime? lastObserved,
    String? userId,
    String? deviceId,
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
    final issued = DateTime.parse(j['issuedAt'] as String),
        expiry = DateTime.parse(j['expiresAt'] as String);
    if ((j['exp'] as num).toInt() != expiry.millisecondsSinceEpoch ~/ 1000 ||
        (j['iat'] as num).toInt() != issued.millisecondsSinceEpoch ~/ 1000 ||
        now.isAfter(expiry) ||
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
