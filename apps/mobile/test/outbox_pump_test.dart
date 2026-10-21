import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/features/sync/outbox_pump.dart';

void main() {
  test(
    'confirmed queue retries after backend recovery without overlapping sends',
    () async {
      var time = DateTime(2026, 10, 15),
          work = true,
          connected = false,
          sends = 0;
      final pending = Completer<bool>();
      final pump = OutboxPump(
        hasWork: () => work,
        now: () => time,
        send: () async {
          sends++;
          if (sends == 1) return pending.future;
          if (!connected) return false;
          work = false;
          return true;
        },
      );
      addTearDown(pump.stop);
      final first = pump.flush();
      await pump.flush();
      expect(sends, 1);
      pending.complete(false);
      await first;
      await pump.flush();
      expect(sends, 1);
      time = time.add(const Duration(seconds: 5));
      connected = true;
      await pump.flush();
      expect(sends, 2);
      expect(work, isFalse);
      await pump.flush();
      expect(sends, 2);
    },
  );
  test('drafts and locked sessions produce no upload attempts', () async {
    var confirmed = false, unlocked = true, sends = 0;
    final pump = OutboxPump(
      hasWork: () => confirmed && unlocked,
      send: () async {
        sends++;
        return true;
      },
    );
    addTearDown(pump.stop);
    await pump.flush(immediately: true);
    expect(sends, 0);
    confirmed = true;
    unlocked = false;
    await pump.flush(immediately: true);
    expect(sends, 0);
    unlocked = true;
    await pump.flush(immediately: true);
    expect(sends, 1);
  });
}
