import '../../core/contracts.dart';

const fttpTemplateId = '40000000-0000-4000-8000-000000000005';
const evidenceStages = ['before', 'installation', 'test', 'blocker'];
const evidenceLabels = {
  'before': 'Before work',
  'installation': 'Installed equipment',
  'test': 'Test result',
  'blocker': 'Blocker / access issue',
};
List<String> fttpIssues(
  String templateId,
  Answers answers,
  List<Json> evidence,
) {
  if (templateId != fttpTemplateId) return [];
  final values = encodeAnswers(answers);
  final issues = <String>[];
  final outcome = values['installation_outcome'];
  if (outcome == 'completed') {
    for (final entry in {
      'access_confirmed': 'Site access',
      'route_agreed': 'Agreed route',
      'site_checks': 'Site checks',
      'customer_handover': 'Customer handover',
      'site_tidy': 'Site left tidy',
    }.entries) {
      if (values[entry.key] != true) {
        issues.add(
          '${entry.value} must be confirmed for a completed installation.',
        );
      }
    }
    if (values['connectivity_test'] != 'passed') {
      issues.add(
        'A completed installation needs a recorded passing connectivity test.',
      );
    }
    for (final stage in ['before', 'installation', 'test']) {
      if (!evidence.any((e) => e['stage'] == stage)) {
        issues.add('Add $stage evidence before completing this installation.');
      }
    }
  } else if (outcome == 'blocked' || outcome == 'partial') {
    for (final field in ['exception_reason', 'next_team', 'next_action']) {
      if (values[field] is! String ||
          (values[field] as String).trim().isEmpty) {
        issues.add('Record the blocker, next team and next action.');
      }
    }
    if (!evidence.any((e) => e['stage'] == 'blocker')) {
      issues.add('Add blocker evidence for the receiving team.');
    }
  }
  return issues.toSet().toList();
}
