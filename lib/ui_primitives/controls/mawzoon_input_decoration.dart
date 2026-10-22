import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// The one look for a text field: porcelain fill, hairline at rest, an ember
/// ring while typing, control radius, thumb-height.
InputDecoration mawzoonInputDecoration(
  BuildContext context, {
  String? hint,
  Widget? prefix,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: context.space.controlRadius,
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    filled: true,
    fillColor: context.colors.porcelain,
    hintText: hint,
    hintStyle: context.type.body.copyWith(color: context.colors.inkFaint),
    prefixIcon: prefix,
    prefixIconConstraints: BoxConstraints(minHeight: context.space.thumbTarget),
    contentPadding: EdgeInsetsDirectional.symmetric(
      horizontal: prefix == null ? context.space.base : 0,
      vertical: context.space.base,
    ),
    enabledBorder: border(context.colors.hairline, 1),
    focusedBorder: border(context.colors.ember, 1.5),
  );
}
