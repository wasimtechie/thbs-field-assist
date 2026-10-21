import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/design_system/profile_avatar.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';

String collaborationTime(String? value) {
  final d = DateTime.tryParse(value ?? '')?.toLocal();
  return d == null
      ? ''
      : '${d.day}/${d.month} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class CollaborationActionsBar extends ConsumerWidget {
  const CollaborationActionsBar({super.key, this.showMessages = true});
  final bool showMessages;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider.select((a) => a.collaboration));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMessages)
          IconButton(
            tooltip: 'Messages',
            onPressed: () => context.push('/messages'),
            icon: Badge.count(
              count: data.unreadMessages,
              isLabelVisible: data.unreadMessages > 0,
              child: const MotionIcon(Icons.chat_bubble_outline_rounded),
            ),
          ),
        IconButton(
          tooltip: 'Alerts',
          onPressed: () => context.push('/alerts'),
          icon: Badge.count(
            count: data.unread,
            isLabelVisible: data.unread > 0,
            child: const MotionIcon(Icons.notifications_outlined),
          ),
        ),
      ],
    );
  }
}

class CommunicationsScreen extends ConsumerStatefulWidget {
  const CommunicationsScreen({super.key});
  @override
  ConsumerState<CommunicationsScreen> createState() =>
      _CommunicationsScreenState();
}

class _CommunicationsScreenState extends ConsumerState<CommunicationsScreen> {
  int tab = 0;
  String query = '', error = '';
  bool searching = false;
  List<Json> people = [];
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(appProvider.notifier).refreshCollaboration(quiet: true),
    );
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> findPeople(String value) async {
    final owner = ref.read(appProvider).user?.id;
    setState(() {
      searching = true;
      error = '';
    });
    try {
      final c = ref.read(appProvider.notifier);
      await c.assertAccess();
      final result = await c.api.send(
        'directory?limit=50&search=${Uri.encodeQueryComponent(value)}',
      );
      if (!mounted || ref.read(appProvider).user?.id != owner) return;
      setState(() => people = (result['items'] as List).cast<Json>());
      await c.repository.setMetadata('directory-cache', people);
    } catch (_) {
      if (mounted) {
        final c = ref.read(appProvider.notifier);
        try {
          final cached =
              (await c.repository.metadata('directory-cache') as List? ?? [])
                  .cast<Json>();
          if (mounted) {
            setState(
              () => people = cached
                  .where(
                    (p) => '${p['name']} ${p['email']} ${p['department']}'
                        .toLowerCase()
                        .contains(value.toLowerCase()),
                  )
                  .toList(),
            );
          }
        } catch (_) {}
        if (mounted) {
          setState(
            () => error =
                'Connect to search the organisation. Previously downloaded contacts remain available.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> open({String? recipientId, String? teamId}) async {
    try {
      final c = await ref
          .read(appProvider.notifier)
          .openConversation(recipientId: recipientId, teamId: teamId);
      if (mounted) context.push('/messages/${c['id']}');
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not open a new conversation. Connect and retry. $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider),
        data = app.collaboration,
        controller = ref.read(appProvider.notifier);
    final pending = data.pending.where((p) => p['kind'] != 'read').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages & team'),
        actions: [
          IconButton(
            tooltip: 'Refresh messages',
            onPressed: () => controller.refreshCollaboration(quiet: true),
            icon: const MotionIcon(Icons.sync_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const WorkspaceIntro(
            title: 'Your people,\nwithin reach.',
            subtitle:
                'Talk to your lead, your squad or someone across the organisation.',
            icon: Icons.forum_outlined,
          ),
          WorkspaceTabs<int>(
            values: [
              (0, 'Chats'),
              (1, 'People'),
              (2, 'Outbox${pending.isEmpty ? '' : ' (${pending.length})'}'),
            ],
            selected: tab,
            onSelected: (value) {
              setState(() => tab = value);
              if (tab == 1) findPeople(query);
            },
          ),
          const SizedBox(height: 18),
          ErrorNotice(error),
          if (tab == 0) ...[
            for (final t in data.teams)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Lead: ${t['lead']['name']} · ${t['department']}',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => open(teamId: t['id'] as String),
                            icon: const MotionIcon(
                              Icons.groups_outlined,
                              size: 17,
                            ),
                            label: const Text('Team chat'),
                          ),
                          if (t['leadId'] != app.user?.id)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  open(recipientId: t['leadId'] as String),
                              icon: const MotionIcon(
                                Icons.support_agent_rounded,
                                size: 17,
                              ),
                              label: const Text('Message lead'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (data.conversations.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                    'Your conversations appear here. Use People to find a colleague anywhere in the organisation.',
                  ),
                ),
              ),
            for (final c in data.conversations)
              Card(
                child: ListTile(
                  leading: c['kind'] == 'team'
                      ? const WorkspaceIcon(Icons.groups_outlined)
                      : ProfileAvatar(
                          name: c['title'] as String? ?? 'Colleague',
                          avatarId:
                              ((c['participants'] as List? ?? [])
                                      .cast<Json>()
                                      .where((p) => p['id'] != app.user?.id)
                                      .firstOrNull?['avatarId']
                                  as String?) ??
                              '',
                          size: 42,
                        ),
                  title: Text(c['title'] as String? ?? 'Conversation'),
                  subtitle: Text(
                    c['lastMessage']?['text'] as String? ??
                        'Start the conversation',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Badge.count(
                    count: c['unread'] as int? ?? 0,
                    isLabelVisible: (c['unread'] as int? ?? 0) > 0,
                    child: const MotionIcon(Icons.chevron_right_rounded),
                  ),
                  onTap: () => context.push('/messages/${c['id']}'),
                ),
              ),
            Text(
              'Alerts and chats refresh while the app is open and unlocked. Downloaded messages remain encrypted on this phone.',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ] else if (tab == 1) ...[
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search your organisation',
                hintText: 'Name, department, squad or designation',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) {
                query = v;
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => findPeople(v),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Approximate spellings work when connected.',
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
            if (searching) const LinearProgressIndicator(),
            const SizedBox(height: 14),
            for (final p in people.where((p) => p['id'] != app.user?.id))
              Card(
                child: ListTile(
                  leading: ProfileAvatar(
                    name: p['name'] as String,
                    avatarId: p['avatarId'] as String? ?? '',
                  ),
                  title: Text(p['name'] as String),
                  subtitle: Text(
                    '${p['jobTitle'] ?? p['role']}\n${p['teamName'] ?? p['department'] ?? p['email']}${p['leadName'] == null ? '' : ' · Lead: ${p['leadName']}'}',
                  ),
                  isThreeLine: true,
                  trailing: const MotionIcon(Icons.chat_bubble_outline_rounded),
                  onTap: () => open(recipientId: p['id'] as String),
                ),
              ),
            if (!searching && people.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'No matching downloaded contacts. Try a name or department.',
                ),
              ),
          ] else ...[
            Text(
              'Messages, assignment responses and site time actions are saved locally before sending. A blocked action needs your attention; reports are retained.',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 14),
            if (pending.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                    'No unsent messages, responses or site time actions.',
                  ),
                ),
              ),
            for (final action in pending)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusPill(
                        action['blocked'] == 1
                            ? 'Needs attention'
                            : 'Queued on this phone',
                        color: action['blocked'] == 1
                            ? context.colors.danger
                            : context.colors.teal,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        action['kind'] == 'message'
                            ? (jsonDecode(action['payload'] as String)
                                      as Json)['text']
                                  as String
                            : action['kind'] == 'time'
                            ? 'Site time: ${(jsonDecode(action['payload'] as String) as Json)['action']}'
                            : 'Assignment response: ${(jsonDecode(action['payload'] as String) as Json)['decision']}',
                      ),
                      if (action['error'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            action['error'] as String,
                            style: TextStyle(
                              color: context.colors.danger,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        children: [
                          TextButton(
                            onPressed: () async {
                              try {
                                await controller.retryCollaboration(
                                  action['id'] as String,
                                );
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = e.toString());
                                }
                              }
                            },
                            child: const Text('Retry'),
                          ),
                          if (action['kind'] != 'time')
                            TextButton(
                              onPressed: () async {
                                final discard = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Discard this unsent action?',
                                    ),
                                    content: const Text(
                                      'This removes the unsent message or response from this phone. Saved reports are kept.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Keep'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Discard'),
                                      ),
                                    ],
                                  ),
                                );
                                if (discard == true) {
                                  try {
                                    await controller.discardCollaboration(
                                      action['id'] as String,
                                    );
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() => error = e.toString());
                                    }
                                  }
                                }
                              },
                              child: const Text('Discard'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});
  final String conversationId;
  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final composer = TextEditingController(), scroll = ScrollController();
  Timer? timer;
  bool loading = false, sending = false;
  String error = '', title = 'Conversation', readSequence = '';
  List<Json> messages = [];
  Json? conversation;
  String? nextBefore;
  @override
  void initState() {
    super.initState();
    Future.microtask(restore);
    timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        load(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool current(String? owner) =>
      mounted &&
      ref.read(appProvider).stage == AccessStage.ready &&
      ref.read(appProvider).user?.id == owner;
  Future<void> refreshAcknowledgedMessages() async {
    final owner = ref.read(appProvider).user?.id;
    try {
      final cached = await ref
          .read(appProvider.notifier)
          .collaboration
          .cachedThread(widget.conversationId);
      if (!current(owner) || cached == null) {
        return;
      }
      final rows = (cached['items'] as List).cast<Json>(),
          merged = <String, Json>{
            for (final m in messages) m['id'] as String: m,
            for (final m in rows) m['id'] as String: m,
          };
      final sorted = merged.values.toList()
        ..sort(
          (a, b) => BigInt.parse(
            a['sequence'] as String,
          ).compareTo(BigInt.parse(b['sequence'] as String)),
        );
      setState(() => messages = sorted);
    } catch (_) {
      /* The next foreground refresh retries the cached/server view. */
    }
  }

  Future<void> restore() async {
    try {
      final cached = await ref
          .read(appProvider.notifier)
          .collaboration
          .cachedThread(widget.conversationId);
      if (cached != null && mounted) {
        setState(() {
          messages = (cached['items'] as List).cast<Json>();
          conversation = cached['conversation'] as Json?;
          title = conversation?['title'] as String? ?? title;
          nextBefore = messages.length >= 50
              ? messages.first['sequence'] as String
              : cached['nextBefore'] as String?;
        });
      }
    } catch (_) {}
    await load();
  }

  Future<void> load({bool quiet = false, bool older = false}) async {
    if (loading) return;
    final owner = ref.read(appProvider).user?.id;
    setState(() => loading = true);
    try {
      final c = ref.read(appProvider.notifier);
      await c.assertAccess();
      final result = await c.collaboration.messages(
        widget.conversationId,
        before: older ? nextBefore : null,
        isCurrent: () => current(owner),
      );
      if (!current(owner)) return;
      final latest = (result['items'] as List).cast<Json>(),
          seen = {
            for (final m in messages) m['id'] as String: m,
            for (final m in latest) m['id'] as String: m,
          };
      final sorted = seen.values.toList()
        ..sort(
          (a, b) => BigInt.parse(
            a['sequence'] as String,
          ).compareTo(BigInt.parse(b['sequence'] as String)),
        );
      setState(() {
        messages = sorted;
        conversation = result['conversation'] as Json;
        title = conversation?['title'] as String? ?? title;
        if (older || nextBefore == null && messages.length <= 50) {
          nextBefore = result['nextBefore'] as String?;
        }
        error = '';
      });
      if (!older && latest.isNotEmpty) {
        final last = latest.last['sequence'] as String;
        if (readSequence != last &&
            (conversation?['unread'] as int? ?? 0) > 0 &&
            mounted &&
            ModalRoute.of(context)?.isCurrent == true) {
          readSequence = last;
          await c.readThread(widget.conversationId, last);
        }
        if (scroll.hasClients &&
            scroll.position.maxScrollExtent - scroll.offset < 180) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scroll.hasClients) {
              scroll.jumpTo(scroll.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (_) {
      if (mounted && !quiet) {
        setState(
          () => error =
              'Could not refresh. Downloaded messages and your encrypted outbox are retained.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final value = composer.text.trim();
    if (value.isEmpty || sending) return;
    setState(() {
      sending = true;
      error = '';
    });
    try {
      await ref
          .read(appProvider.notifier)
          .sendMessage(widget.conversationId, value);
      composer.clear();
      unawaited(load(quiet: true));
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Could not complete this message: $e');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appProvider.select((a) => a.collaboration.pending), (
      previous,
      next,
    ) {
      final currentIds = next.map((p) => p['id']).toSet();
      if ((previous ?? <Json>[]).any(
        (p) =>
            p['kind'] == 'message' &&
            p['route'] == 'conversations/${widget.conversationId}/messages' &&
            !currentIds.contains(p['id']),
      )) {
        unawaited(refreshAcknowledgedMessages());
      }
    });
    final app = ref.watch(appProvider), owner = app.user?.id;
    final sentIds = messages.map((m) => m['clientMessageId']).toSet();
    final pending = app.collaboration.pending
        .where(
          (p) =>
              p['kind'] == 'message' &&
              p['route'] == 'conversations/${widget.conversationId}/messages' &&
              !sentIds.contains(p['id']),
        )
        .toList();
    final participants = (conversation?['participants'] as List? ?? [])
        .cast<Json>();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh conversation',
            onPressed: loading ? null : () => load(),
            icon: const MotionIcon(Icons.sync_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ErrorNotice(error),
            ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                if (nextBefore != null)
                  TextButton(
                    onPressed: loading ? null : () => load(older: true),
                    child: const Text('Load earlier messages'),
                  ),
                if (messages.isEmpty && pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Start the conversation. Messages you send are encrypted on this phone before delivery.',
                    ),
                  ),
                for (final m in messages)
                  _MessageBubble(
                    text: m['text'] as String,
                    mine: m['senderId'] == owner,
                    by: m['senderId'] == owner
                        ? 'You'
                        : participants
                                      .where((p) => p['id'] == m['senderId'])
                                      .firstOrNull?['name']
                                  as String? ??
                              'Colleague',
                    status:
                        '${collaborationTime(m['createdAt'] as String?)}${m['senderId'] == owner ? ' · Sent' : ''}',
                  ),
                for (final p in pending)
                  _MessageBubble(
                    text:
                        (jsonDecode(p['payload'] as String) as Json)['text']
                            as String,
                    mine: true,
                    by: 'You',
                    status: p['blocked'] == 1
                        ? 'Needs attention · open Outbox'
                        : 'Queued · saved on this phone',
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.panel,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: context.colors.edge.withValues(alpha: .6),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: composer,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        hintText: 'Message your colleague…',
                        counterText: '',
                        fillColor: context.colors.panel,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      enabled: !sending,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    tooltip: 'Send message',
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: sending ? null : send,
                    icon: const MotionIcon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.mine,
    required this.by,
    required this.status,
  });
  final String text, by, status;
  final bool mine;
  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .82,
      ),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: mine
            ? context.colors.indigo.withValues(alpha: .12)
            : context.colors.panel,
        border: Border.all(color: context.colors.edge.withValues(alpha: .45)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(23),
          topRight: const Radius.circular(23),
          bottomLeft: Radius.circular(mine ? 23 : 6),
          bottomRight: Radius.circular(mine ? 6 : 23),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(by, style: TextStyle(fontSize: 11, color: context.colors.muted)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.6, fontSize: 15)),
          const SizedBox(height: 7),
          Text(
            status,
            style: TextStyle(fontSize: 10, color: context.colors.muted),
          ),
        ],
      ),
    ),
  );
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appProvider.select((a) => a.collaboration));
    return Scaffold(
      appBar: AppBar(
        title: Text('Alerts${data.unread > 0 ? ' (${data.unread})' : ''}'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(appProvider.notifier).refreshCollaboration(),
        child: ListView(
          padding: const EdgeInsets.all(22),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const WorkspaceIntro(
              title: 'Your updates',
              subtitle:
                  'Assignments, team messages and the things that need you.',
              icon: Icons.notifications_outlined,
            ),
            if (data.notifications.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No downloaded alerts. New assignments and messages appear here when connected.',
                  ),
                ),
              ),
            for (final n in data.notifications)
              Card(
                child: ListTile(
                  leading: MotionIcon(
                    n['kind'] == 'message.new'
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.assignment_outlined,
                    color: n['readAt'] == null
                        ? context.colors.indigo
                        : context.colors.muted,
                  ),
                  title: Text(n['title'] as String),
                  subtitle: Text(
                    '${n['body']}\n${collaborationTime(n['createdAt'] as String?)}${n['readAt'] == null ? ' · Unread' : ''}',
                  ),
                  isThreeLine: true,
                  onTap: () async {
                    try {
                      await ref
                          .read(appProvider.notifier)
                          .readAlert(n['id'] as String);
                      if (context.mounted) {
                        if (n['kind'] == 'message.new') {
                          context.push('/messages/${n['resourceId']}');
                        } else {
                          context.push('/jobs/${n['resourceId']}');
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                ),
              ),
            const SizedBox(height: 18),
            Text(
              'Showing your latest 100 downloaded alerts. New updates arrive while the app is open, unlocked and connected.',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
