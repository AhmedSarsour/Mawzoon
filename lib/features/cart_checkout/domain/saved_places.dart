import '../../../core/localization/localized_text.dart';
import 'delivery_address.dart';

/// The guest's saved addresses.
///
/// Stand-in data until an account service exists. It lives behind a named
/// class rather than a literal in a widget so the day it becomes a repository
/// call, nothing above it changes.
abstract final class SavedPlaces {
  /// Home.
  static const DeliveryAddress home = DeliveryAddress(
    id: 'address.home',
    label: LocalizedText(ar: 'المنزل', en: 'Home'),
    line: 'شارع الأمير سلطان، مبنى ٤٤٢٩',
    district: 'العليا',
    directions: 'الدور الثالث، الباب الأيمن',
    isDefault: true,
  );

  /// Work.
  static const DeliveryAddress work = DeliveryAddress(
    id: 'address.work',
    label: LocalizedText(ar: 'العمل', en: 'Work'),
    line: 'طريق الملك فهد، برج المملكة',
    district: 'العليا',
    directions: 'الاستقبال في الدور الأرضي',
  );

  /// The gym — the address a plate is most often sent to after training.
  static const DeliveryAddress gym = DeliveryAddress(
    id: 'address.gym',
    label: LocalizedText(ar: 'النادي', en: 'The gym'),
    line: 'شارع التحلية، مجمع الرياضة',
    district: 'السليمانية',
  );

  /// Every saved address, default first.
  static const List<DeliveryAddress> all = <DeliveryAddress>[home, work, gym];

  /// The address a new order starts on, or `null` if none is marked.
  static DeliveryAddress? get defaultAddress {
    for (final DeliveryAddress address in all) {
      if (address.isDefault) return address;
    }
    return all.isEmpty ? null : all.first;
  }
}
