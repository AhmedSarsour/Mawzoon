import '../../../core/localization/localized_text.dart';
import '../../../core/menu/ingredient_option.dart';
import '../../../core/menu/mawzoon_catalog.dart';
import '../../../core/pricing/money.dart';
import 'order_draft.dart';

/// What happened when the guest tapped "place order".
///
/// Three outcomes, because "it failed" is two different events: the kitchen
/// said no (nothing was placed, tell the guest why), or nobody answered (it may
/// have been placed — retry with the same key, which can never place it twice).
sealed class PlaceOrderOutcome {
  const PlaceOrderOutcome();
}

/// The kitchen has it.
final class OrderPlaced extends PlaceOrderOutcome {
  /// Creates the placed outcome.
  const OrderPlaced({
    required this.orderId,
    required this.orderNumber,
    required this.total,
    this.replayed = false,
  });

  /// The server's id for the order.
  final String orderId;

  /// The number called out at the pass.
  final int orderNumber;

  /// What the server charged — the figure the guest pays, whatever the sheet
  /// computed locally.
  final Money total;

  /// True when this answers a retry of an order that had already gone through.
  final bool replayed;

  /// The code on the kitchen ticket and the guest's confirmation.
  String get code => 'M-$orderNumber';
}

/// Why the kitchen turned an order down. Nothing was placed.
enum RefusalReason {
  /// A component sold out between the menu loading and the tap.
  soldOut,

  /// This build shows prices the server no longer charges.
  menuChanged,

  /// Delivery without a usable phone number.
  needsPhone,

  /// Delivery without an address.
  needsAddress,

  /// Anything the guest can't fix by editing the sheet: a malformed request,
  /// a lost session, a key reused by someone else.
  couldNotSend,
}

/// The kitchen said no.
final class OrderRefused extends PlaceOrderOutcome {
  /// Creates the refused outcome.
  const OrderRefused(this.reason, {this.componentId});

  /// Why.
  final RefusalReason reason;

  /// The component that sold out, for [RefusalReason.soldOut].
  final String? componentId;

  /// Whether tapping again could help. Only for [RefusalReason.couldNotSend];
  /// the others need the guest to change something first.
  bool get retryable => reason == RefusalReason.couldNotSend;

  /// What the place-order button says instead of its label.
  LocalizedText get message => switch (reason) {
        RefusalReason.soldOut => _soldOut,
        RefusalReason.menuChanged => const LocalizedText(
            ar: 'تغيّرت القائمة — حدّث التطبيق',
            en: 'The menu changed — update the app',
          ),
        RefusalReason.needsPhone => OrderDraft.needsPhoneBlocker,
        RefusalReason.needsAddress => OrderDraft.needsAddressBlocker,
        RefusalReason.couldNotSend => const LocalizedText(
            ar: 'تعذّر إرسال الطلب — حاول مجددًا',
            en: "Couldn't send your order — try again",
          ),
      };

  LocalizedText get _soldOut {
    final String? id = componentId;
    final IngredientOption? option =
        id == null ? null : MawzoonCatalog.optionById(id);
    if (option != null) return OrderDraft.soldOutBlocker(option);
    return const LocalizedText(
      ar: 'نفد أحد مكوّنات طبقك — اختر بديلًا',
      en: 'Part of your plate just sold out — pick another',
    );
  }

  @override
  String toString() => 'OrderRefused(${reason.name}, $componentId)';
}

/// Nobody answered. The order may or may not have been placed; retrying with
/// the same idempotency key is safe either way.
final class OrderUnreachable extends PlaceOrderOutcome {
  /// Creates the unreachable outcome.
  const OrderUnreachable();

  /// What the button says. The button stays live: trying again is the answer,
  /// and the same key means it can't place the order twice.
  static const LocalizedText message = LocalizedText(
    ar: 'تعذّر الاتصال — اضغط لإعادة المحاولة',
    en: "Couldn't connect — tap to retry",
  );
}

/// Sends an order to the kitchen.
abstract interface class OrderGateway {
  /// Places [draft]. Calling again with the same [idempotencyKey] returns the
  /// first answer instead of placing a second order.
  Future<PlaceOrderOutcome> place(
    OrderDraft draft, {
    required String idempotencyKey,
  });
}
