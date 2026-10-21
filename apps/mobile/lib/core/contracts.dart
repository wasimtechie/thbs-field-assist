import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:json_canonicalizer/json_canonicalizer.dart';

typedef Json = Map<String, dynamic>;

enum FieldKind {
  shortText,
  longText,
  integer,
  decimal,
  quantity,
  boolean,
  singleSelect,
  date,
}

const _kinds = {
  'short_text': FieldKind.shortText,
  'long_text': FieldKind.longText,
  'integer': FieldKind.integer,
  'decimal': FieldKind.decimal,
  'quantity': FieldKind.quantity,
  'boolean': FieldKind.boolean,
  'single_select': FieldKind.singleSelect,
  'date': FieldKind.date,
};

sealed class Answer {
  const Answer();
  Object? toJson();
  static Answer? decode(Object? value) => switch (value) {
    null => null,
    String v => TextAnswer(v),
    bool v => BoolAnswer(v),
    num v => NumberAnswer(v),
    Map<String, dynamic> v
        when v['amount'] is num &&
            v['unit'] is String &&
            v.keys.every((k) => k == 'amount' || k == 'unit') =>
      QuantityAnswer(v['amount'] as num, v['unit'] as String),
    _ => throw const FormatException('Unsupported field value'),
  };
}

final class TextAnswer extends Answer {
  const TextAnswer(this.value);
  final String value;
  @override
  String toJson() => value;
}

final class BoolAnswer extends Answer {
  const BoolAnswer(this.value);
  final bool value;
  @override
  bool toJson() => value;
}

final class NumberAnswer extends Answer {
  const NumberAnswer(this.value);
  final num value;
  @override
  num toJson() => value;
}

final class QuantityAnswer extends Answer {
  const QuantityAnswer(this.amount, this.unit);
  final num amount;
  final String unit;
  @override
  Json toJson() => {'amount': amount, 'unit': unit};
}

typedef Answers = Map<String, Answer?>;
Answers decodeAnswers(Json json) => Map.unmodifiable(
  json.map((key, value) => MapEntry(key, Answer.decode(value))),
);
Json encodeAnswers(Answers values) =>
    values.map((key, value) => MapEntry(key, value?.toJson()));
bool missing(Answer? v) =>
    v == null || v is TextAnswer && v.value.trim().isEmpty;

class Choice {
  const Choice(this.id, this.label);
  final String id, label;
  factory Choice.fromJson(Json j) =>
      Choice(j['id'] as String, j['label'] as String);
}

class FormSection {
  const FormSection(this.id, this.label, this.order);
  final String id, label;
  final int order;
  factory FormSection.fromJson(Json j) =>
      FormSection(j['id'] as String, j['label'] as String, j['order'] as int);
}

class VisibilityCondition {
  const VisibilityCondition(this.fieldId, this.operator, this.value);
  final String fieldId, operator;
  final Object value;
  factory VisibilityCondition.fromJson(Json j) {
    if (!['equals', 'in'].contains(j['operator'])) {
      throw const FormatException('Unsupported visibility condition');
    }
    return VisibilityCondition(
      j['fieldId'] as String,
      j['operator'] as String,
      j['value'] as Object,
    );
  }
}

class FieldDefinition {
  FieldDefinition.fromJson(Json j)
    : id = j['id'] as String,
      sectionId = j['sectionId'] as String,
      label = j['label'] as String,
      order = j['order'] as int,
      kind =
          _kinds[j['type']] ??
          (throw const FormatException('Unsupported field type')),
      required = j['required'] as bool,
      options = List.unmodifiable(
        ((j['options'] as List?) ?? []).map((v) => Choice.fromJson(v as Json)),
      ),
      units = List.unmodifiable(
        ((j['units'] as Json?)?['allowed'] as List?)?.cast<String>() ?? [],
      ),
      canonicalUnit = (j['units'] as Json?)?['canonical'] as String?,
      scanTarget = (j['scan'] as Json?)?['target'] as String?,
      constraints = Map.unmodifiable((j['constraints'] as Json?) ?? {}),
      condition = j['condition'] == null
          ? null
          : VisibilityCondition.fromJson(j['condition'] as Json),
      voiceEnabled = (j['voice'] as Json)['enabled'] as bool,
      question = (j['voice'] as Json)['question'] as String,
      description = (j['voice'] as Json)['description'] as String,
      source = Map.unmodifiable(j);
  final String id, sectionId, label, question, description;
  final int order;
  final FieldKind kind;
  final bool required, voiceEnabled;
  final List<Choice> options;
  final List<String> units;
  final String? canonicalUnit;
  final String? scanTarget;
  final Json constraints, source;
  final VisibilityCondition? condition;
  String display(Answer? v) => switch (v) {
    null => 'Not provided',
    TextAnswer(:final value) =>
      kind == FieldKind.singleSelect
          ? options.where((o) => o.id == value).firstOrNull?.label ?? value
          : value,
    BoolAnswer(:final value) => value ? 'Yes' : 'No',
    NumberAnswer(:final value) => '$value',
    QuantityAnswer(:final amount, :final unit) => '$amount $unit',
  };
}

class FormDefinition {
  FormDefinition.fromJson(Json j)
    : templateId = j['templateId'] as String,
      typeId = j['engineerTypeId'] as String,
      title = j['title'] as String,
      versionId = j['versionId'] as String? ?? '',
      versionNumber = j['versionNumber'] as int? ?? 0,
      hash = j['schemaHash'] as String? ?? '',
      sections = List.unmodifiable(
        (j['sections'] as List).map((s) => FormSection.fromJson(s as Json)),
      ),
      fields = List.unmodifiable(
        (j['fields'] as List).map((f) => FieldDefinition.fromJson(f as Json)),
      ),
      source = Map.unmodifiable(j) {
    if (j['schemaFormatVersion'] != 1 ||
        fields.length > 30 ||
        sections.isEmpty ||
        sections.length > 6 ||
        fields.map((f) => f.id).toSet().length != fields.length) {
      throw const FormatException('Unsupported form schema');
    }
    final scanTargets = <String>{};
    for (final f in fields) {
      final target = f.scanTarget;
      if (target != null) {
        const textTargets = [
          'cable_id',
          'drum_id',
          'manufacturer',
          'batch',
          'specification',
        ];
        final expected = textTargets.contains(target)
            ? FieldKind.shortText
            : target == 'fibre_count'
            ? FieldKind.integer
            : target == 'declared_length'
            ? FieldKind.quantity
            : target == 'manufactured_date'
            ? FieldKind.date
            : null;
        if (expected == null ||
            f.kind != expected ||
            !scanTargets.add(target) ||
            (f.source['scan'] as Json)['kind'] != 'cable_label' ||
            target == 'declared_length' &&
                (f.units.isEmpty ||
                    f.units.any((u) => !['m', 'km'].contains(u)))) {
          throw const FormatException('Unsupported cable scan field mapping');
        }
      }
      if (!sections.any((s) => s.id == f.sectionId) || f.options.length > 20) {
        throw const FormatException('Invalid form structure');
      }
      final seen = <String>{f.id};
      var c = f.condition;
      while (c != null) {
        final parent = fields.where((f) => f.id == c!.fieldId).firstOrNull;
        if (parent == null || !seen.add(parent.id)) {
          throw const FormatException('Invalid visibility reference');
        }
        if (c.operator == 'in' &&
            (parent.kind != FieldKind.singleSelect ||
                c.value is! List ||
                (c.value as List).isEmpty ||
                !(c.value as List).every(
                  (v) => parent.options.any((o) => o.id == v),
                ))) {
          throw const FormatException('Invalid membership condition');
        }
        if (c.operator == 'equals' &&
            (parent.kind == FieldKind.boolean
                ? c.value is! bool
                : parent.kind == FieldKind.singleSelect
                ? !parent.options.any((o) => o.id == c!.value)
                : true)) {
          throw const FormatException('Invalid equality condition');
        }
        c = parent.condition;
      }
    }
  }
  final String templateId, typeId, title, versionId, hash;
  final int versionNumber;
  final List<FormSection> sections;
  final List<FieldDefinition> fields;
  final Json source;
  Json get canonicalSchema => {
    for (final key in [
      'schemaFormatVersion',
      'templateId',
      'engineerTypeId',
      'title',
      'sections',
      'fields',
    ])
      key: source[key],
  };
  String get calculatedHash =>
      sha256.convert(canonicalizeUtf8(canonicalSchema)).toString();
  void verifyHash() {
    if (hash.isEmpty || hash != calculatedHash) {
      throw const FormatException('Template integrity check failed');
    }
  }

  bool visible(FieldDefinition f, Answers values) {
    final c = f.condition;
    if (c == null) return true;
    final parent = fields.firstWhere((f) => f.id == c.fieldId);
    if (!visible(parent, values)) return false;
    final value = values[c.fieldId]?.toJson();
    return c.operator == 'equals'
        ? value == c.value
        : (c.value as List).contains(value);
  }

  List<FieldDefinition> visibleFields(Answers values) =>
      fields.where((f) => visible(f, values)).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
}

class ValidationIssue {
  const ValidationIssue(this.fieldId, this.code, this.message);
  final String fieldId, code, message;
}

class ValidationResult {
  const ValidationResult(this.values, this.issues, this.excluded);
  final Answers values;
  final List<ValidationIssue> issues;
  final List<String> excluded;
  bool get valid => issues.isEmpty;
}

bool _validDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  return d != null && d.toIso8601String().startsWith(s);
}

ValidationResult validate(
  FormDefinition schema,
  Answers values, {
  bool requireComplete = true,
}) {
  final issues = <ValidationIssue>[];
  final included = <String, Answer?>{};
  final excluded = <String>[];
  for (final key in values.keys) {
    if (!schema.fields.any((f) => f.id == key)) {
      issues.add(ValidationIssue(key, 'UNKNOWN_FIELD', 'Unknown field.'));
    }
  }
  for (final f in schema.fields) {
    if (!schema.visible(f, values)) {
      if (!missing(values[f.id])) excluded.add(f.id);
      continue;
    }
    var v = values[f.id];
    void error(String code, String text) =>
        issues.add(ValidationIssue(f.id, code, text));
    if (missing(v)) {
      if (requireComplete && f.required) {
        error('REQUIRED', '${f.label} is required.');
      }
      continue;
    }
    if (v is TextAnswer) v = TextAnswer(v.value.trim());
    num? numeric;
    switch (f.kind) {
      case FieldKind.shortText:
      case FieldKind.longText:
        if (v is! TextAnswer) {
          error('INVALID_TYPE', 'Enter text.');
        } else if (v.value.length >
            ((f.constraints['maxLength'] as num?) ??
                (f.kind == FieldKind.shortText ? 160 : 500))) {
          error('TOO_LONG', 'Text exceeds maximum length.');
        }
      case FieldKind.integer:
      case FieldKind.decimal:
        if (v is! NumberAnswer ||
            !v.value.isFinite ||
            f.kind == FieldKind.integer &&
                v.value != v.value.truncateToDouble()) {
          error('INVALID_TYPE', 'Enter a valid number.');
        } else {
          numeric = v.value;
        }
      case FieldKind.quantity:
        if (v is! QuantityAnswer || !v.amount.isFinite) {
          error('INVALID_TYPE', 'Enter an amount and unit.');
        } else if (!f.units.contains(v.unit)) {
          error('UNSUPPORTED_UNIT', 'Select an allowed unit.');
        } else {
          numeric = v.amount;
        }
      case FieldKind.boolean:
        if (v is! BoolAnswer) error('INVALID_TYPE', 'Choose yes or no.');
      case FieldKind.singleSelect:
        if (v is! TextAnswer || !f.options.any((o) => o.id == v!.toJson())) {
          error('INVALID_OPTION', 'Choose an allowed option.');
        }
      case FieldKind.date:
        if (v is! TextAnswer || !_validDate(v.value)) {
          error('INVALID_DATE', 'Use a valid YYYY-MM-DD date.');
        } else if (f.constraints['minDate'] != null &&
                v.value.compareTo(f.constraints['minDate'] as String) < 0 ||
            f.constraints['maxDate'] != null &&
                v.value.compareTo(f.constraints['maxDate'] as String) > 0) {
          error('OUT_OF_RANGE', 'Date is outside the allowed range.');
        }
    }
    if (numeric != null) {
      final min = f.constraints['min'] as num?,
          max = f.constraints['max'] as num?,
          precision = f.constraints['precision'] as int?;
      if (min != null && numeric < min || max != null && numeric > max) {
        error('OUT_OF_RANGE', 'Number is outside the allowed range.');
      }
      if (precision != null) {
        final scaled = numeric * math.pow(10, precision);
        if ((scaled - scaled.round()).abs() > 1e-7) {
          error('INVALID_PRECISION', 'Use at most $precision decimal places.');
        }
      }
    }
    included[f.id] = v;
  }
  return ValidationResult(
    Map.unmodifiable(included),
    List.unmodifiable(issues),
    List.unmodifiable(excluded),
  );
}

QuantityAnswer convertQuantity(QuantityAnswer value, String canonical) {
  if (value.unit == canonical) return value;
  const factors = {'Gbps:Mbps': 1000.0, 'Mbps:Gbps': 0.001};
  final factor = factors['${value.unit}:$canonical'];
  if (factor == null) throw const FormatException('UNSUPPORTED_UNIT');
  return QuantityAnswer(value.amount * factor, canonical);
}

enum ReportState { draft, queued, syncing, accepted, needsAttention }

String stateName(ReportState state) =>
    state == ReportState.needsAttention ? 'needs_attention' : state.name;
ReportState parseState(String s) =>
    ReportState.values.firstWhere((v) => stateName(v) == s);
ReportState transition(ReportState state, String event) {
  final next = {
    'draft:confirm': ReportState.queued,
    'queued:upload': ReportState.syncing,
    'syncing:receipt': ReportState.accepted,
    'syncing:transient': ReportState.queued,
    'syncing:rejected': ReportState.needsAttention,
    'needs_attention:retry': ReportState.queued,
    'needs_attention:fenced_reopen': ReportState.draft,
    'queued:fenced_reopen': ReportState.draft,
  }['${stateName(state)}:$event'];
  if (next == null) throw StateError('INVALID_TRANSITION');
  return next;
}

class EngineerIdentity {
  const EngineerIdentity({
    this.avatarId = '',
    required this.id,
    required this.name,
    required this.email,
    required this.organizationId,
    required this.typeId,
    required this.typeName,
    required this.assignmentRevision,
  });
  final String id, name, email, organizationId, typeId, typeName, avatarId;
  final int assignmentRevision;
  factory EngineerIdentity.fromJson(Json j) {
    if (j['role'] != 'ENGINEER') {
      throw const FormatException('Use an engineer account in this app.');
    }
    final type = j['engineerType'] as Json?;
    return EngineerIdentity(
      avatarId: j['avatarId'] as String? ?? '',
      id: j['id'] as String,
      name: j['name'] as String,
      email: j['email'] as String,
      organizationId: j['organizationId'] as String,
      typeId: type?['id'] as String? ?? '',
      typeName: type?['name'] as String? ?? 'Unassigned',
      assignmentRevision: j['assignmentRevision'] as int? ?? 0,
    );
  }
  Json toJson() => {
    'avatarId': avatarId,
    'id': id,
    'name': name,
    'email': email,
    'organizationId': organizationId,
    'engineerType': {'id': typeId, 'name': typeName},
    'assignmentRevision': assignmentRevision,
    'role': 'ENGINEER',
  };
}

class ReportLocation {
  const ReportLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.capturedAt,
    required this.isMocked,
  });
  final double latitude, longitude, accuracyMeters;
  final DateTime capturedAt;
  final bool isMocked;
  factory ReportLocation.fromJson(Json j) {
    final lat = j['latitude'],
        lon = j['longitude'],
        accuracy = j['accuracyMeters'];
    final time = j['capturedAt'];
    if (lat is! num ||
        lon is! num ||
        accuracy is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        !accuracy.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180 ||
        accuracy < 0 ||
        accuracy > 100000 ||
        time is! String ||
        !time.endsWith('Z') ||
        DateTime.tryParse(time) == null ||
        j['isMocked'] is! bool) {
      throw const FormatException('Invalid report location.');
    }
    return ReportLocation(
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      accuracyMeters: accuracy.toDouble(),
      capturedAt: DateTime.parse(time).toUtc(),
      isMocked: j['isMocked'] as bool,
    );
  }
  void requireFresh(DateTime now) {
    // Re-validate even locations constructed directly by an integration client.
    ReportLocation.fromJson(toJson());
    final age = now.toUtc().difference(capturedAt).inMilliseconds;
    if (age < -30000 || age > 60000) {
      throw const FormatException(
        'Capture a fresh location before confirming.',
      );
    }
  }

  Json toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'isMocked': isMocked,
  };
}

class LocalReport {
  const LocalReport({
    required this.id,
    required this.ownerId,
    required this.schema,
    required this.values,
    required this.state,
    required this.revision,
    required this.entitlementId,
    required this.updatedAt,
    this.frozen,
    this.payloadHash,
    this.attemptId,
    this.receipt,
    this.lastError,
    this.provenance = const {},
    this.retryCount = 0,
    this.nextRetryAt,
    this.workOrderId,
    this.workOrderAssignmentRevision,
  });
  final String id, ownerId, entitlementId;
  final FormDefinition schema;
  final Answers values;
  final ReportState state;
  final int revision, retryCount;
  final DateTime updatedAt;
  final String? frozen, payloadHash, attemptId, lastError;
  final String? workOrderId;
  final int? workOrderAssignmentRevision;
  final Json? receipt;
  final Json provenance;
  final DateTime? nextRetryAt;
  ReportLocation? get location {
    if (frozen == null) return null;
    final raw = (jsonDecode(frozen!) as Json)['location'];
    return raw == null ? null : ReportLocation.fromJson(raw as Json);
  }

  factory LocalReport.fromRow(Json r) => LocalReport(
    id: r['id'] as String,
    workOrderId: r['work_order_id'] as String?,
    workOrderAssignmentRevision: r['work_order_assignment_revision'] as int?,
    ownerId: r['owner_id'] as String,
    schema: FormDefinition.fromJson(
      jsonDecode(r['schema_json'] as String) as Json,
    ),
    values: decodeAnswers(jsonDecode(r['values_json'] as String) as Json),
    state: parseState(r['state'] as String),
    revision: r['revision'] as int,
    entitlementId: r['entitlement_id'] as String,
    updatedAt: DateTime.parse(r['updated_at'] as String),
    frozen: r['frozen'] as String?,
    payloadHash: r['payload_hash'] as String?,
    attemptId: r['attempt_id'] as String?,
    receipt: r['receipt_json'] == null
        ? null
        : jsonDecode(r['receipt_json'] as String) as Json,
    lastError: r['last_error'] as String?,
    provenance: jsonDecode(r['provenance_json'] as String) as Json,
    retryCount: r['retry_count'] as int,
    nextRetryAt: r['next_retry_at'] == null
        ? null
        : DateTime.parse(r['next_retry_at'] as String),
  );
}
