import 'package:flutter/material.dart';

// Flik design tokens based on the minimal-ai-ui specification.
class FlikTokens {
  // Theme ramp - dark mode default
  static const Color background = Color(0xFF151515);
  static const Color surface = Color(0xFF20201E);
  static const Color raised = Color(0xFF303030);
  static const Color text = Color(0xFFF9F9F7);
  static const Color muted = Color(0xFFA0A09E);
  static const Color line = Color(0x1FFFFFFF); // 12% white
  static const Color accent = Color(0xFF3566EF);
  static const Color accentSoft = Color(0xFF8AABF8);
  static const Color danger = Color(0xFFEF4444);

  // Light theme alternative
  static const Color lightBackground = Color(0xFFFCFCFC);
  static const Color lightSurface = Color(0xFFE8E8E8);
  static const Color lightRaised = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF0D0D0D);
  static const Color lightMuted = Color(0xFF5D5D5D);
  static const Color lightLine = Color(0x1A000000); // 10% black
  static const Color lightAccent = Color(0xFF2D51BF);

  // Geometry
  static const double radiusGroup = 28.0;
  static const double radiusInner = 6.0;
  static const double radiusPill = 999.0;
  static const double radiusSheet = 28.0;

  // Margins & rhythm
  static const double screenMargin = 16.0;
  static const double tabletMargin = 24.0;
  static const double desktopMargin = 40.0;
  static const double unit = 8.0;

  // Controls
  static const double rowHeight = 56.0;
  static const double rowHeightSubtitle = 72.0;
  static const double buttonHeight = 44.0;
  static const double buttonHeightLarge = 52.0;
  static const double iconButtonSize = 44.0;

  // Motion durations
  static const Duration fastMotion = Duration(milliseconds: 120);
  static const Duration baseMotion = Duration(milliseconds: 200);
  static const Duration slowMotion = Duration(milliseconds: 320);

  // Curves
  static const Curve easeStandard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve easeEnter = Cubic(0.05, 0.7, 0.1, 1.0);
}
