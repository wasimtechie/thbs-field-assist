import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/contracts.dart';

abstract interface class LabelReader {
  Future<String> read(String path);
  Future<void> cancel();
}

class NativeLabelReader implements LabelReader {
  const NativeLabelReader();
  static const channel = MethodChannel('field_assist/label_ocr');
  @override
  Future<String> read(String path) async {
    try {
      return (await channel
              .invokeMethod<String>('recognize', {'path': path})
              .timeout(const Duration(seconds: 30))) ??
          '';
    } on TimeoutException {
      throw const FormatException(
        'Reading took too long. Retake the photo or enter the details manually.',
      );
    } finally {
      await cancel();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } catch (_) {
      /* Native request already stopped. */
    }
  }
}

/// Only explicitly configured, visible form fields participate. Label text is
/// untrusted data, never a prompt or instruction for the voice agent.
List<FieldDefinition> scannableFields(
  FormDefinition form,
  Answers existing, {
  String? sectionId,
}) => form
    .visibleFields(existing)
    .where(
      (f) =>
          f.scanTarget != null &&
          (sectionId == null || f.sectionId == sectionId),
    )
    .toList();

class CableLabelReadout {
  CableLabelReadout(this.rawText, this.values, this.ambiguous);
  final String rawText;
  final Map<String, String> values;
  final Set<String> ambiguous;
  static final labels = <String, String>{
    'cable_id':
        r'cable\s*(?:part\s*)?(?:id|no\.?|number|serial(?:\s*(?:no\.?|number))?)',
    'drum_id':
        r'(?:drum|reel)\s*(?:id|no\.?|number|serial(?:\s*(?:no\.?|number))?)',
    'manufacturer':
        r'(?:manufactured\s+by|manufacturer|mfd\.?\s+by|mfr\.?|make)',
    'batch': r'(?:batch|lot)\s*(?:id|no\.?|number)?',
    'specification':
        r'(?:cable\s*(?:type|specification|spec)|specification|construction)',
    'fibre_count':
        r'(?:(?:fibre|fiber)\s*(?:count|quantity)|(?:no\.?\s*of\s*)?cores)',
    'declared_length': r'(?:(?:cable|drum|reel|printed|nominal)\s*)?length',
    'manufactured_date':
        r'(?:(?:manufacture|manufacturing|manufactured|mfg\.?|mfd\.?)\s*date|date\s*of\s*manufacture)',
  };

  factory CableLabelReadout.parse(String text) {
    final found = <String, Set<String>>{};
    final lines = text
        .substring(0, text.length.clamp(0, 32000).toInt())
        .split(RegExp(r'[\r\n;|]+'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    final anyLabel = RegExp(
      '^(?:${labels.values.join('|')})(?:\\s*[:#=–-]\\s*|\\s+|\$)',
      caseSensitive: false,
    );
    for (final entry in labels.entries) {
      final pattern = RegExp(
        '^${entry.value}(?:\\s*[:#=–-]\\s*|\\s+|\$)(.*)\$',
        caseSensitive: false,
      );
      for (var i = 0; i < lines.length; i++) {
        final match = pattern.firstMatch(lines[i]);
        if (match == null) continue;
        var value = match.group(1)!.trim();
        if (value.isEmpty &&
            i + 1 < lines.length &&
            !anyLabel.hasMatch(lines[i + 1])) {
          value = lines[i + 1];
        }
        value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
        // A merged OCR row with multiple labels is uncertain; don't copy one
        // field's label/value into another field.
        final embedded = RegExp(
          '(?:${labels.values.join('|')})\\s*[:#=]',
          caseSensitive: false,
        );
        if (value.isNotEmpty &&
            value.length <= 160 &&
            !embedded.hasMatch(value)) {
          found.putIfAbsent(entry.key, () => {}).add(value);
        }
      }
    }
    return CableLabelReadout(
      text,
      {
        for (final e in found.entries)
          if (e.value.length == 1) e.key: e.value.single,
      },
      {
        for (final e in found.entries)
          if (e.value.length > 1) e.key,
      },
    );
  }
}

/// No inferred installation outcome, installed length or manufacturer lookup.
/// IDs keep their original OCR spelling (including O/0 and I/1).
Answer? decodeLabelEntry(FieldDefinition field, String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  switch (field.scanTarget) {
    case 'fibre_count':
      final m = RegExp(
        r'^(\d{1,4})(?:\s*(?:f|fibres?|fibers?|cores?))?$',
        caseSensitive: false,
      ).firstMatch(value);
      if (m == null) return null;
      return NumberAnswer(int.parse(m.group(1)!));
    case 'declared_length':
      final m = RegExp(
        r'^(\d+(?:\.\d+)?)\s*(km|m|kilometres?|kilometers?|metres?|meters?)$',
        caseSensitive: false,
      ).firstMatch(value);
      if (m == null) {
        return null; // Missing unit and comma-decimal/grouping are ambiguous.
      }
      var amount = double.parse(m.group(1)!);
      var unit = m.group(2)!.toLowerCase().startsWith('k') ? 'km' : 'm';
      if (!field.units.contains(unit)) {
        final target = field.canonicalUnit;
        if (target == 'm' && unit == 'km') {
          amount *= 1000;
          unit = 'm';
        } else if (target == 'km' && unit == 'm') {
          amount /= 1000;
          unit = 'km';
        } else {
          return null;
        }
      }
      return amount.isFinite ? QuantityAnswer(amount, unit) : null;
    case 'manufactured_date':
      final m = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})$').firstMatch(value);
      if (m == null) return null;
      final year = int.parse(m.group(1)!),
          month = int.parse(m.group(2)!),
          day = int.parse(m.group(3)!);
      final date = DateTime.utc(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return TextAnswer('${m.group(1)}-${m.group(2)}-${m.group(3)}');
    case 'cable_id':
    case 'drum_id':
    case 'manufacturer':
    case 'batch':
    case 'specification':
      return TextAnswer(value);
    default:
      return null;
  }
}

Answers validLabelSuggestions(
  FormDefinition form,
  Answers existing,
  CableLabelReadout readout,
) {
  final patch = <String, Answer?>{};
  for (final field in scannableFields(form, existing)) {
    final raw = readout.values[field.scanTarget];
    if (raw == null) continue;
    final value = decodeLabelEntry(field, raw);
    if (value != null &&
        !validate(form, {
          ...existing,
          field.id: value,
        }, requireComplete: false).issues.any((i) => i.fieldId == field.id)) {
      patch[field.id] = value;
    }
  }
  return patch;
}
