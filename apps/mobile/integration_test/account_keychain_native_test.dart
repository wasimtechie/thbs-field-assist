import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/persistence/account_secure_storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'existing iOS Keychain entries update without replacement or duplicate errors',
    (tester) async {
      const current = AccountSecureStorage();
      const legacy = FlutterSecureStorage();
      final key = 'keychain-regression:${const Uuid().v4()}';
      final newKey = '$key:new';
      addTearDown(() async {
        await current.delete(key: key);
        await current.delete(key: newKey);
      });
      // A synthetic entry under the older accessibility policy must stay readable.
      await legacy.write(key: key, value: 'synthetic-original');
      expect(await current.read(key: key), 'synthetic-original');
      for (var i = 0; i < 10; i++) {
        await current.write(key: key, value: 'synthetic-$i');
        expect(await legacy.read(key: key), 'synthetic-$i');
      }
      await current.write(key: newKey, value: 'device-bound-original');
      await current.write(key: newKey, value: 'device-bound-updated');
      expect(await current.read(key: newKey), 'device-bound-updated');
      await current.delete(key: key);
      expect(await legacy.read(key: key), isNull);
      await current.write(key: newKey, value: null);
      expect(await current.read(key: newKey), isNull);
      binding.reportData = {
        'legacyPolicyUpdate': true,
        'repeatedUpdate': true,
        'deviceBoundUpdate': true,
        'scopedDelete': true,
        'scope':
            'Unique synthetic probe keys only; real account keys and reports were not reset.',
      };
    },
  );
}
