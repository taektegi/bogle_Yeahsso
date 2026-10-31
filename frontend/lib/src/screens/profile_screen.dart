import 'package:flutter/material.dart';

import '../data/app_services.dart';
import '../data/character_repository.dart';
import '../data/order_repository.dart';
import '../data/profile_repository.dart';
import '../models/character_friend.dart';
import '../theme/bogle_theme.dart';
import '../theme/bogle_viewport.dart';
import '../widgets/bogle_widgets.dart';
import '../widgets/top_bar.dart';
import 'create_studio_screen.dart';
import 'friend_screen.dart';
import 'order_screen.dart';
import 'order/address_book_screen.dart';
import 'order/payment_methods_screen.dart';
import 'order/postcode_search.dart';
import 'profile/characters_section.dart';
import 'profile/orders_section.dart';
import 'profile/profile_editor.dart';
import 'profile/profile_widgets.dart';
import 'profile/settings_section.dart';

/// My page, after the 마이페이지 design (and Figma 254:3589): a big
/// greeting, 내 친구들, 주문 내역, and 설정 및
/// 고객센터 (kept with its icons), in white cards under display-font titles.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.repository,
    this.profileRepository,
    this.orderRepository,
    this.searchAddress,
  });
  final CharacterRepository repository;

  /// Default to the app's ([AppServices]).
  final ProfileRepository? profileRepository;
  final OrderRepository? orderRepository;
  final AddressSearch? searchAddress;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _repo =
      widget.profileRepository ?? AppServices.of(context).profile;
  late final OrderRepository _orderRepo =
      widget.orderRepository ?? AppServices.of(context).orders;
  UserProfile _profile = const UserProfile();
  List<CharacterFriend> _friends = [];
  List<ProfileOrder> _orders = [];
  bool _loading = true;
  bool _failed = false;
  int _request = 0;
  final _messages = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final results = await Future.wait<Object>([
        _repo.fetchProfile(),
        widget.repository.fetchFriends(),
        _orderRepo.fetchOrders(),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _friends = results[1] as List<CharacterFriend>;
        _orders = results[2] as List<ProfileOrder>;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(bogleRoute(screen));
    if (mounted) await _load();
  }

  Future<void> _edit() async {
    final saved = await showProfileEditor(
      context,
      profile: _profile,
      friends: _friends,
      repository: _repo,
    );
    if (mounted && saved != null) {
      setState(() => _profile = saved);
      _messages.currentState
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('프로필을 바꿨어요.')));
    }
  }

  Future<void> _saveProfile(UserProfile next) async {
    final saved = await _repo.saveProfile(next);
    if (mounted) setState(() => _profile = saved);
  }

  void _openFriend(CharacterFriend f) =>
      _open(FriendScreen(repository: widget.repository, friend: f));
  void _create() => _open(CreateStudioScreen(repository: widget.repository));

  Future<void> _changeOrderAddress(ProfileOrder order) async {
    final address = await Navigator.of(context).push<DeliveryAddress>(
      bogleRoute(
        AddressBookScreen(
          repository: _orderRepo,
          selecting: true,
          search: widget.searchAddress,
        ),
      ),
    );
    if (address == null || !mounted) return;
    try {
      await _orderRepo.updateOrderShipping(order.id, address);
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        _messages.currentState?.showSnackBar(
          const SnackBar(content: Text('주문의 배송지를 바꾸지 못했어요. 다시 시도해 주세요.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => withBogleBodyFont(
    context,
    ScaffoldMessenger(
      key: _messages,
      child: Scaffold(
        backgroundColor: BogleColors.cream,
        // Text entry happens in dialogs, which avoid the keyboard themselves.
        resizeToAvoidBottomInset: false,
        body: Column(
          children: [
            // Figma 254:3589: the shared top bar with the child's name in the
            // pill; news has the same destination on every screen.
            AppTopBar(
              key: const ValueKey('profile-header'),
              repository: widget.repository,
              title: _profile.nickname,
              current: TopBarPage.profile,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SafeArea(top: false, bottom: false, child: _body()),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: '마이페이지 불러오는 중'),
      );
    }
    if (_failed) {
      return Center(
        child: ProfileEmptyState(
          icon: Icons.cloud_off_rounded,
          title: '마이페이지를 불러오지 못했어요',
          message: '잠시 후 다시 시도해 주세요.',
          action: '다시 불러오기',
          onPressed: () {
            setState(() => _loading = true);
            _load();
          },
        ),
      );
    }
    const gap = SizedBox(height: 36);
    final side = (BogleViewport.of(context).usable.width * .04).clamp(
      16.0,
      40.0,
    );
    return SingleChildScrollView(
      key: const ValueKey('profile-scroll'),
      padding: EdgeInsets.fromLTRB(
        side,
        12,
        side,
        40 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Overview(profile: _profile, friends: _friends, onEdit: _edit),
              gap,
              CharactersSection(
                friends: _friends,
                onOpen: _openFriend,
                onCreate: _create,
              ),
              gap,
              OrdersSection(
                orders: _orders,
                onChangeAddress: _changeOrderAddress,
                onShop: () => _friends.isEmpty
                    ? _create()
                    : _open(
                        OrderScreen(
                          repository: widget.repository,
                          orderRepository: _orderRepo,
                          searchAddress: widget.searchAddress,
                        ),
                      ),
              ),
              gap,
              gap,
              SettingsSection(
                profile: _profile,
                onSave: _saveProfile,
                onEditProfile: _edit,
                onAddresses: () => _open(
                  AddressBookScreen(
                    repository: _orderRepo,
                    search: widget.searchAddress,
                  ),
                ),
                onPaymentMethods: () =>
                    _open(PaymentMethodsScreen(repository: _orderRepo)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's greeting: a big round picture on the left, "안녕, ○○!" in
/// the display font, how many friends they've made, and a big outlined
/// "개인 정보 수정" pill.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.profile,
    required this.friends,
    required this.onEdit,
  });
  final UserProfile profile;
  final List<CharacterFriend> friends;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final avatar = box.maxWidth >= 900 ? 156.0 : 120.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: '프로필 바꾸기',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: profileAccent(profile.profileColor),
                    shape: BoxShape.circle,
                  ),
                  child: ProfileAvatar(asset: profile.avatar, size: avatar),
                ),
              ),
            ),
            SizedBox(width: avatar * .24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안녕, ${profile.nickname}!',
                    key: const ValueKey('profile-greeting'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: bogleDisplayFont,
                      fontSize: avatar * .25,
                      height: 1.15,
                      color: BogleColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '지금까지 ${friends.length}개의 캐릭터를 만들었어요.',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: BogleColors.text,
                    ),
                  ),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      profile.bio,
                      style: const TextStyle(
                        fontFamily: bogleUiFont,
                        fontSize: 16,
                        color: BogleColors.text,
                      ),
                    ),
                  ],
                  if (profile.interests.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final interest in profile.interests)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: profileAccent(
                                profile.profileColor,
                              ).withValues(alpha: .4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              interest,
                              style: const TextStyle(
                                fontFamily: bogleUiFont,
                                fontSize: 13,
                                color: BogleColors.text,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  ProfileButton(
                    label: '개인 정보 수정',
                    large: true,
                    onPressed: onEdit,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
