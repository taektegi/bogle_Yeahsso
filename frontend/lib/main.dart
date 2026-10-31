import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/data/api/api_client.dart';
import 'src/data/app_services.dart';
import 'src/data/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // With BOGLE_API_URL (see ApiConfig) the app uses the service; without
  // it, everything stays on the device.
  final config = ApiConfig.fromEnvironment();
  // What the app keeps between launches lives in its own folder.
  final store = FileStore(
    Directory('${(await getApplicationSupportDirectory()).path}/bogle'),
  );
  runApp(
    BogleApp(
      services: config == null
          ? AppServices.local(store: store)
          : AppServices.remote(config, store: store),
    ),
  );
}
