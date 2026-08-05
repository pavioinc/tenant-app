/// Strict 4px base, per the design doc's Spacing section.
class NivasaSpacing {
  NivasaSpacing._();

  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0; // card padding (mobile)
  static const s20 = 20.0;
  static const s24 = 24.0; // section gaps
  static const s32 = 32.0; // block spacing
  static const s48 = 48.0; // major regions

  /// "Touch targets never below 44px. Buttons min-height 48px on mobile."
  static const minTouchTarget = 44.0;
  static const buttonHeightMobile = 48.0;
}

class NivasaRadius {
  NivasaRadius._();

  static const sm = 4.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const pill = 999.0;
  static const card = 12.0;
  static const button = 9.0;
  static const input = 9.0;
  static const bottomSheetTop = 16.0;
  static const phoneFrameCard = 16.0;
}
