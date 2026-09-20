import 'package:flutter/material.dart';

import '../theme/mawzoon_typography.dart';
import '../theme/theme_context.dart';

/// Text that carries its script's strut.
///
/// A [TextStyle] with `height: 1.8` is not on its own enough to stop Arabic
/// diacritics clipping. Without a [StrutStyle] the line box is measured from
/// whatever glyphs land on that line, so a dish name whose first line carries
/// a shadda and whose second does not renders with two different line heights
/// — and a single-line label with a stacked mark can be trimmed by its
/// container. The strut sets a floor that does not depend on the content.
///
/// Use this anywhere the copy may be Arabic, which in this app is everywhere.
/// It resolves the strut from the ambient [MawzoonTypography], so it stays
/// correct across a language switch with no call-site change.
class MawzoonText extends StatelessWidget {
  /// Creates strut-aware text.
  const MawzoonText(
    this.data, {
    super.key,
    this.style,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  /// The string to render.
  final String data;

  /// The style to use. Defaults to the ambient body style.
  final TextStyle? style;

  /// A colour applied over [style], so a call site can pick a role colour
  /// without rebuilding the whole style.
  final Color? color;

  /// How the text is aligned within its box.
  final TextAlign? textAlign;

  /// The maximum number of lines before [overflow] applies.
  final int? maxLines;

  /// What to do when the text does not fit.
  final TextOverflow? overflow;

  /// Whether the text should wrap.
  final bool? softWrap;

  /// An override read by screen readers instead of [data].
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final MawzoonTypography type = context.type;
    final TextStyle resolved = (style ?? type.body).copyWith(color: color);

    return Text(
      data,
      style: resolved,
      strutStyle: type.strutFor(resolved),
      textHeightBehavior: type.heightBehavior,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      semanticsLabel: semanticsLabel,
    );
  }
}
