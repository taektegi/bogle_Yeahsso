import 'dart:async';
import 'package:flutter/material.dart';

import 'data/app_services.dart';
import 'data/local_store.dart';
import 'widgets/bogle_dialog.dart';
import 'drawing/studio_draft.dart';
import 'screens/startup_screen.dart';
import 'theme/bogle_theme.dart';

class BogleApp extends StatefulWidget {
  const BogleApp({super.key, this.services});

  /// Where the app's data comes from; [AppServices.local] when not given.
  /// The API-backed services go in here.
  final AppServices? services;

  @override
  State<BogleApp> createState() => _BogleAppState();
}

class _BogleAppState extends State<BogleApp> with WidgetsBindingObserver {
  late final AppServices _services = widget.services ?? AppServices.local();
  final _navigator = GlobalKey<NavigatorState>();
  final _recoveries = <String, Future<bool>>{};
  Future<void> _recoveryQueue = Future.value();

  Future<bool> _recoverDocument(String name) => _recoveries[name] ??= () async {
    final previous = _recoveryQueue;
    final done = Completer<void>();
    _recoveryQueue = done.future;
    try {
      await previous;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _navigator.currentContext == null) return false;
      final label = switch (name) {
        'characters' => '캐릭터와 돌봄 기록',
        'orders' => '주문·배송지·결제수단',
        'sketchbook' => '스케치북 초안',
        'profile' => '프로필',
        _ when name.startsWith('conversation-') => '이 친구와의 대화 기록',
        _ => '저장 정보',
      };
      return await showDialog<bool>(
            context: _navigator.currentContext!,
            barrierDismissible: false,
            builder: (context) => BogleDialog(
              title: '저장 정보를 복구하지 못했어요',
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('나중에'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('원본 보관 후 새로 시작'),
                ),
              ],
              child: Text(
                '$label 정보를 원본과 백업에서 모두 읽지 못했어요.\n\n새로 시작하면 해당 정보가 초기화돼요. 손상된 원본은 기기에 별도로 보관하며, 다른 정보와 캐릭터 그림 파일은 지우지 않아요.',
              ),
            ),
          ) ??
          false;
    } finally {
      done.complete();
      _recoveries.remove(name);
    }
  }();

  late final _studioDraft = StudioDraft(store: _services.draftStore);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final store = _services.draftStore;
    if (store is FileStore) store.onRecovery = _recoverDocument;
    // Bring in what the iPad doesn't have and send what the service hasn't
    // heard, without holding up the app.
    _services.sync?.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _services.sync?.resumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final store = _services.draftStore;
    if (store is FileStore) store.onRecovery = null;
    _studioDraft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: '보글',
      debugShowCheckedModeBanner: false,
      theme: buildBogleTheme(),
      builder: (context, child) => StudioDraftScope(
        draft: _studioDraft,
        child: AppServicesScope(services: _services, child: child!),
      ),
      home: StartupScreen(repository: _services.characters),
    );
  }
}
