import 'package:flutter/material.dart';

/// Responsive breakpoint utilities for adaptive layouts.
///
/// Breakpoints based on Material Design guidelines:
/// - Small: < 600dp (phones in portrait)
/// - Medium: 600-840dp (phones in landscape, small tablets)
/// - Large: 840-1200dp (tablets in portrait)
/// - XLarge: > 1200dp (tablets in landscape, desktops)
class Breakpoints {
  /// Small screens: phones in portrait (< 600dp)
  static bool isSmall(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  /// Medium screens: phones in landscape, small tablets (600-840dp)
  static bool isMedium(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 840;
  }

  /// Large screens: tablets in portrait (840-1200dp)
  static bool isLarge(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 840 && width < 1200;
  }

  /// Extra large screens: tablets in landscape, desktops (> 1200dp)
  static bool isXLarge(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1200;
  }

  /// Returns the number of columns for a grid layout based on screen size
  static int gridColumns(BuildContext context) {
    if (isSmall(context)) return 1;
    if (isMedium(context)) return 2;
    if (isLarge(context)) return 2;
    return 3; // XLarge
  }

  /// Returns responsive padding based on screen size
  static EdgeInsets responsivePadding(BuildContext context) {
    if (isXLarge(context)) {
      return const EdgeInsets.symmetric(horizontal: 48, vertical: 24);
    } else if (isLarge(context)) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 20);
    } else if (isMedium(context)) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  }

  /// Returns responsive horizontal padding
  static double responsiveHorizontalPadding(BuildContext context) {
    if (isXLarge(context)) return 48;
    if (isLarge(context)) return 32;
    if (isMedium(context)) return 24;
    return 16;
  }

  /// Returns responsive vertical padding
  static double responsiveVerticalPadding(BuildContext context) {
    if (isXLarge(context)) return 24;
    if (isLarge(context)) return 20;
    if (isMedium(context)) return 16;
    return 16;
  }

  /// Returns max width for content containers
  static double maxContentWidth(BuildContext context) {
    if (isXLarge(context)) return 1200;
    if (isLarge(context)) return 840;
    if (isMedium(context)) return 600;
    return double.infinity;
  }
}
