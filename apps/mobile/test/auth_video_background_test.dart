import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/authentication/auth_video_background.dart';

class TestVideo extends ValueNotifier<VideoPlayerValue>
    implements VideoPlayerController {
  TestVideo(this.dataSource, {this.pending, this.fail = false})
    : super(const VideoPlayerValue(duration: Duration.zero));
  @override
  final String dataSource;
  final Completer<void>? pending;
  final bool fail;
  final events = <String>[];
  bool closed = false;
  @override
  int get playerId => VideoPlayerController.kUninitializedPlayerId;
  @override
  Future<void> initialize() async {
    events.add('initialize');
    if (pending != null) await pending!.future;
    if (fail) throw StateError('Unavailable decoder');
    if (!closed) {
      value = value.copyWith(
        duration: const Duration(seconds: 30),
        size: const Size(720, 1280),
        isInitialized: true,
      );
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    events.add('volume:$volume');
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> setLooping(bool looping) async {
    events.add('loop:$looping');
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(bool prevents) async {
    events.add('preventSleep:$prevents');
  }

  @override
  Future<void> play() async {
    events.add('play');
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> dispose() async {
    closed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const power = MethodChannel('field_assist/security');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(power, (_) async => false);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(power, null);
  });

  Widget page({
    required VideoPlayerController Function(String) factory,
    Brightness brightness = Brightness.light,
    bool reduced = false,
    bool visible = true,
    bool paused = false,
  }) => MaterialApp(
    theme: fieldTheme(brightness: brightness),
    themeAnimationDuration: Duration.zero,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: TickerMode(
        enabled: visible,
        child: AuthVideoBackground(
          controllerFactory: factory,
          paused: paused,
          child: const Center(child: Text('Sign in form')),
        ),
      ),
    ),
  );

  testWidgets(
    'theme videos mute before playback, loop, and pause when hidden',
    (tester) async {
      final players = <TestVideo>[];
      TestVideo factory(String asset) {
        final player = TestVideo(asset);
        players.add(player);
        return player;
      }

      await tester.pumpWidget(page(factory: factory));
      await tester.pumpAndSettle();
      final light = players.single;
      expect(light.dataSource, 'assets/auth/light.mp4');
      expect(light.value.volume, 0);
      expect(light.value.isLooping, isTrue);
      expect(
        light.events.indexOf('volume:0.0'),
        lessThan(light.events.indexOf('play')),
      );
      expect(light.value.isPlaying, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(light.value.isPlaying, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(light.value.isPlaying, isTrue);

      await tester.pumpWidget(
        page(factory: factory, brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      expect(light.closed, isTrue);
      final dark = players.last;
      expect(dark.dataSource, 'assets/auth/dark.mp4');
      expect(dark.value.isPlaying, isTrue);
      await tester.pumpWidget(
        page(factory: factory, brightness: Brightness.dark, visible: false),
      );
      await tester.pumpAndSettle();
      expect(dark.value.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(dark.closed, isTrue);
    },
  );

  testWidgets(
    'reduced motion uses a poster and decoder failure keeps the form',
    (tester) async {
      final players = <TestVideo>[];
      TestVideo factory(String asset) {
        final player = TestVideo(asset, fail: true);
        players.add(player);
        return player;
      }

      await tester.pumpWidget(page(factory: factory, reduced: true));
      await tester.pumpAndSettle();
      expect(players, isEmpty);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Sign in form'), findsOneWidget);
      await tester.pumpWidget(page(factory: factory));
      await tester.pumpAndSettle();
      expect(players.single.closed, isTrue);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.text('Sign in form'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing during initialization cannot start late playback', (
    tester,
  ) async {
    final pending = Completer<void>();
    final player = TestVideo('test', pending: pending);
    await tester.pumpWidget(page(factory: (_) => player));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pumpAndSettle();
    expect(player.closed, isTrue);
    expect(player.events, isNot(contains('play')));
    expect(tester.takeException(), isNull);
  });
}
