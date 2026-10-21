import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/networking/api_client.dart';

void main() {
  test(
    'server connection normalizes HTTPS and preserves a supplied API base',
    () {
      expect(
        normalizeServerAddress(' https://demo.example.com '),
        'https://demo.example.com/api/v1/',
      );
      expect(
        normalizeServerAddress('https://demo.example.com/api/v1'),
        'https://demo.example.com/api/v1/',
      );
    },
  );
  test('HTTP stays restricted to explicitly allowed private demo networks', () {
    expect(
      normalizeServerAddress('http://192.168.1.5:3000', allowLocalHttp: true),
      'http://192.168.1.5:3000/api/v1/',
    );
    expect(
      () => normalizeServerAddress(
        'http://demo.example.com',
        allowLocalHttp: true,
      ),
      throwsFormatException,
    );
    expect(
      () => normalizeServerAddress(
        'http://192.168.1.5:3000',
        allowLocalHttp: false,
      ),
      throwsFormatException,
    );
  });
  test('connection settings cannot embed credentials or redirect queries', () {
    for (final value in [
      'https://user:secret@example.com',
      'https://example.com?token=secret',
      'javascript:alert(1)',
      'https://example.com/not-the-api',
    ]) {
      expect(() => normalizeServerAddress(value), throwsFormatException);
    }
  });
}
