import '../localization/localized_text.dart';

/// Why a component is not being sold.
enum SoldOutReason {
  /// The store fell below the safety buffer. Nobody decided this; the count
  /// did.
  belowSafetyBuffer(
    label: LocalizedText(ar: 'نفد لهذا المساء', en: 'Sold out for the evening'),
    note: LocalizedText(
      ar: 'الكمية المتبقية محجوزة للطلبات الجارية',
      en: 'What is left is held for orders already on the line',
    ),
  ),

  /// A manager took it off. A quality call, a late delivery, a broken fryer —
  /// reasons a count cannot see.
  takenOff(
    label: LocalizedText(ar: 'موقوف مؤقتًا', en: 'Off the menu'),
    note: LocalizedText(
      ar: 'أوقفه المدير',
      en: 'Taken off by a manager',
    ),
  );

  const SoldOutReason({required this.label, required this.note});

  /// How it reads to a guest.
  final LocalizedText label;

  /// How it reads to a manager, who is owed the reason.
  final LocalizedText note;
}

/// What the store can still make of one menu component.
///
/// ## Why a sealed set and not a boolean
///
/// "Available" is the wrong question. A manager needs to know the difference
/// between forty portions and six, and a guest needs to be told the difference
/// between six and none — in different words. Three flat states carry that,
/// and a screen that forgets one does not compile.
sealed class StockStatus {
  const StockStatus({required this.portionsRemaining});

  /// Derives the status from a count and the rails.
  ///
  /// The single transition function. There is no path that constructs a
  /// [SoldOut] holding forty portions, or an [InStock] holding two.
  factory StockStatus.from({
    required int portionsRemaining,
    required int safetyBuffer,
    required int lowWaterMark,
    bool forcedOff = false,
  }) {
    if (forcedOff) {
      return SoldOut(
        reason: SoldOutReason.takenOff,
        portionsRemaining: portionsRemaining,
      );
    }
    if (portionsRemaining < safetyBuffer) {
      return SoldOut(
        reason: SoldOutReason.belowSafetyBuffer,
        portionsRemaining: portionsRemaining,
      );
    }
    if (portionsRemaining <= lowWaterMark) {
      return RunningLow(portionsRemaining: portionsRemaining);
    }
    return InStock(portionsRemaining: portionsRemaining);
  }

  /// How many standard portions the store can still make.
  ///
  /// Kept even on [SoldOut]: a manager stopping sales at four portions still
  /// needs to know it is four and not zero, and the buffer is exactly the
  /// stock that is left when selling stops.
  final int portionsRemaining;

  /// Whether a guest can order this right now.
  bool get isOrderable => this is! SoldOut;

  /// Whether a manager should be looking at it.
  bool get needsAttention => this is! InStock;
}

/// Comfortably in stock.
final class InStock extends StockStatus {
  /// Creates the in-stock status.
  const InStock({required super.portionsRemaining});

  @override
  String toString() => 'InStock($portionsRemaining)';

  @override
  bool operator ==(Object other) =>
      other is InStock && other.portionsRemaining == portionsRemaining;

  @override
  int get hashCode => Object.hash(InStock, portionsRemaining);
}

/// Still selling, but a manager should order or prep more.
///
/// Invisible to the guest on purpose. A menu that announces it is nearly out
/// of something creates a scarcity rush that empties the store faster, and
/// then the next forty guests are told no.
final class RunningLow extends StockStatus {
  /// Creates the running-low status.
  const RunningLow({required super.portionsRemaining});

  @override
  String toString() => 'RunningLow($portionsRemaining)';

  @override
  bool operator ==(Object other) =>
      other is RunningLow && other.portionsRemaining == portionsRemaining;

  @override
  int get hashCode => Object.hash(RunningLow, portionsRemaining);
}

/// Not being sold.
final class SoldOut extends StockStatus {
  /// Creates the sold-out status.
  const SoldOut({required this.reason, required super.portionsRemaining});

  /// Why.
  final SoldOutReason reason;

  @override
  String toString() => 'SoldOut(${reason.name}, $portionsRemaining)';

  @override
  bool operator ==(Object other) =>
      other is SoldOut &&
      other.reason == reason &&
      other.portionsRemaining == portionsRemaining;

  @override
  int get hashCode => Object.hash(SoldOut, reason, portionsRemaining);
}

/// What the menu can sell, right now, as an immutable snapshot.
///
/// ## Why a snapshot and not a live lookup
///
/// A guest's screen must not change its mind between the frame that laid it
/// out and the frame that painted it. Widgets hold one of these for the whole
/// build; a new one arrives through the tree when the count changes, and the
/// old one stays valid and consistent for anything still holding it.
///
/// Nothing here can reach into a plate. Availability describes the menu, never
/// the guest's selection — which is the entire reason a component going out
/// mid-session cannot break that session.
final class MenuAvailability {
  /// Creates a snapshot.
  const MenuAvailability(this._byComponent);

  /// Everything orderable, for tests and for a first frame before any count
  /// has arrived.
  static const MenuAvailability everything = MenuAvailability(
    <String, StockStatus>{},
  );

  final Map<String, StockStatus> _byComponent;

  /// The status of [componentId].
  ///
  /// A component the snapshot has never heard of is orderable. A menu that
  /// hid every dish it had no count for would empty itself the first time a
  /// new dish shipped ahead of its recipe.
  StockStatus statusOf(String componentId) =>
      _byComponent[componentId] ?? const InStock(portionsRemaining: 999);

  /// Whether [componentId] can be ordered.
  bool canOrder(String componentId) => statusOf(componentId).isOrderable;

  /// Every component that is not being sold.
  Set<String> get soldOut => <String>{
        for (final MapEntry<String, StockStatus> entry in _byComponent.entries)
          if (entry.value is SoldOut) entry.key,
      };

  /// Every component a manager should look at.
  Set<String> get needingAttention => <String>{
        for (final MapEntry<String, StockStatus> entry in _byComponent.entries)
          if (entry.value.needsAttention) entry.key,
      };

  @override
  String toString() => 'MenuAvailability(${soldOut.length} off)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MenuAvailability) return false;
    if (other._byComponent.length != _byComponent.length) return false;
    for (final MapEntry<String, StockStatus> entry in _byComponent.entries) {
      if (other._byComponent[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(<Object>[
        for (final MapEntry<String, StockStatus> e in _byComponent.entries)
          Object.hash(e.key, e.value),
      ]);
}
