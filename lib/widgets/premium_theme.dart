import 'package:flutter/material.dart';

/// Single-wallet app styling; does not import local portfolios or bots.
abstract final class PremiumColors {
  static const background = Color(0xFF07110F);
  static const panel = Color(0xFF111F1C);
  static const panelRaised = Color(0xFF172623);
  static const emerald = Color(0xFF44E5AB);
  static const emeraldDim = Color(0xFF13392E);
  static const gold = Color(0xFFE9C47A);
  static const goldDim = Color(0xFF3B3120);
  static const danger = Color(0xFFFF796F);
  static const muted = Color(0xFF99ABA5);
  static const border = Color(0xFF29433A);
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.gradient,
    this.borderColor,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: PremiumColors.panel,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? PremiumColors.border.withValues(alpha: .85)),
      boxShadow: const [BoxShadow(
        color: Color(0x26000000), blurRadius: 22,
        offset: Offset(0, 12))],
    ),
    child: child,
  );
}

class PremiumSectionTitle extends StatelessWidget {
  const PremiumSectionTitle({
    super.key, required this.title, this.trailing,
  });
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 3, height: 19,
      decoration: BoxDecoration(
        color: PremiumColors.gold,
        borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 10),
    Expanded(child: Text(title, style: const TextStyle(
      fontSize: 17, fontWeight: FontWeight.w800))),
    if (trailing != null) trailing!,
  ]);
}
