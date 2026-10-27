/// The guest's mobile, normalised to `+9725XXXXXXXX`.
///
/// Accepts how people actually type it — `050-123-4567`, `0501234567`,
/// `501234567`, `+972 50…`, `00972…`, Arabic-Indic digits from an Arabic
/// keyboard — and returns null for anything that isn't an Israeli mobile, so
/// the field can't hand the driver a number they can't call.
String? israeliMobile(String input) {
  final String digits = _asciiDigits(input).replaceAll(RegExp(r'[\s\-()]'), '');
  final String local = switch (digits) {
    final String d when d.startsWith('+972') => d.substring(4),
    final String d when d.startsWith('00972') => d.substring(5),
    final String d when d.startsWith('972') && d.length == 12 => d.substring(3),
    final String d when d.startsWith('0') => d.substring(1),
    final String d => d,
  };
  if (!RegExp(r'^5\d{8}$').hasMatch(local)) return null;
  return '+972$local';
}

/// `+972501234567` as `050-123-4567` — the way it's written in Israel.
String formatIsraeliMobile(String e164) {
  if (!RegExp(r'^\+9725\d{8}$').hasMatch(e164)) return e164;
  final String l = localPart(e164);
  return '${l.substring(0, 3)}-${l.substring(3, 6)}-${l.substring(6)}';
}

/// What the guest edits (`0501234567`), or '' for none.
String localPart(String? e164) =>
    e164 != null && e164.startsWith('+972') ? '0${e164.substring(4)}' : '';

String _asciiDigits(String s) {
  final StringBuffer out = StringBuffer();
  for (final int c in s.runes) {
    if (c >= 0x0660 && c <= 0x0669) {
      out.writeCharCode(0x30 + c - 0x0660); // Arabic-Indic
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      out.writeCharCode(0x30 + c - 0x06F0); // Extended (Persian)
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// Where the guest's phone is kept between orders, so it is asked once.
abstract interface class PhoneMemory {
  /// The last phone used, or null.
  Future<String?> read();

  /// Remembers [e164].
  Future<void> write(String e164);
}
