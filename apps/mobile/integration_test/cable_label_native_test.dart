import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/label_scan/cable_label.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native OCR, field mapping and encrypted draft recovery',
    (tester) async {
      // An original synthetic bitmap, passed through the real native OCR bridge.
      // Camera hardware, OS permissions and physical airplane mode are excluded.
      const schemaBase64 = String.fromEnvironment(
        'CABLE_LABEL_TEST_SCHEMA_BASE64',
      );
      final raw = jsonDecode(utf8.decode(base64Decode(schemaBase64))) as Json;
      raw['schemaHash'] = FormDefinition.fromJson(raw).calculatedHash;
      raw['versionId'] = const Uuid().v4();
      raw['versionNumber'] = 4;
      final form = FormDefinition.fromJson(raw)..verifyHash();
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'cable_label_scan'),
      );
      await dir.create(recursive: true);
      final photo = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
      final recording = ui.PictureRecorder();
      final canvas = ui.Canvas(recording);
      canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      const lines = [
        'SYNTHETIC DEMO LABEL - NOT A REAL ASSET',
        'CABLE ID: CBL-2026-0042',
        'DRUM NO: DR-0017',
        'MANUFACTURED BY: DEMO CABLE WORKS',
        'BATCH NO: B2409-08',
        'CABLE TYPE: 24F SM G.652D',
        'FIBRE COUNT: 24',
        'LENGTH: 1000 m',
        'MANUFACTURE DATE: 2026-09-18',
      ];
      for (var i = 0; i < lines.length; i++) {
        final painter = TextPainter(
          text: TextSpan(
            text: lines[i],
            style: const TextStyle(color: ui.Color(0xff000000), fontSize: 32),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout(maxWidth: 1170);
        painter.paint(canvas, ui.Offset(55, 35 + i * 66));
        painter.dispose();
      }
      final picture = recording.endRecording();
      final bitmap = await picture.toImage(1280, 690);
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await photo.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      picture.dispose();
      bitmap.dispose();
      addTearDown(() async {
        if (await photo.exists()) await photo.delete();
      });
      final text = await const NativeLabelReader().read(photo.path);
      final patch = validLabelSuggestions(
        form,
        {},
        CableLabelReadout.parse(text),
      );
      expect(patch.length, 8, reason: text);
      expect(patch['label_cable_id']?.toJson(), 'CBL-2026-0042');
      expect(patch['label_drum_id']?.toJson(), 'DR-0017');
      expect(patch['label_manufacturer']?.toJson(), 'DEMO CABLE WORKS');
      expect(patch['label_batch']?.toJson(), 'B2409-08');
      expect(patch['label_specification']?.toJson(), '24F SM G.652D');
      expect(patch['label_fibre_count']?.toJson(), 24);
      expect(patch['label_declared_length']?.toJson(), {
        'amount': 1000.0,
        'unit': 'm',
      });
      expect(patch['label_manufactured_date']?.toJson(), '2026-09-18');
      final owner = 'synthetic-cable-ocr-${const Uuid().v4()}';
      const secrets = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );
      final repository = SecureReportRepository(secrets);
      addTearDown(repository.close);
      // Presence is bypassed only in this isolated storage integration test.
      await repository.open(owner, authorizePresence: false);
      final draft = await repository.create(form, const Uuid().v4());
      final values = <String, Answer?>{
        ...patch,
        'cable_installed': const QuantityAnswer(12, 'm'),
      };
      await repository.save(draft.id, values, source: 'camera_ocr_reviewed');
      await repository.close();
      await repository.open(owner, authorizePresence: false);
      final recovered = await repository.get(draft.id);
      expect(encodeAnswers(recovered.values), encodeAnswers(values));
      expect(
        (recovered.provenance['label_cable_id'] as List).last['source'],
        'camera_ocr_reviewed',
      );
      final root = await getApplicationSupportDirectory();
      final header = await File(
        p.join(root.path, 'accounts', owner, 'reports.db'),
      ).openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
      expect(header, isNot(utf8.encode('SQLite format 3\u0000')));
      await photo.delete();
      binding.reportData = {
        'scope':
            'Native OCR on a synthetic label and encrypted draft reopen; no camera hardware or physical network test',
        'platform': Platform.operatingSystem,
        'rawText': text,
        'mappedFields': encodeAnswers(patch),
        'installedLengthPreserved': true,
        'encryptedDraftRecovered': true,
        'reviewedProvenanceRetained': true,
        'temporaryPhotoDeleted': !await photo.exists(),
      };
      debugPrint('CABLE_NATIVE_EVIDENCE ${jsonEncode(binding.reportData)}');
      await repository.close();
      // Delete only this run's isolated test data, never the demo account.
      await Directory(
        p.join(root.path, 'accounts', owner),
      ).delete(recursive: true);
      await secrets.delete(key: 'database-key:$owner');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
