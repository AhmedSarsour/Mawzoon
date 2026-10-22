import '../../../core/measure/quantity.dart';

/// What the manager is recording for one ingredient.
enum StockMovement {
  /// A stock take: the shelf holds exactly this.
  count,

  /// A delivery arrived: add this.
  delivery,

  /// Waste, a staff meal, a dropped tray: take this away.
  writeOff,
}

/// A typed amount in the ingredient's *bulk* unit (kg, L, pieces) as a
/// [Quantity], or null if it isn't a usable non-negative number.
///
/// Typed in bulk because that's how a store room is counted ("12.4 kg", not
/// "12400 g"). Arabic-Indic digits and the Arabic decimal mark are accepted,
/// since that's what an Arabic keyboard types.
Quantity? parseBulkAmount(String text, MeasureUnit unit) {
  final String normalised = _asciiNumber(text.trim());
  if (normalised.isEmpty) return null;
  final double? value = double.tryParse(normalised);
  if (value == null || value.isNaN || value.isInfinite || value < 0) {
    return null;
  }
  return switch (unit) {
    MeasureUnit.gram => Quantity.kilograms(value),
    MeasureUnit.millilitre => Quantity.litres(value),
    MeasureUnit.piece => Quantity.pieces(value),
  };
}

/// What the book will say after recording [amount] as [movement].
Quantity applyMovement(
  Quantity onHand,
  StockMovement movement,
  Quantity amount,
) =>
    switch (movement) {
      StockMovement.count => amount,
      StockMovement.delivery => onHand + amount,
      StockMovement.writeOff => onHand - amount,
    };

String _asciiNumber(String s) {
  final StringBuffer out = StringBuffer();
  for (final int c in s.runes) {
    if (c >= 0x0660 && c <= 0x0669) {
      out.writeCharCode(0x30 + c - 0x0660);
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      out.writeCharCode(0x30 + c - 0x06F0);
    } else if (c == 0x066B || c == 0x2C) {
      out.write('.'); // Arabic decimal separator, or a comma
    } else if (c != 0x20) {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}
