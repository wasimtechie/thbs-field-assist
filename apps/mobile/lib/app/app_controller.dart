import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:field_voice/field_voice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/contracts.dart';
import '../core/location/location_capture.dart';
import '../core/networking/api_client.dart';
import '../core/persistence/report_repository.dart';
import '../core/persistence/account_secure_storage.dart';
import '../features/offline_access/entitlement.dart';
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
    this.reduceMotion = false,
    this.workOrders = const [],
    this.feedback = const [],
    this.operationsSyncedAt,
    this.collaboration = const CollaborationState(),
  });
  final AccessStage stage;
  final String error, notice, step;
  final bool busy, voiceReady, offline, playback, reduceMotion;
  final double progress, speechRate;
  final List<LocalReport> reports;
  final List<WorkOrder> workOrders;
  final List<Json> feedback;
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
    bool? reduceMotion,
    List<WorkOrder>? workOrders,
    List<Json>? feedback,
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
    reduceMotion: reduceMotion ?? this.reduceMotion,
    workOrders: workOrders ?? this.workOrders,
    feedback: feedback ?? this.feedback,
    operationsSyncedAt: operationsSyncedAt ?? this.operationsSyncedAt,
    collaboration: collaboration ?? this.collaboration,
  );
}

final appProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends Notifier<AppState> with CollaborationActions {
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
    } catch (e) {
      if (!ref.mounted) return;
      state = AppState(
        stage: AccessStage.signedOut,
        error: 'Secure account storage could not be opened. ${e.toString()}',
      );
    }
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
    if (state.stage != AccessStage.signedOut) {
      throw StateError(
        'Sign out before changing the server. Saved reports remain on this phone.',
      );
    }
    final url = normalizeServerAddress(address);
    await secrets.write(key: 'api-base-url', value: url);
    api.token = null;
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
      await repository.open(user.id, authorizePresence: true);
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
      } catch (e) {
        state = state.copy(
          voiceReady: false,
          notice: 'Manual forms are available. Voice needs attention: $e',
        );
      }
      await repository.setMetadata(
        'last-sync',
        DateTime.now().toUtc().toIso8601String(),
      );
      await _restoreSettings();
      await reloadReports();
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
      await repository.open(state.user!.id, authorizePresence: true);
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
    } catch (e) {
      if (_currentOwner(owner)) {
        state = state.copy(
          voiceReady: false,
          notice: 'Manual forms are available. Voice needs repair: $e',
        );
      }
    }
  }

  void _warmOpeningPrompt() {
    final form = state.form;
    if (form == null || !state.playback) return;
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
      if (sync.lastError != null) {
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
    if (s != null) {
      state = state.copy(
        playback: s['playback'] as bool? ?? true,
        speechRate: (s['speechRate'] as num?)?.toDouble() ?? 1,
        reduceMotion: s['reduceMotion'] as bool? ?? false,
      );
    }
  }

  Future<void> settings({bool? playback, double? rate, bool? reduced}) async {
    state = state.copy(
      playback: playback,
      speechRate: rate,
      reduceMotion: reduced,
    );
    await repository.setMetadata('settings', {
      'playback': state.playback,
      'speechRate': state.speechRate,
      'reduceMotion': state.reduceMotion,
    });
  }

  Future<void> reloadReports() async {
    if (!ref.mounted) return;
    final owner = state.user?.id, reports = await repository.list();
    if (owner != null && _currentOwner(owner)) {
      state = state.copy(reports: reports);
    }
  }

  Future<LocalReport> startReport() async {
    final lease = await assertAccess();
    final form = state.form;
    if (form == null || !lease.allowedTemplates.contains(form.templateId)) {
      throw StateError('Reconnect to install your assigned form.');
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
    final draft = await repository.create(
      form,
      lease.id,
      workOrderId: id,
      assignmentRevision: job.assignmentRevision,
    );
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
      if (sync.lastError != null) {
        state = state.copy(offline: true, error: sync.lastError, busy: false);
        return;
      }
      state = state.copy(lastSync: DateTime.now(), offline: false, busy: false);
      await provision();
    } catch (e) {
      if (current()) {
        state = state.copy(busy: false, offline: true, error: e.toString());
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
          (state.reports.any((r) => r.state == ReportState.queued) ||
              state.collaboration.pending.any((p) => p['blocked'] != 1)),
      send: () => _syncForeground(state.user!.id),
    );
    _outbox!.start();
    startCollaboration();
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
