import 'package:flutter/material.dart';

/// Ported from owner-dashboard/app/tokens.css's Elevation section (2026-08-31) — this
/// app had no elevation vocabulary at all until now (every surface was `elevation: 0`
/// plus a 1px `PavioColors.line` border, root cause of the "flat hierarchy" finding in
/// the design review). `e0` is that existing 1px-border look, kept as a named step so a
/// widget can declare "no elevation" on purpose rather than by omission; `e1`/`e2`/
/// `modal` step up from there. Apply to `Container.boxShadow` the same way the web file's
/// callers apply `box-shadow: var(--elevation-e1)` etc.
///
/// Colors below are `PavioColors.ink900`/black baked into each `Color` literal rather
/// than referencing `PavioColors.ink900.withValues(alpha: ...)` — a `BoxShadow` list
/// here needs to be `const`, and `withValues` isn't a const constructor. If `ink900`
/// (`#1A1F1D`) ever changes, these need a manual update to match — same hand-sync risk
/// tokens.css's own README already flags between the web and Dart token files.
class PavioElevation {
  PavioElevation._();

  static const e0 = <BoxShadow>[];

  // rgba(26,31,29,.08)
  static const e1 = <BoxShadow>[BoxShadow(color: Color(0x141A1F1D), blurRadius: 2, offset: Offset(0, 1))];

  // rgba(26,31,29,.12)
  static const e2 = <BoxShadow>[BoxShadow(color: Color(0x1F1A1F1D), blurRadius: 14, offset: Offset(0, 4))];

  // rgba(0,0,0,.28)
  static const modal = <BoxShadow>[BoxShadow(color: Color(0x47000000), blurRadius: 40, offset: Offset(0, 12))];

  /// Behind a modal/bottom-sheet/dialog barrier — same color web's `--scrim` names for
  /// the same purpose. rgba(26,31,29,.4)
  static const scrim = Color(0x661A1F1D);
}
