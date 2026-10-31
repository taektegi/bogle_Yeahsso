part of '../order_screen.dart';

// Delivery addresses: the saved address card, the new-address card and the
// form.

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});
  final DeliveryAddress address;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: BogleColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Tag(address.label, strong: true),
                  if (address.isDefault) const _Tag('기본 배송지'),
                  Text(
                    address.recipient,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BogleColors.text,
                    ),
                  ),
                  Text(address.phone, style: _Type.muted),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '(${address.zip}) ${address.street}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: BogleColors.text,
                ),
              ),
              if (address.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(address.detail, style: _Type.muted.copyWith(fontSize: 15)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a new address is added: the only card until there is one.
class _NewAddressCard extends StatelessWidget {
  const _NewAddressCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF7F8FC),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: BogleColors.line),
    ),
    child: InkWell(
      key: const ValueKey('order-add-address'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Row(
          children: [
            Icon(Icons.add_location_alt_outlined, color: BogleColors.logo),
            SizedBox(width: 10),
            Text(
              '새 배송지 추가',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: BogleColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
