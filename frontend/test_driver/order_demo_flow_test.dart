import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final folder = Directory('artifacts/order-demo');
  await folder.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${folder.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      await File(
        '${folder.path}/verification.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}
