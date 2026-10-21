import 'dart:async';
import 'package:flutter/services.dart';
import '../contracts.dart';

class LocationCaptureFailure implements Exception {
  const LocationCaptureFailure(this.code, this.message);
  final String code, message;
  bool get canOpenSettings => [
    'LOCATION_DISABLED',
    'PERMISSION_DENIED',
    'PERMISSION_RESTRICTED',
  ].contains(code);
  @override
  String toString() => message;
}

enum LocationCaptureStage { permission, locating }

/// A foreground, one-shot fix. No location is requested during sync/retries.
class LocationCapture {
  const LocationCapture();
  static const channel = MethodChannel('field_assist/location');
  static bool _capturing = false;
  Future<ReportLocation> capture({
    void Function(LocationCaptureStage)? onStage,
  }) async {
    // A rejected duplicate must never cancel the first caller's native request.
    if (_capturing) {
      throw const LocationCaptureFailure(
        'LOCATION_BUSY',
        'A location request is already in progress.',
      );
    }
    _capturing = true;
    try {
      onStage?.call(LocationCaptureStage.permission);
      await channel
          .invokeMethod<void>('prepare')
          .timeout(const Duration(seconds: 60));
      onStage?.call(LocationCaptureStage.locating);
      final raw = await channel
          .invokeMapMethod<String, dynamic>('capture')
          .timeout(const Duration(seconds: 75));
      if (raw == null) throw const FormatException('No location returned.');
      final location = ReportLocation.fromJson(raw);
      location.requireFresh(DateTime.now().toUtc());
      return location;
    } on PlatformException catch (e) {
      throw LocationCaptureFailure(
        e.code,
        e.message ?? 'Location is unavailable. Retry outdoors.',
      );
    } on MissingPluginException {
      throw const LocationCaptureFailure(
        'LOCATION_UNAVAILABLE',
        'Install the updated app to capture location. Your draft is saved.',
      );
    } on TimeoutException {
      throw const LocationCaptureFailure(
        'LOCATION_TIMEOUT',
        'Location took too long. Check device location is on, move outdoors, and retry. Your draft is saved.',
      );
    } on FormatException {
      throw const LocationCaptureFailure(
        'LOCATION_INVALID',
        'A fresh location could not be obtained. Move outdoors and retry. Your draft is saved.',
      );
    } finally {
      // Cleanup must not replace the actual permission or capture error.
      try {
        await channel
            .invokeMethod<void>('cancel')
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        /* No active native request. */
      }
      _capturing = false;
    }
  }

  Future<void> openSettings({required bool deviceLocation}) => channel
      .invokeMethod<void>('openSettings', {'deviceLocation': deviceLocation});
}
