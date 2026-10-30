import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      final label = Platform.environment['STUDIO_PROFILE_LABEL'] ?? 'latest';
      final file = File('artifacts/studio-performance-$label.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    },
  );
}
