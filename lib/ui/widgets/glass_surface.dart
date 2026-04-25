import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../theme/liquid_glass_theme.dart';

/// A translucent, backdrop-blurred surface — the hallmark of Apple's
/// Liquid Glass material.
///
/// On platforms where [isLiquidGlassPlatform] is true (iOS, macOS) the
/// widget renders a real [BackdropFilter] blur over a low-alpha tint
/// layer. Elsewhere it renders an opaque rounded surface so layouts
/// don't shift between platforms — the visual treatment differs but
/// the box geometry is identical.
///
/// Use it for hero surfaces (cards over imagery, modal sheets, action
/// bars) where you want the content behind to peek through. For
/// regular content areas the theme's `cardTheme` already supplies a
/// translucent fill, so wrapping every Card in a GlassSurface would be
/// over-blurry — pick where it matters.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  /// Sigma passed to [ImageFilter.blur] on Apple platforms. Higher
  /// values look more frosted but cost more on every frame.
  final double blurSigma;

  /// Override the surface tint. Defaults to white-on-light /
  /// near-black-on-dark.
  final Color? tint;

  /// Override the tint alpha. Range 0–1; default tuned for legibility
  /// when the host window has no native vibrancy.
  final double? tintOpacity;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.blurSigma = 24,
    this.tint,
    this.tintOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final defaultTint = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final color = (tint ?? defaultTint).withValues(
      alpha: tintOpacity ?? (isDark ? 0.55 : 0.65),
    );
    final hairline = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.10 : 0.06,
    );

    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: hairline, width: 0.5),
      ),
      child: child,
    );

    if (!isLiquidGlassPlatform) {
      // Cheap fallback: opaque rounded card. Same geometry as the
      // glass version so layout doesn't shift.
      return body;
    }

    return ClipRRect(
      borderRadius: borderRadius is BorderRadius
          ? borderRadius as BorderRadius
          : BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: body,
      ),
    );
  }
}
