import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import 'compact_closure_screen.dart' show summaryReceiptLabels;

/// Displays the immutable confirmed payload, never the editable draft.
class VisitSummaryReceiptScreen extends ConsumerWidget {
  const VisitSummaryReceiptScreen({super.key, required this.summaryId});
  final String summaryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final entry = app.summarySubmissions
        .where((e) => e['id'] == summaryId)
        .firstOrNull;
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visit summary')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/queue'),
            child: const Text('Open Reports'),
          ),
        ),
      );
    }
    final payload = entry['payload'] as Json;
    final values = payload['values'] as Json;
    final delivered = entry['status'] == 'received';
    final attention = entry['status'] == 'attention';
    final serverReceipt = entry['receipt'] as Json?;
    final completed = values['claimed_outcome'] == 'completed';
    void done() => context.go(completed ? '/jobs?view=completed' : '/jobs');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Visit summary receipt'),
          automaticallyImplyLeading: false,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(onPressed: done, child: const Text('Done')),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.task_alt, size: 48),
            const SizedBox(height: 16),
            Text(
              delivered
                  ? 'Visit summary submitted'
                  : attention
                  ? 'Submitted on device · Sync needs attention'
                  : 'Saved on this device · Waiting to sync',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SelectableText('Device confirmation: ${entry['id']}'),
            const SizedBox(height: 12),
            Text(
              completed
                  ? 'Visit completed. Find it in My jobs → Completed. Supervisor approval is tracked separately.'
                  : 'Visit recorded. The outstanding work remains in My jobs.',
            ),
            const SizedBox(height: 12),
            Text(
              delivered
                  ? 'Dashboard → Submissions → Visit summaries'
                  : 'Submitted offline and stored in encrypted storage. Delivery resumes when connected. You can leave this screen safely.',
            ),
            if (delivered && serverReceipt != null)
              SelectableText('Receipt: ${serverReceipt['id']}'),
            if (attention && entry['error'] != null)
              Text(entry['error'] as String),
            if (!delivered)
              TextButton.icon(
                onPressed: app.busy
                    ? null
                    : () => ref.read(appProvider.notifier).synchronize(),
                icon: const Icon(Icons.sync),
                label: const Text('Retry sync'),
              ),
            TextButton(
              onPressed: () => context.go('/queue'),
              child: const Text('View in Reports'),
            ),
            const SizedBox(height: 16),
            for (final field in summaryReceiptLabels(values).entries)
              Card(
                child: ListTile(
                  title: Text(field.value),
                  subtitle: Text(
                    values[field.key] is bool
                        ? values[field.key] == true
                              ? 'Yes'
                              : 'No'
                        : values[field.key]?.toString().replaceAll('_', ' ') ??
                              'Not provided',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
