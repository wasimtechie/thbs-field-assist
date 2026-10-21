part of 'app_controller.dart';

mixin CollaborationActions on Notifier<AppState> {
  ApiClient get api;
  SecureReportRepository get repository;
  Future<OfflineLease> assertAccess();
  Future<void> refreshOperations({bool quiet = false});
  late final collaboration = CollaborationService(api, repository);
  Timer? _collaborationTimer;
  bool _collaborationRefreshing = false;
  bool _currentOwner(String owner) =>
      ref.mounted &&
      state.stage == AccessStage.ready &&
      state.user?.id == owner;
  String _owner() =>
      state.user?.id ?? (throw StateError('Unlock your account first.'));
  void _checkOwner(String owner) {
    if (!_currentOwner(owner)) {
      throw StateError(
        'Unlock the original account to continue. Its saved work is retained.',
      );
    }
  }

  Future<bool> _pendingFor(String owner) async {
    final rows = await collaboration.pending();
    if (!_currentOwner(owner)) {
      return false;
    }
    final visits = await repository.metadata('time-visits') as List?;
    if (!_currentOwner(owner)) return false;
    state = state.copy(
      collaboration: state.collaboration.copy(
        pending: rows,
        visits: visits?.cast<Json>(),
      ),
    );
    return true;
  }

  void startCollaboration() {
    stopCollaboration();
    _collaborationTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (ref.mounted && state.stage == AccessStage.ready && !state.busy) {
        unawaited(refreshCollaboration(quiet: true));
      }
    });
    unawaited(refreshCollaboration(quiet: true));
  }

  void stopCollaboration() => _collaborationTimer?.cancel();
  List<WorkOrder> queuedWorkOrders(List<WorkOrder> jobs, List<Json> pending) =>
      jobs.map((j) {
        final source = {...j.source};
        for (final p in pending.where(
          (p) =>
              p['kind'] == 'response' &&
              p['blocked'] != 1 &&
              p['route'] == 'work-orders/${j.id}/response',
        )) {
          final payload = jsonDecode(p['payload'] as String) as Json;
          if (payload['assignmentRevision'] == j.assignmentRevision) {
            source['responseStatus'] = payload['decision'];
            source['responseNote'] = payload['note'];
            source['responseQueued'] = true;
          }
        }
        return WorkOrder.fromJson(source);
      }).toList();
  Future<void> restoreCollaboration() async {
    final owner = state.user?.id,
        cached = await repository.metadata('collaboration-snapshot') as Json?,
        pending = await collaboration.pending(),
        visits = await repository.metadata('time-visits') as List?;
    if (ref.mounted &&
        owner != null &&
        state.user?.id == owner &&
        state.stage != AccessStage.signedOut) {
      state = state.copy(
        collaboration: CollaborationState.fromJson(
          cached ?? {},
        ).copy(pending: pending, visits: visits?.cast<Json>()),
      );
    }
  }

  Future<void> refreshCollaboration({bool quiet = false}) async {
    if (!ref.mounted) return;
    final owner = state.user?.id;
    if (state.stage != AccessStage.ready ||
        owner == null ||
        _collaborationRefreshing) {
      return;
    }
    _collaborationRefreshing = true;
    bool current() => _currentOwner(owner);
    try {
      await assertAccess();
      if (!current()) {
        return;
      }
      await collaboration.flush(isCurrent: current);
      if (!current()) {
        return;
      }
      final results = await Future.wait([
        api.send('notifications?limit=100'),
        api.send('conversations?limit=100'),
        api.send('teams'),
        api.send('time-tracking?limit=100'),
      ]);
      if (!current()) {
        return;
      }
      final pending = await collaboration.pending();
      if (!current()) {
        return;
      }
      final snapshot = CollaborationState(
        notifications: (results[0]['items'] as List).cast<Json>(),
        unread: results[0]['unread'] as int,
        conversations: (results[1]['items'] as List).cast<Json>(),
        unreadMessages: results[1]['unread'] as int,
        visits: <String, Json>{
          for (final v in [
            ...(results[3]['items'] as List),
            ...(results[3]['active'] as List),
          ].cast<Json>())
            v['id'] as String: v,
        }.values.toList(),
        teams: (results[2]['items'] as List).cast<Json>(),
        pending: pending,
        syncedAt: DateTime.now(),
      );
      await repository.setMetadata('time-visits', snapshot.visits);
      if (!current()) return;
      await repository.setMetadata('collaboration-snapshot', snapshot.toJson());
      if (!current()) {
        return;
      }
      state = state.copy(collaboration: snapshot);
      await refreshOperations(quiet: true);
    } catch (e) {
      if (current()) {
        try {
          await _pendingFor(owner);
        } catch (_) {}
      }
      if (!quiet) {
        rethrow;
      }
    } finally {
      _collaborationRefreshing = false;
    }
  }

  Future<void> respondToAssignment(
    WorkOrder job,
    String decision,
    String note,
  ) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    final pending = await collaboration.pending();
    _checkOwner(owner);
    if (pending.any(
      (p) =>
          p['kind'] == 'response' &&
          p['route'] == 'work-orders/${job.id}/response',
    )) {
      throw StateError(
        'A response for this job is already queued. Resolve it in Messages → Outbox.',
      );
    }
    final id = const Uuid().v4();
    await collaboration
        .enqueue(owner, 'response', 'work-orders/${job.id}/response', {
          'requestId': id,
          'assignmentRevision': job.assignmentRevision,
          'decision': decision,
          'note': note.trim(),
        }, id: id);
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    state = state.copy(
      workOrders: state.workOrders
          .map(
            (j) => j.id == job.id
                ? WorkOrder.fromJson({
                    ...j.source,
                    'responseStatus': decision,
                    'responseNote': note.trim(),
                    'responseQueued': true,
                  })
                : j,
          )
          .toList(),
    );
    unawaited(refreshCollaboration(quiet: true));
  }

  Future<void> recordSiteTime(
    WorkOrder job,
    String action, {
    String note = '',
  }) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    final pending = await collaboration.pending();
    _checkOwner(owner);
    final visits = effectiveVisits(state.collaboration.copy(pending: pending));
    if (visits.any((v) => v['blocked'] == true)) {
      throw StateError(
        'Resolve the time action in Messages → Outbox before recording more time.',
      );
    }
    final active = visits.where((v) => v['state'] != 'closed').firstOrNull;
    if (action == 'check_in' && (active != null || !job.canStart)) {
      throw StateError(
        'Accept this job and check out of any other active visit first.',
      );
    }
    if (action != 'check_in' &&
        (active == null || active['workOrderId'] != job.id)) {
      throw StateError('Open the job for your active site visit.');
    }
    if (action == 'break_start' && active?['state'] != 'working' ||
        action == 'break_end' && active?['state'] != 'break') {
      throw StateError('Refresh your visit to check its current break state.');
    }
    final location = ['check_in', 'check_out'].contains(action)
        ? await const LocationCapture().capture()
        : null;
    _checkOwner(owner);
    final now = DateTime.now().toUtc();
    if (active != null &&
        now.isBefore(DateTime.parse(active['lastOccurredAt'] as String))) {
      throw StateError(
        'The phone clock moved backwards. Correct it before recording this action.',
      );
    }
    final id = const Uuid().v4();
    await collaboration
        .enqueue(owner, 'time', 'work-orders/${job.id}/time-events', {
          'requestId': id,
          'visitId': active?['id'] ?? const Uuid().v4(),
          'assignmentRevision':
              active?['assignmentRevision'] ?? job.assignmentRevision,
          'sequence': active == null ? 1 : (active['sequence'] as int) + 1,
          'action': action,
          'occurredAt': now.toIso8601String(),
          'location': ?location?.toJson(),
          'note': note.trim(),
        }, id: id);
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    unawaited(refreshCollaboration(quiet: true));
  }

  Future<Json> openConversation({String? recipientId, String? teamId}) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    final existing = state.collaboration.conversations
        .where(
          (c) => teamId != null
              ? c['teamId'] == teamId
              : c['kind'] == 'direct' &&
                    (c['participants'] as List).any(
                      (p) => p['id'] == recipientId,
                    ),
        )
        .firstOrNull;
    if (existing != null) {
      return existing;
    }
    final c = await api.send(
      'conversations',
      method: 'POST',
      body: {'teamId': ?teamId, 'recipientId': ?recipientId},
    );
    _checkOwner(owner);
    await refreshCollaboration(quiet: true);
    _checkOwner(owner);
    return c;
  }

  Future<String> sendMessage(String conversationId, String text) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    final id = const Uuid().v4();
    await collaboration.enqueue(
      owner,
      'message',
      'conversations/$conversationId/messages',
      {'clientMessageId': id, 'text': text.trim()},
      id: id,
    );
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    unawaited(refreshCollaboration(quiet: true));
    return id;
  }

  Future<void> readThread(String id, String sequence) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    final route = 'conversations/$id/read',
        pending = await collaboration.pending();
    _checkOwner(owner);
    if (pending.any(
      (p) =>
          p['route'] == route &&
          (jsonDecode(p['payload'] as String) as Json)['throughSequence'] ==
              sequence,
    )) {
      return;
    }
    await collaboration.enqueue(owner, 'read', route, {
      'throughSequence': sequence,
    });
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    unawaited(refreshCollaboration(quiet: true));
  }

  Future<void> readAlert(String id) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    await collaboration.enqueue(owner, 'read', 'notifications/$id/read', {});
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    final notifications = state.collaboration.notifications
        .map(
          (n) => n['id'] == id
              ? {...n, 'readAt': DateTime.now().toUtc().toIso8601String()}
              : n,
        )
        .toList();
    state = state.copy(
      collaboration: state.collaboration.copy(
        notifications: notifications,
        unread: notifications.where((n) => n['readAt'] == null).length,
      ),
    );
    unawaited(refreshCollaboration(quiet: true));
  }

  Future<void> retryCollaboration(String id) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    await collaboration.retry(id);
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    await refreshCollaboration(quiet: true);
  }

  Future<void> discardCollaboration(String id) async {
    final owner = _owner();
    await assertAccess();
    _checkOwner(owner);
    await collaboration.discard(id);
    _checkOwner(owner);
    await _pendingFor(owner);
    _checkOwner(owner);
    await refreshOperations(quiet: true);
  }
}
