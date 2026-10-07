import 'package:flutter/material.dart';

/// Ported 1:1 from design_handoff_pavio/README.md's Design Tokens section — the same
/// source owner-dashboard/app/tokens.css encodes for the web. Keep both in sync by hand;
/// there's no shared token package between the Next.js and Flutter apps.
class PavioColors {
  PavioColors._();

  // Primary — Pavio Green
  static const primary900 = Color(0xFF08312A);
  static const primary800 = Color(0xFF0B4438);
  static const primary700 = Color(0xFF0F5C4A); // Base
  static const primary600 = Color(0xFF147A61);
  static const primary500 = Color(0xFF1E9B7B);
  static const primary100 = Color(0xFFD7ECE6);
  static const primary50 = Color(0xFFEEF6F3);

  // Secondary — Warm Gold. Accent & money only, never body UI.
  static const gold900 = Color(0xFF5C3A08);
  static const gold800 = Color(0xFF8A5A16);
  static const gold700 = Color(0xFFB9791F);
  static const gold500 = Color(0xFFE8A33D); // Base — the single money CTA
  static const gold300 = Color(0xFFF2C982);
  static const gold200 = Color(0xFFF9E4BC);
  static const gold100 = Color(0xFFFBEBD0);
  static const goldTextOn = Color(0xFF3A2606);

  // Neutral — warm, never cold blue
  static const ink900 = Color(0xFF1A1F1D);
  static const ink700 = Color(0xFF3A423F);
  static const ink500 = Color(0xFF5A6560); // floor — never below 13px text; darkened 2026-08-21 for WCAG AA
  static const ink400 = Color(0xFF97A09B);
  static const ink300 = Color(0xFFC3C9C4);
  static const line = Color(0xFFDBD9D2);
  static const surface = Color(0xFFF6F5F1);
  static const canvas = Color(0xFFEEEDE8);
  static const white = Color(0xFFFFFFFF);
  static const skeletonBase = Color(0xFFE4E2DC);
  static const skeletonHighlight = Color(0xFFF1EFEA);

  // Semantic status — one meaning per color, reused across every status axis.
  static const positiveFg = Color(0xFF1E8E5A);
  static const positiveTint = Color(0xFFE3F3EA);
  static const positiveTintBorder = Color(0xFFC9E6D6);
  static const positiveTextOnTint = Color(0xFF166B44);

  static const negativeFg = Color(0xFFCB2E2E);
  static const negativeTint = Color(0xFFFBE4E2);
  static const negativeTintBorder = Color(0xFFF2C9C6);
  static const negativeTextOnTint = Color(0xFFA62222);

  static const warningFg = Color(0xFFC77D11);
  static const warningTint = Color(0xFFFBEFD6);
  static const warningTintBorder = Color(0xFFF1DEAF);
  static const warningTextOnTint = Color(0xFF9A6210);

  static const infoFg = Color(0xFF1F6FA8);
  static const infoTint = Color(0xFFE2EEF6);
  static const infoTintBorder = Color(0xFFC4DBEC);
  static const infoTextOnTint = Color(0xFF1A4F78);

  static const offlineFg = Color(0xFF6B7671);
  static const offlineTint = Color(0xFFEEECE7);
  static const offlineTintBorder = Color(0xFFDBD9D2);
  static const offlineTextOnTint = Color(0xFF4A524E);

  static const inputErrorBg = Color(0xFFFEF7F6);

  // WhatsApp-style notification cards (chat canvas + bubbles) — see Product Patterns.
  static const chatCanvas = Color(0xFFDDD9CE);
  static const inboundBubble = white;
  static const outboundBubble = Color(0xFFDCF3D6);
}
