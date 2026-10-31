import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'api/api_services.dart';
import 'api/api_window_views.dart';
import 'api/device_art.dart';
import 'api/outbox.dart';
import 'api/synced_character_repository.dart';
import 'character_generation.dart';
import 'character_repository.dart';
import 'chat_service.dart';
import 'conversation_archive.dart';
import 'local_store.dart';
import 'motion_service.dart';
import 'order_repository.dart';
import 'profile_repository.dart';
import 'window_view_service.dart';

/// Everything the app reads and writes, chosen once in `app.dart`. Each part
/// is an interface, and the iPad is where the app's data lives: friends,
/// their pictures, care and memories, the profile and orders are kept in its
/// storage either way. [AppServices.remote] adds the character service for
/// what only it can do (making a friend from a drawing and chat)
/// and keeps its copy in step ([sync]).
class AppServices {
  AppServices({
    required this.characters,
    required this.profile,
    required this.orders,
    required this.generator,
    required this.chat,
    required this.motion,
    this.sync,
    this.windowViews,
    this.draftStore,
    ConversationArchive? conversations,
  }) : conversations = conversations ?? ConversationArchive(store: draftStore);

  /// No server: the starter friends, a new profile, no orders, the child's
  /// own picture as a new friend, scripted chat, and motion clips only when
  /// a motion server is configured (`MOTION_SERVER`). Any part given
  /// replaces its local one.
  ///
  /// With a [store] everything is kept across launches; without one, for
  /// the session.
  factory AppServices.local({
    FileStore? store,
    CharacterRepository? characters,
    ProfileRepository? profile,
    OrderRepository? orders,
    CharacterGenerator? generator,
    ChatService? chat,
    MotionService? motion,
  }) => AppServices(
    draftStore: store,
    characters:
        characters ??
        InMemoryCharacterRepository(store: store, relocate: store?.relocate),
    profile: profile ?? InMemoryProfileRepository(store: store),
    orders: orders ?? InMemoryOrderRepository(store: store),
    generator: generator ?? LocalCharacterGenerator(folder: store?.art),
    chat: chat ?? const LocalChatService(),
    motion: motion ?? motionService,
  );

  /// With the character service (`ApiConfig`). Everything is still kept on
  /// the iPad ([store]); the service makes friends from drawings, answers in
  /// chat and hears about changes through an outbox. Motions run in the app.
  factory AppServices.remote(
    ApiConfig config, {
    required FileStore store,
    http.Client? client,
  }) {
    final api = ApiClient(
      baseUrl: config.apiUrl,
      session: SupabasePasswordSession(config, client: client),
      client: client,
    );
    final outbox = Outbox(api, store: store);
    final art = DeviceArt(store.art);
    final windows = ApiWindowViews(api, store: store);
    final conversations = ConversationArchive(store: store);
    final characters = SyncedCharacterRepository(
      api,
      onForget: windows.forget,
      onCreated: windows.warm,
      local: InMemoryCharacterRepository(
        store: store,
        relocate: store.relocate,
      ),
      outbox: outbox,
      art: art,
    );
    final profile = SyncedProfileRepository(
      api,
      local: InMemoryProfileRepository(store: store),
      characters: characters,
      outbox: outbox,
      store: store,
    );
    return AppServices(
      draftStore: store,
      windowViews: windows,
      characters: characters,
      profile: profile,
      orders: InMemoryOrderRepository(store: store),
      generator: ApiCharacterGenerator(api, art: art, store: store),
      conversations: conversations,
      chat: ApiChatService(
        api,
        beforeReply: outbox.flush,
        onExchange: conversations.recordExchange,
      ),
      // 팀 서버의 GIF 대신 기존 앱 내장 모션을 유지한다.
      motion: const NoMotionService(),
      sync: ServiceSync(
        characters: characters,
        profile: profile,
        outbox: outbox,
      ),
    );
  }

  final CharacterRepository characters;
  final ProfileRepository profile;
  final OrderRepository orders;
  final LocalStore? draftStore;
  final ConversationArchive conversations;
  final CharacterGenerator generator;
  final ChatService chat;
  final MotionService motion;
  final WindowViewService? windowViews;

  /// Keeping the service's copy in step; null without the service.
  final ServiceSync? sync;

  /// The app's services. A screen built on its own, outside the app (as in
  /// widget tests), gets a fresh local set.
  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppServicesScope>()?.services ??
      AppServices.local();
}

/// Shares [AppServices] with every screen. It never changes for the life
/// of the app, so reading it doesn't subscribe to anything; it is safe to
/// call from initState.
class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) =>
      oldWidget.services != services;
}
