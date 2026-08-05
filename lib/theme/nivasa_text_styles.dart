import 'package:flutter/material.dart';
import 'nivasa_colors.dart';

const _fontSans = 'Noto Sans';
const _fontMono = 'Noto Sans Mono';

/// Type scale from the design doc, ported directly — sizes, weights, and (unitless)
/// line-heights match exactly. `letterSpacing` below is pre-converted from the doc's em
/// values to logical pixels at each style's font size (Flutter's TextStyle takes px, CSS
/// used em). `height` in Flutter is a multiplier of fontSize, same semantics as CSS
/// unitless line-height, so those values carry over unchanged.
class NivasaText {
  NivasaText._();

  static const display = TextStyle(
    fontFamily: _fontSans,
    fontSize: 40,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.8,
    color: NivasaColors.ink900,
  );

  static const h1 = TextStyle(
    fontFamily: _fontSans,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.6,
    color: NivasaColors.ink900,
  );

  static const h2 = TextStyle(
    fontFamily: _fontSans,
    fontSize: 23,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.345,
    color: NivasaColors.ink900,
  );

  static const h3 = TextStyle(
    fontFamily: _fontSans,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: NivasaColors.ink900,
  );

  static const body = TextStyle(
    fontFamily: _fontSans,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: NivasaColors.ink900,
  );

  static const label = TextStyle(
    fontFamily: _fontSans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: NivasaColors.ink700,
  );

  static const caption = TextStyle(
    fontFamily: _fontSans,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: NivasaColors.ink500,
  );

  /// IDs, ₹ amounts, OTP digits, timestamps, transaction tokens — anything tabular or
  /// scanned digit-by-digit, per the doc's Typography section.
  static const mono = TextStyle(
    fontFamily: _fontMono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.26,
    color: NivasaColors.ink900,
  );
}
