import 'package:flutter/material.dart';

/// Ported from owner-dashboard/app/tokens.css's Motion section (2026-08-31) — same
/// four named durations, plus [reduceMotion] standing in for the web file's
/// `@media (prefers-reduced-motion: reduce)` override. [spinner]/[shimmer]/[caret] name
/// durations for loops a custom animation controller would repeat; [toggle] is a
/// one-shot transition duration (e.g. `AnimatedContainer.duration`). A caller driving a
/// repeating animation should check [reduceMotion] and skip/zero it rather than hard-
/// coding a duration — one-shot transitions are left alone, matching the web file's own
/// posture (`--motion-toggle` isn't zeroed under reduced motion either).
class PavioMotion {
  PavioMotion._();

  static const spinner = Duration(milliseconds: 750);
  static const shimmer = Duration(milliseconds: 1300);
  static const caret = Duration(seconds: 1);
  static const toggle = Duration(milliseconds: 180);
  static const toggleCurve = Curves.ease;

  /// Reflects the OS-level "Reduce Motion" accessibility setting — Flutter's own
  /// equivalent of the web's `prefers-reduced-motion` media query.
  static bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;
}
