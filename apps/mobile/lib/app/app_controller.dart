import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:field_voice/field_voice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../features/closure/visit_summary_submission.dart';
import 'package:uuid/uuid.dart';
import '../core/contracts.dart';
import '../core/location/location_capture.dart';
import '../core/networking/api_client.dart';
import '../core/persistence/report_repository.dart';
import '../core/persistence/account_secure_storage.dart';
import '../features/offline_access/entitlement.dart';
import '../features/authentication/demo_access.dart';
import '../features/templates/asset_installer.dart';
import '../features/sync/sync_service.dart';
import '../features/sync/outbox_pump.dart';
import '../features/voice/conversation.dart';
import '../features/voice/patch_rules.dart';
import '../features/voice/prompt_audio_cache.dart';
import '../features/jobs/work_order.dart';
import '../features/time_tracking/time_tracking.dart';
import '../features/collaboration/collaboration_service.dart';
part 'collaboration_controller.dart';

enum AccessStage { booting, signedOut, locked, provisioning, ready }

const _voiceSetupRecoveryNotice =
    'Manual forms are available. To finish voice setup, open Profile → Offline readiness → Sync & repair package.';

class AppState {
  const AppState({
    this.stage = AccessStage.booting,
    this.error = '',
    this.notice = '',
    this.busy = false,
    this.voiceReady = false,
    this.offline = false,
    this.progress = 0,
    this.step = '',
    this.reports = const [],
    this.user,
    this.form,
    this.lease,
    this.lastSync,
    this.playback = true,
    this.speechRate = 1,
    this.speechVoiceId = attentiveSpeechVoice,
    this.reduceMotion = false,
    this.workOrders = const [],
    this.feedback = const [],
    this.summarySubmissions = const [],
    this.summaryDrafts = const {},
    this.operationsSyncedAt,
    this.collaboration = const CollaborationState(),
  });
  final AccessStage stage;
  final String error, notice, step;
  final bool busy, voiceReady, offline, playback, reduceMotion;
  final double progress, speechRate;
  final String speechVoiceId;
  final List<LocalReport> reports;
  final List<WorkOrder> workOrders;
  final List<Json> feedback, summarySubmissions;
  final Map<String, Json> summaryDrafts;
  final DateTime? operationsSyncedAt;
  final CollaborationState collaboration;
  final EngineerIdentity? user;
  final FormDefinition? form;
  final OfflineLease? lease;
  final DateTime? lastSync;
  AppState copy({
    AccessStage? stage,
    String? error,
    String? notice,
    bool? busy,
    bool? voiceReady,
    bool? offline,
    double? progress,
    String? step,
    List<LocalReport>? reports,
    EngineerIdentity? user,
    FormDefinition? form,
    OfflineLease? lease,
    DateTime? lastSync,
    bool? playback,
    double? speechRate,
    String? speechVoiceId,
    bool? reduceMotion,
    List<WorkOrder>? workOrders,
    List<Json>? feedback,
    List<Json>? summarySubmissions,
    Map<String, Json>? summaryDrafts,
    DateTime? operationsSyncedAt,
    CollaborationState? collaboration,
  }) => AppState(
    stage: stage ?? this.stage,
    error: error ?? this.error,
    notice: notice ?? this.notice,
    busy: busy ?? this.busy,
    voiceReady: voiceReady ?? this.voiceReady,
    offline: offline ?? this.offline,
    progress: progress ?? this.progress,
    step: step ?? this.step,
    reports: reports ?? this.reports,
    user: user ?? this.user,
    form: form ?? this.form,
    lease: lease ?? this.lease,
    lastSync: lastSync ?? this.lastSync,
    playback: playback ?? this.playback,
    speechRate: speechRate ?? this.speechRate,
    speechVoiceId: speechVoiceId ?? this.speechVoiceId,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    workOrders: workOrders ?? this.workOrders,
    feedback: feedback ?? this.feedback,
    summarySubmissions: summarySubmissions ?? this.summarySubmissions,
    summaryDrafts: summaryDrafts ?? this.summaryDrafts,
    operationsSyncedAt: operationsSyncedAt ?? this.operationsSyncedAt,
    collaboration: collaboration ?? this.collaboration,
  );
}

final appProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends Notifier<AppState> with CollaborationActions {
  DemoAccess get demoAccess => const DemoAccess.fromEnvironment();
  final secrets = const AccountSecureStorage();
  @override
  late final repository = SecureReportRepository(secrets);
  @override
  late final api = ApiClient();
  late final sync = SyncService(
    api,
    repository,
    beforeUpload: collaboration.canUpload,
  );
  final voice = FieldVoice();
  late final promptAudio = PromptAudioCache(voice);
  OutboxPump? _outbox;
  String? _deviceId;
  Timer? _leaseTimer;
  @override
  AppState build() {
    Future.microtask(bootstrap);
    ref.onDispose(() {
      _leaseTimer?.cancel();
      stopCollaboration();
      _outbox?.stop();
      voice.cancel();
      promptAudio.clear();
    });
    return const AppState();
  }

  Future<void> bootstrap() async {
    try {
      final server = await secrets.read(key: 'api-base-url');
      if (server != null) {
        api.dio.options.baseUrl = normalizeServerAddress(server);
      }
      final owner = await secrets.read(key: 'active-user');
      if (!ref.mounted) return;
      if (owner == null) {
        if (demoAccess.enabled) {
          await startDemo();
          return;
        }
        state = const AppState(stage: AccessStage.signedOut);
        return;
      }
      final identity = await secrets.read(key: 'identity:$owner');
      api.token = await secrets.read(key: 'token:$owner');
      _deviceId = await secrets.read(key: 'device:$owner');
      if (!ref.mounted) return;
      state = AppState(
        stage: AccessStage.locked,
        user: identity == null
            ? null
            : EngineerIdentity.fromJson(jsonDecode(identity) as Json),
      );
      if (demoAccess.enabled) {
        if (demoAccess.matches(state.user?.email)) {
          if (demoAccess.nonExpiringOfflineAccess) {
            OfflineLease? savedLease;
            try {
              savedLease = await assertAccess();
            } catch (_) {
              // An upgraded demo replaces its old timed grant with the signed
              // bundled demo grant, without clearing the encrypted workspace.
            }
            if (savedLease?.nonExpiringDemo != true) {
              await startDemo();
              return;
            }
          }
          await unlock();
          if (!ref.mounted || state.stage == AccessStage.ready) return;
        }
        await startDemo();
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = AppState(
        stage: AccessStage.signedOut,
        error: 'Secure account storage could not be opened. ${e.toString()}',
      );
    }
  }

  Future<void> startDemo() async {
    if (!demoAccess.configured) {
      state = state.copy(
        stage: AccessStage.signedOut,
        busy: false,
        error: 'This demo build needs its synthetic account configuration.',
      );
      return;
    }
    if (demoAccess.offlinePackage) {
      await prepareBundledDemo();
      // Bundled access remains subject to the normal signed lease lifetime.
      // An online sign-in can renew it without replacing encrypted drafts.
      if (state.stage != AccessStage.ready &&
          state.error.contains('offline lease expired')) {
        await signIn(demoAccess.email, demoAccess.password);
        if (state.stage != AccessStage.ready) {
          state = state.copy(
            error:
                'Offline demo access needs renewal. Connect to the dashboard server and open the demo again. ${state.error}',
          );
        }
      }
      return;
    }
    await signIn(demoAccess.email, demoAccess.password);
  }

  Future<Json> loadBundledDemo() async {
    if (!demoAccess.offlinePackage) {
      throw StateError('Offline demo package is not enabled.');
    }
    final snapshot =
        jsonDecode(
              await rootBundle.loadString('assets/offline_demo/bootstrap.json'),
            )
            as Json;
    if (snapshot['synthetic'] != true ||
        !demoAccess.matches((snapshot['user'] as Json)['email'] as String?)) {
      throw StateError(
        'Only the configured synthetic demo account can use this package.',
      );
    }
    return snapshot;
  }

  Future<void> prepareBundledDemo() async {
    state = state.copy(
      stage: AccessStage.provisioning,
      busy: true,
      error: '',
      step: 'Opening bundled offline demo',
      progress: .05,
    );
    try {
      final snapshot = await loadBundledDemo();
      final user = EngineerIdentity.fromJson(snapshot['user'] as Json);
      final form = FormDefinition.fromJson(snapshot['template'] as Json);
      form.verifyHash();
      final previous = await secrets.read(key: 'observed:${user.id}');
      final lease = await OfflineLease.verify(
        snapshot['entitlement'] as String,
        _publicKey,
        keyId: const String.fromEnvironment(
          'ENTITLEMENT_KEY_ID',
          defaultValue: 'field-assist-local-1',
        ),
        now: DateTime.now().toUtc(),
        lastObserved: previous == null ? null : DateTime.parse(previous),
        userId: user.id,
        deviceId: snapshot['deviceId'] as String,
        nonExpiringDemoEmail:
            demoAccess.nonExpiringOfflineAccess &&
                demoAccess.matches(user.email)
            ? user.email
            : null,
      );
      if (!lease.allowedTemplates.contains(form.templateId) ||
          lease.typeId != form.typeId) {
        throw StateError('Bundled form is outside the signed demo access.');
      }
      await repository.open(user.id, authorizePresence: false);
      _deviceId = snapshot['deviceId'] as String;
      await secrets.write(key: 'device:${user.id}', value: _deviceId);
      await secrets.write(
        key: 'lease:${user.id}',
        value: snapshot['entitlement'] as String,
      );
      await secrets.write(
        key: 'observed:${user.id}',
        value: DateTime.now().toUtc().toIso8601String(),
      );
      await secrets.write(
        key: 'identity:${user.id}',
        value: jsonEncode(user.toJson()),
      );
      await secrets.write(key: 'active-user', value: user.id);
      api.token = null;
      await repository.setMetadata('installed-form', form.source);
      if (await repository.metadata('operations-snapshot') == null) {
        await repository.setMetadata(
          'operations-snapshot',
          snapshot['operations'] as Json,
        );
      }
      state = state.copy(
        user: user,
        form: form,
        lease: lease,
        voiceReady: false,
        offline: true,
        step: 'Preparing bundled voice package',
      );
      await _restoreSettings();
      await reloadReports();
      await reloadSummarySubmissions();
      await prepareBundledVoice(user.id, snapshot);
      if (!ref.mounted || state.user?.id != user.id) return;
      state = state.copy(
        stage: AccessStage.ready,
        busy: false,
        progress: 1,
        offline: true,
        notice:
            'Offline demo ready. Jobs, voice and saved summaries are available on this device.',
      );
      _startLeaseMonitor();
    } catch (e) {
      state = state.copy(
        busy: false,
        error: e.toString(),
        step: 'Offline setup needs attention',
      );
    }
  }

  Future<void> prepareBundledVoice(String owner, Json snapshot) async {
    bool current() =>
        ref.mounted &&
        state.user?.id == owner &&
        [AccessStage.ready, AccessStage.provisioning].contains(state.stage);
    final directory = await AssetInstaller(api).installBundled(snapshot, (p) {
      if (current() && state.stage == AccessStage.provisioning) {
        state = state.copy(
          progress: .15 + .7 * p.done / p.total,
          step: 'Preparing offline voice · ${p.done}/${p.total}',
        );
      }
    });
    if (!current()) return;
    await voice.load(directory);
    await voice.smokeTest();
    if (!current()) return;
    await repository.activateVoicePackage(
      directory,
      snapshot['manifest'] as Json,
    );
    if (current()) {
      state = state.copy(
        voiceReady: true,
        notice: 'Offline voice package verified on this device.',
      );
    }
  }

  VisitSummaryOutbox? _summaryOutbox;
  String? _summaryOwner;
  VisitSummaryOutbox summariesFor(String owner) {
    if (_summaryOwner != owner) {
      _summaryOwner = owner;
      Future<void> check() async {
        if (!_currentOwner(owner)) throw StateError('Workspace changed.');
        await assertAccess();
        if (!_currentOwner(owner)) throw StateError('Workspace changed.');
      }

      _summaryOutbox = VisitSummaryOutbox(
        read: repository.metadata,
        write: repository.setMetadata,
        assertAccess: check,
        send: (payload) async {
          await ensureDemoSession(owner);
          await check();
          try {
            return await api.send(
              'visit-summaries',
              method: 'POST',
              body: payload,
            );
          } on ServiceFailure catch (e) {
            if (e.status != 401 || !demoAccess.matches(state.user?.email)) {
              rethrow;
            }
            api.token = null;
            await ensureDemoSession(owner);
            await check();
            return api.send('visit-summaries', method: 'POST', body: payload);
          }
        },
      );
    }
    return _summaryOutbox!;
  }

  Future<void> reloadSummarySubmissions() async {
    final owner = state.user?.id;
    if (owner == null) return;
    // Bootstrap also restores this queue before the ready stage is published.
    final rows =
        (await repository.metadata(VisitSummaryOutbox.storageKey) as List? ??
                [])
            .cast<Json>();
    if (ref.mounted && state.user?.id == owner) {
      state = state.copy(summarySubmissions: rows);
    }
  }

  void cacheSummaryDraft(String id, Json saved, {required String ownerId}) {
    if (_currentOwner(ownerId)) {
      state = state.copy(summaryDrafts: {...state.summaryDrafts, id: saved});
    }
  }

  Future<void> saveSummaryDraft(
    String id,
    Json saved, {
    required String ownerId,
  }) async {
    await assertAccess();
    if (!_currentOwner(ownerId)) throw StateError('Workspace changed.');
    await repository.setMetadata('closure-demo-summary:$id', saved);
    cacheSummaryDraft(id, saved, ownerId: ownerId);
  }

  Future<Json> queueVisitSummary({
    required String reportId,
    required String? workOrderId,
    required Answers values,
    required Json sources,
  }) async {
    final owner =
        state.user?.id ?? (throw StateError('Open your workspace first.'));
    final queued = await summariesFor(owner).enqueue(
      reportId: reportId,
      workOrderId: workOrderId,
      values: values,
      sources: sources,
    );
    if (!_currentOwner(owner)) throw StateError('Workspace changed.');
    await reloadSummarySubmissions();
    unawaited(flushVisitSummaries(owner, manual: true));
    return queued;
  }

  Future<bool> flushVisitSummaries(String owner, {bool manual = false}) async {
    if (!_currentOwner(owner)) return false;
    try {
      final hadPending = state.summarySubmissions.any(
        (e) => e['status'] == 'waiting' || manual && e['status'] == 'attention',
      );
      final done = await summariesFor(owner).flush(manual: manual);
      if (!_currentOwner(owner)) return false;
      await reloadSummarySubmissions();
      if (!done || hadPending) state = state.copy(offline: !done);
      return done;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureDemoSession(String owner) async {
    if (!demoAccess.matches(state.user?.email) || api.token != null) return;
    final login = await api.send(
      'auth/login',
      method: 'POST',
      body: {
        'email': demoAccess.email,
        'password': demoAccess.password,
        'audience': 'mobile',
      },
    );
    if (!_currentOwner(owner)) throw StateError('Workspace changed.');
    if ((login['user'] as Json)['id'] != owner) {
      throw StateError(
        'The server demo account differs from this offline workspace.',
      );
    }
    api.token = login['token'] as String;
    await secrets.write(key: 'token:$owner', value: api.token);
  }

  Future<void> updateAvatar(String avatarId) async {
    final owner = state.user?.id;
    if (owner == null || state.stage != AccessStage.ready) {
      throw StateError('Unlock your account first.');
    }
    await assertAccess();
    if (state.user?.id != owner || state.stage != AccessStage.ready) return;
    await api.send('me/profile', method: 'PATCH', body: {'avatarId': avatarId});
    if (state.user?.id != owner || state.stage != AccessStage.ready) return;
    final updated = EngineerIdentity.fromJson({
      ...state.user!.toJson(),
      'avatarId': avatarId,
    });
    await secrets.write(
      key: 'identity:$owner',
      value: jsonEncode(updated.toJson()),
    );
    if (state.user?.id == owner && state.stage == AccessStage.ready) {
      state = state.copy(user: updated);
    }
  }

  Future<void> configureServer(String address) async {
    if (state.stage != AccessStage.signedOut &&
        !(demoAccess.offlinePackage && demoAccess.matches(state.user?.email))) {
      throw StateError(
        'Sign out before changing the server. Saved reports remain on this phone.',
      );
    }
    final url = normalizeServerAddress(address);
    await secrets.write(key: 'api-base-url', value: url);
    api.token = null;
    if (state.user != null) {
      await secrets.delete(key: 'token:${state.user!.id}');
    }
    api.dio.options.baseUrl = url;
    state = state.copy(error: '');
  }

  Future<void> signIn(String email, String password) async {
    state = state.copy(busy: true, error: '', notice: '');
    try {
      final login = await api.send(
        'auth/login',
        method: 'POST',
        body: {'email': email, 'password': password, 'audience': 'mobile'},
      );
      final user = EngineerIdentity.fromJson(login['user'] as Json);
      api.token = login['token'] as String;
      await repository.open(
        user.id,
        authorizePresence: !demoAccess.matches(user.email),
      );
      _deviceId =
          await secrets.read(key: 'device:${user.id}') ?? const Uuid().v4();
      await secrets.write(key: 'device:${user.id}', value: _deviceId);
      await secrets.write(key: 'token:${user.id}', value: api.token);
      await secrets.write(
        key: 'identity:${user.id}',
        value: jsonEncode(user.toJson()),
      );
      await secrets.write(key: 'active-user', value: user.id);
      state = state.copy(
        user: user,
        stage: AccessStage.provisioning,
        busy: false,
        step: 'Checking assignment',
      );
      await provision();
    } catch (e) {
      state = state.copy(
        busy: false,
        stage: AccessStage.signedOut,
        error: e.toString(),
      );
    }
  }

  Json get _publicKey {
    const value = String.fromEnvironment('ENTITLEMENT_PUBLIC_JWK');
    if (value.isEmpty) {
      throw StateError(
        'The offline signing public key is not pinned in this build. Run the setup script and use its mobile configuration.',
      );
    }
    return jsonDecode(value) as Json;
  }

  @override
  Future<OfflineLease> assertAccess() async {
    final user = state.user;
    if (user == null || _deviceId == null) {
      throw StateError('Provision this account online first.');
    }
    final token = await secrets.read(key: 'lease:${user.id}');
    if (token == null) {
      throw StateError('Reconnect to provision offline access.');
    }
    final previous = await secrets.read(key: 'observed:${user.id}');
    final lease = await OfflineLease.verify(
      token,
      _publicKey,
      keyId: const String.fromEnvironment(
        'ENTITLEMENT_KEY_ID',
        defaultValue: 'field-assist-local-1',
      ),
      now: DateTime.now().toUtc(),
      lastObserved: previous == null ? null : DateTime.parse(previous),
      userId: user.id,
      deviceId: _deviceId,
      nonExpiringDemoEmail:
          demoAccess.nonExpiringOfflineAccess && demoAccess.matches(user.email)
          ? user.email
          : null,
    );
    await secrets.write(
      key: 'observed:${user.id}',
      value: DateTime.now().toUtc().toIso8601String(),
    );
    return lease;
  }

  Future<void> provision() async {
    state = state.copy(
      stage: AccessStage.provisioning,
      busy: true,
      error: '',
      progress: 0.05,
      step: 'Validating account and form',
    );
    try {
      final data = await api.send(
        'devices/provision',
        method: 'POST',
        body: {
          'deviceId': _deviceId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'appVersion': '0.1.0',
          'osVersion': Platform.operatingSystemVersion,
          'model': '${Platform.operatingSystem} device (model not reported)',
          if (demoAccess.nonExpiringOfflineAccess &&
              demoAccess.matches(state.user?.email))
            'nonExpiringDemo': true,
        },
      );
      final form = FormDefinition.fromJson(data['template'] as Json);
      form.verifyHash();
      final user = EngineerIdentity.fromJson(data['user'] as Json);
      final lease = await OfflineLease.verify(
        data['entitlement'] as String,
        _publicKey,
        keyId: const String.fromEnvironment(
          'ENTITLEMENT_KEY_ID',
          defaultValue: 'field-assist-local-1',
        ),
        now: DateTime.parse(data['serverTime'] as String),
        userId: user.id,
        deviceId: _deviceId,
        nonExpiringDemoEmail:
            demoAccess.nonExpiringOfflineAccess &&
                demoAccess.matches(user.email)
            ? user.email
            : null,
      );
      await repository.setMetadata('installed-form', form.source);
      await secrets.write(
        key: 'lease:${user.id}',
        value: data['entitlement'] as String,
      );
      await secrets.write(
        key: 'observed:${user.id}',
        value: data['serverTime'] as String,
      );
      await secrets.write(
        key: 'identity:${user.id}',
        value: jsonEncode(user.toJson()),
      );
      state = state.copy(
        form: form,
        user: user,
        lease: lease,
        progress: 0.15,
        step: 'Verifying local voice assets',
      );
      try {
        final manifest = (data['manifest'] as Json)['assets'] as Json;
        final directory = await AssetInstaller(api).install(
          manifest,
          (p) => state = state.copy(
            progress: .15 + .7 * p.done / p.total,
            step: 'Installing voice package · ${p.done}/${p.total}',
          ),
        );
        await repository.setMetadata('pending-voice-package', {
          'directory': directory,
          'manifest': manifest,
        });
        await voice.load(directory);
        state = state.copy(progress: .9, step: 'Running local speech check');
        await voice.smokeTest();
        await repository.activateVoicePackage(directory, manifest);
        state = state.copy(
          voiceReady: true,
          notice: 'Offline voice package verified on this device.',
        );
      } catch (e, stack) {
        developer.log(
          'Voice package setup failed',
          name: 'field_assist.voice',
          error: e,
          stackTrace: stack,
        );
        state = state.copy(
          voiceReady: false,
          notice: _voiceSetupRecoveryNotice,
        );
      }
      await repository.setMetadata(
        'last-sync',
        DateTime.now().toUtc().toIso8601String(),
      );
      await _restoreSettings();
      await reloadReports();
      await reloadSummarySubmissions();
      state = state.copy(
        stage: AccessStage.ready,
        busy: false,
        progress: 1,
        offline: false,
        lastSync: DateTime.now(),
      );
      _startLeaseMonitor();
      if (state.voiceReady) _warmOpeningPrompt();
      await _heartbeat();
      await refreshOperations(quiet: true);
    } catch (e) {
      state = state.copy(
        busy: false,
        error: e.toString(),
        step: 'Provisioning needs attention',
      );
    }
  }

  Future<void> unlock() async {
    state = state.copy(busy: true, error: '');
    try {
      final lease = await assertAccess();
      await repository.open(
        state.user!.id,
        authorizePresence: !demoAccess.matches(state.user?.email),
      );
      final stored = await repository.metadata('installed-form');
      if (stored == null) {
        throw StateError(
          'No complete form was installed. Reconnect to provision this device.',
        );
      }
      final form = FormDefinition.fromJson(stored as Json);
      form.verifyHash();
      if (!lease.allowedTemplates.contains(form.templateId)) {
        throw StateError('This form is not authorized by the offline lease.');
      }
      await _restoreSettings();
      state = state.copy(
        stage: AccessStage.ready,
        form: form,
        lease: lease,
        voiceReady: false,
        busy: false,
        notice: 'Manual forms are ready. Checking the local voice package…',
      );
      await reloadReports();
      await reloadSummarySubmissions();
      _startLeaseMonitor();
      unawaited(_restoreVoice(state.user!.id));
      unawaited(_syncForeground(state.user!.id));
    } catch (e) {
      await repository.close();
      state = state.copy(
        stage: AccessStage.locked,
        busy: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _restoreVoice(String owner) async {
    try {
      if (demoAccess.offlinePackage) {
        await prepareBundledVoice(owner, await loadBundledDemo());
        return;
      }
      final pending =
          await repository.metadata('pending-voice-package') as Json?;
      final storedDirectory =
          pending?['directory'] as String? ??
          await repository.metadata('voice-directory') as String?;
      final manifest =
          pending?['manifest'] as Json? ??
          await repository.metadata('asset-manifest') as Json?;
      if (!_currentOwner(owner)) return;
      if (storedDirectory == null || manifest == null) {
        throw StateError(
          'Connect from Settings to install the local voice package.',
        );
      }
      final directory = await AssetInstaller.installedDirectory(manifest);
      if (!await AssetInstaller(api).verifyInstalled(manifest, directory)) {
        throw StateError('A local voice asset is missing or corrupt.');
      }
      if (!_currentOwner(owner)) return;
      await voice.load(directory);
      await voice.smokeTest();
      if (!_currentOwner(owner)) return;
      await repository.activateVoicePackage(directory, manifest);
      if (_currentOwner(owner)) {
        state = state.copy(voiceReady: true, notice: '');
        _warmOpeningPrompt();
      }
    } catch (e, stack) {
      developer.log(
        'Voice package restore failed',
        name: 'field_assist.voice',
        error: e,
        stackTrace: stack,
      );
      if (_currentOwner(owner)) {
        state = state.copy(
          voiceReady: false,
          notice: _voiceSetupRecoveryNotice,
        );
      }
    }
  }

  void _warmOpeningPrompt() {
    final form = state.form;
    if (form == null || !state.playback) return;
    // Closure already has prepared prompts. Background live synthesis shares
    // the serial ASR/extraction worker and can delay the first spoken answer.
    if (form.source['closurePolicy'] != null) return;
    // A shared short acknowledgment can play immediately after a durable save;
    // it no longer waits for synthesis of an entire combined next question.
    unawaited(
      promptAudio
          .synthesize('Saved.', speed: state.speechRate)
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    final field = nextQuestion(form, {}, [], {});
    if (field != null) {
      unawaited(
        promptAudio
            .synthesize(spokenQuestion(field), speed: state.speechRate)
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  Future<bool> _syncForeground(String owner) async {
    if (!_currentOwner(owner)) {
      return false;
    }
    try {
      await assertAccess();
      if (!_currentOwner(owner)) return false;
      await ensureDemoSession(owner);
      if (!_currentOwner(owner)) return false;
      final summariesDelivered = await flushVisitSummaries(owner);
      await collaboration.flush(isCurrent: () => _currentOwner(owner));
      if (!_currentOwner(owner)) {
        return false;
      }
      final performed = await sync.run(isCurrent: () => _currentOwner(owner));
      if (!performed) return false;
      if (!_currentOwner(owner)) {
        return false;
      }
      await reloadReports();
      if (!_currentOwner(owner)) return false;
      if (sync.lastError != null || !summariesDelivered) {
        state = state.copy(offline: true);
        return false;
      }
      final now = DateTime.now();
      await repository.setMetadata('last-sync', now.toUtc().toIso8601String());
      if (!_currentOwner(owner)) return false;
      state = state.copy(offline: false, lastSync: now);
      await refreshCollaboration(quiet: true);
      await refreshOperations(quiet: true);
      return true;
    } catch (_) {
      if (_currentOwner(owner)) {
        state = state.copy(offline: true);
      }
    }
    return false;
  }

  Future<void> _restoreSettings() async {
    final owner = state.user?.id;
    await restoreCollaboration();
    if (owner == null || state.user?.id != owner) {
      return;
    }
    final operations =
        await repository.metadata('operations-snapshot') as Json?;
    if (state.user?.id != owner) {
      return;
    }
    state = state.copy(
      workOrders: ((operations?['workOrders'] as List?) ?? [])
          .map((j) => WorkOrder.fromJson(j as Json))
          .toList(),
      feedback: ((operations?['feedback'] as List?) ?? []).cast<Json>(),
      operationsSyncedAt: DateTime.tryParse(
        operations?['syncedAt'] as String? ?? '',
      ),
    );
    state = state.copy(
      workOrders: queuedWorkOrders(
        state.workOrders,
        state.collaboration.pending,
      ),
    );
    final last = await repository.metadata('last-sync') as String?;
    if (state.user?.id != owner) {
      return;
    }
    if (last != null) state = state.copy(lastSync: DateTime.tryParse(last));
    final s = await repository.metadata('settings') as Json?;
    if (state.user?.id != owner) {
      return;
    }
    final voiceId =
        offlineSpeechVoice(s?['speechVoiceId'] as String?)?.id ??
        attentiveSpeechVoice;
    voice.selectSpeechVoice(voiceId);
    promptAudio.clear();
    if (s != null) {
      state = state.copy(
        playback: s['playback'] as bool? ?? true,
        speechRate: (s['speechRate'] as num?)?.toDouble() ?? 1,
        reduceMotion: s['reduceMotion'] as bool? ?? false,
        speechVoiceId: voiceId,
      );
    } else {
      state = state.copy(speechVoiceId: voiceId);
    }
  }

  Future<void> settings({
    bool? playback,
    double? rate,
    bool? reduced,
    String? voiceId,
  }) async {
    if (voiceId != null) {
      voice.selectSpeechVoice(voiceId);
      promptAudio.clear();
    }
    state = state.copy(
      playback: playback,
      speechRate: rate,
      reduceMotion: reduced,
      speechVoiceId: voiceId,
    );
    await repository.setMetadata('settings', {
      'playback': state.playback,
      'speechRate': state.speechRate,
      'reduceMotion': state.reduceMotion,
      'speechVoiceId': state.speechVoiceId,
    });
  }

  Future<int> nextVoiceGreetingIndex() async {
    final owner = state.user?.id;
    final previous = await repository.metadata('voice-greeting-index');
    if (state.user?.id != owner) throw StateError('Workspace changed');
    final index = previous is int && previous >= 0 ? previous % 3 : 0;
    await repository.setMetadata('voice-greeting-index', (index + 1) % 3);
    return index;
  }

  Future<void> reloadReports() async {
    if (!ref.mounted) return;
    final owner = state.user?.id;
    bool current() =>
        ref.mounted &&
        state.user?.id == owner &&
        [AccessStage.ready, AccessStage.provisioning].contains(state.stage);
    if (owner == null || !current()) return;
    final reports = await repository.list();
    if (current()) {
      final summaries = <String, Json>{};
      for (final report in reports.where(
        (r) => r.schema.source['closurePolicy'] != null,
      )) {
        if (!current()) return;
        final saved =
            await repository.metadata('closure-demo-summary:${report.id}')
                as Json?;
        if (saved != null) summaries[report.id] = saved;
      }
      if (current()) {
        state = state.copy(reports: reports, summaryDrafts: summaries);
      }
    }
  }

  Future<LocalReport> startReport() async {
    final lease = await assertAccess();
    final form = state.form;
    if (form == null || !lease.allowedTemplates.contains(form.templateId)) {
      throw StateError('Reconnect to install your assigned form.');
    }
    if (form.source['closurePolicy'] != null) {
      throw StateError(
        'Start the closure assistant from an assigned visit in My jobs.',
      );
    }
    final report = await repository.create(form, lease.id);
    await reloadReports();
    return report;
  }

  @override
  Future<void> refreshOperations({bool quiet = false}) async {
    if (!ref.mounted) return;
    final owner = state.user?.id;
    if (state.stage != AccessStage.ready || owner == null) return;
    try {
      await assertAccess();
      if (!_currentOwner(owner)) return;
      final snapshot = await api.send('mobile/operations');
      if (!_currentOwner(owner)) return;
      final pending = await collaboration.pending();
      if (!_currentOwner(owner)) return;
      final jobs = (snapshot['workOrders'] as List).map((j) {
        final value = Map<String, dynamic>.from(j as Json);
        for (final action in pending.where(
          (a) =>
              a['kind'] == 'response' &&
              a['blocked'] != 1 &&
              a['route'] == 'work-orders/${value['id']}/response',
        )) {
          final payload = jsonDecode(action['payload'] as String) as Json;
          if (payload['assignmentRevision'] == value['assignmentRevision']) {
            value['responseStatus'] = payload['decision'];
            value['responseQueued'] = true;
            value['responseNote'] = payload['note'];
          }
        }
        return WorkOrder.fromJson(value);
      }).toList();
      final feedback = (snapshot['feedback'] as List).cast<Json>();
      final synced = DateTime.parse(snapshot['syncedAt'] as String);
      if (!_currentOwner(owner)) return;
      await repository.setMetadata('operations-snapshot', snapshot);
      if (_currentOwner(owner)) {
        state = state.copy(
          workOrders: jobs,
          feedback: feedback,
          operationsSyncedAt: synced,
        );
      }
    } catch (e) {
      if (!quiet) rethrow;
    }
  }

  Future<LocalReport> startAssignedJob(String id) async {
    final lease = await assertAccess();
    if (state.stage != AccessStage.ready) {
      throw StateError('Unlock the account first.');
    }
    final job = state.workOrders.where((j) => j.id == id).firstOrNull;
    if (job == null || !job.canStart) {
      throw StateError('Refresh your jobs to check this assignment.');
    }
    final acknowledged = state.reports
        .where((r) => r.workOrderId == id && r.state == ReportState.accepted)
        .firstOrNull;
    if (acknowledged != null &&
        acknowledged.receipt?['reportId'] != job.source['latestReportId'] &&
        acknowledged.updatedAt.isAfter(
          DateTime.parse(job.source['updatedAt'] as String),
        )) {
      throw StateError(
        'A report was delivered after this job was downloaded. Refresh assignments before starting another.',
      );
    }
    final existing = state.reports
        .where((r) => r.workOrderId == id && r.state != ReportState.accepted)
        .firstOrNull;
    if (existing != null) {
      if (existing.state == ReportState.draft) return existing;
      throw StateError(
        'A report for this job is already queued. Check the sync queue before starting another.',
      );
    }
    final form = state.form;
    if (form == null ||
        form.typeId != job.typeId ||
        !lease.allowedTemplates.contains(form.templateId)) {
      throw StateError('Connect to install the form assigned to this job.');
    }
    var draft = await repository.create(
      form,
      lease.id,
      workOrderId: id,
      assignmentRevision: job.assignmentRevision,
    );
    final closureContext = job.source['closureContext'] as Json?;
    if (form.source['closurePolicy'] != null && closureContext != null) {
      draft = await repository.save(draft.id, {
        'scenario': TextAnswer(closureContext['scenario'] as String),
        'work_stage': TextAnswer(closureContext['workStage'] as String),
      }, source: 'job_pack');
      await repository.saveClosureCapture(draft.id, {
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'transcript': '',
        'candidates': [
          for (final field in ['scenario', 'work_stage'])
            {
              'fieldId': field,
              'value': field == 'scenario'
                  ? closureContext['scenario']
                  : closureContext['workStage'],
              'sourceSpan':
                  'Assigned job ${job.id}: ${closureContext['scenario']} / ${closureContext['workStage']}',
              'sourceType': 'job_pack',
              'confidence': null,
              'verificationStatus': 'accepted',
              'ambiguityReason':
                  'Assigned job context; verify the premises identity on site.',
            },
        ],
      });
    }
    await reloadReports();
    return draft;
  }

  Future<void> synchronize() async {
    final owner = state.user?.id;
    if (state.busy || owner == null || state.stage != AccessStage.ready) {
      return;
    }
    bool current() => _currentOwner(owner);
    state = state.copy(busy: true, error: '');
    try {
      await ensureDemoSession(owner);
      if (!current()) return;
      final summariesDelivered = await flushVisitSummaries(owner, manual: true);
      if (!current()) return;
      await collaboration.flush(isCurrent: current);
      if (!current()) {
        return;
      }
      if (!await sync.run(manual: true, isCurrent: current)) {
        if (current()) {
          state = state.copy(busy: false);
        }
        return;
      }
      if (!current()) {
        return;
      }
      await reloadReports();
      if (!current()) {
        return;
      }
      if (sync.lastError != null || !summariesDelivered) {
        state = state.copy(
          offline: true,
          error:
              sync.lastError ??
              'A visit summary is still waiting to sync. Its saved details are in Reports.',
          busy: false,
        );
        return;
      }
      state = state.copy(lastSync: DateTime.now(), offline: false, busy: false);
      await provision();
    } catch (e) {
      if (current()) {
        state = state.copy(
          busy: false,
          offline: true,
          error: e is ServiceFailure && e.status == null && e.retryable
              ? 'Dashboard unavailable. Your reports are saved on this device. Submitted reports will be delivered when connected.'
              : e.toString(),
        );
      }
    }
  }

  Future<void> _heartbeat() async {
    if (!ref.mounted) return;
    try {
      await api.send(
        'devices/heartbeat',
        method: 'POST',
        body: {
          'deviceId': _deviceId,
          'readiness': {
            'voiceReady': state.voiceReady,
            'manualReady': true,
            'components': {
              'database': 'SQLCipher ${repository.cipherVersion}',
              'template': 'verified',
              'lease': 'verified',
              'speech': state.voiceReady ? 'local smoke passed' : 'not ready',
            },
          },
          'schemaVersion': '${state.form?.versionNumber}',
          'packageVersion': state.voiceReady
              ? 'field-voice-2026-10-15'
              : 'not ready',
        },
      );
    } catch (_) {
      if (ref.mounted) state = state.copy(offline: true);
    }
  }

  Future<LocalReport> confirmReport(
    String id, {
    void Function(LocationCaptureStage)? onLocationStage,
  }) async {
    await assertAccess();
    final owner = state.user!.id;
    final location = await const LocationCapture().capture(
      onStage: onLocationStage,
    );
    // A permission dialog or trip to Settings may have locked/switched accounts.
    await assertAccess();
    if (state.stage != AccessStage.ready || state.user?.id != owner) {
      throw StateError(
        'Unlock the original account and retry. Your draft is saved.',
      );
    }
    final report = await repository.confirm(
      id,
      timezone: DateTime.now().timeZoneName,
      location: location,
    );
    await reloadReports();
    if (_outbox != null) unawaited(_outbox!.flush(immediately: true));
    return report;
  }

  void _startLeaseMonitor() {
    _outbox ??= OutboxPump(
      hasWork: () =>
          ref.mounted &&
          state.stage == AccessStage.ready &&
          !state.busy &&
          (state.summarySubmissions.any((s) => s['status'] == 'waiting') ||
              state.reports.any((r) => r.state == ReportState.queued) ||
              state.collaboration.pending.any((p) => p['blocked'] != 1)),
      send: () => _syncForeground(state.user!.id),
    );
    _outbox!.start();
    if (!demoAccess.offlinePackage || api.token != null) startCollaboration();
    _leaseTimer?.cancel();
    _leaseTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!ref.mounted || state.stage != AccessStage.ready) return;
      try {
        await assertAccess();
      } catch (e) {
        if (!ref.mounted) return;
        await lock();
        if (!ref.mounted) return;
        state = state.copy(error: e.toString());
      }
    });
  }

  Future<void> lock() async {
    stopCollaboration();
    voice.cancel();
    promptAudio.clear();
    _outbox?.stop();
    _leaseTimer?.cancel();
    await repository.close();
    state = state.copy(
      stage: AccessStage.locked,
      voiceReady: false,
      busy: false,
      reports: [],
      summaryDrafts: const {},
      collaboration: const CollaborationState(),
      error: '',
    );
  }

  Future<void> signOut() async {
    stopCollaboration();
    try {
      await api.send('auth/logout', method: 'POST', body: {});
    } catch (_) {}
    final owner = state.user?.id;
    if (owner != null) {
      await secrets.delete(key: 'lease:$owner');
      await secrets.delete(key: 'token:$owner');
    }
    await secrets.delete(key: 'active-user');
    api.token = null;
    _outbox?.stop();
    promptAudio.clear();
    voice.cancel();
    await repository.close();
    _leaseTimer?.cancel();
    state = const AppState(stage: AccessStage.signedOut);
  }
}
