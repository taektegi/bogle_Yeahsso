import 'dart:io';
import 'dart:convert';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File(
        'artifacts/studio-verification.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
    onScreenshot: (name, bytes, [args]) async {
      final file = File('artifacts/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
