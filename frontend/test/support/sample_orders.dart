import 'package:bogle_app/src/data/order_repository.dart';

/// Earlier orders for tests of My Page: one being made, two delivered.
/// The app itself starts with none.
const sampleOrders = [
  ProfileOrder(
    id: 'TEST-0926',
    product: '뭉글이 인형',
    asset: 'assets/figma/character_card.svg',
    options: ['기본형', 'M 사이즈 (30cm)', '선물 포장'],
    date: '2026.09.26',
    price: 42000,
    status: ProfileOrderStatus.making,
    shipping: ShippingInfo(
      recipient: '김보글',
      address: '서울특별시 보글구 몽글로 1 보글아파트 101동 1203호',
      courier: '제작이 끝나면 보내 드려요',
    ),
  ),
  ProfileOrder(
    id: 'TEST-0812',
    product: '뚜치 인형',
    asset: 'assets/figma/dduchi.png',
    options: ['기본형', 'S 사이즈 (20cm)'],
    date: '2026.08.12',
    price: 36000,
    status: ProfileOrderStatus.delivered,
  ),
  ProfileOrder(
    id: 'TEST-0728',
    product: '네모린 인형',
    asset: 'assets/figma/nemorin.png',
    options: ['기본형', 'M 사이즈 (30cm)'],
    date: '2026.07.28',
    price: 42000,
    status: ProfileOrderStatus.delivered,
  ),
];

/// A saved address, for tests that get as far as paying.
const sampleAddress = DeliveryAddress(
  label: '우리 집',
  recipient: '김보글',
  phone: '010-0000-0000',
  zip: '00000',
  street: '서울특별시 보글구 몽글로 1',
  detail: '보글아파트 101동 1203호',
);
