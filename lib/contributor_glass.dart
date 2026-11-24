import 'dart:ui';
import 'package:material_ui/material_ui.dart';

/// Reusable translucent surface. It blurs what is underneath without changing
/// data, tap handling or the contrast of child controls.
class ContributorGlass extends StatelessWidget {
  const ContributorGlass({super.key, required this.child,
    this.padding = const EdgeInsets.all(12), this.radius = 15,
    this.margin = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding, margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = dark ? const Color(0xFF436680) : const Color(0xFF98B8D1);
    return Padding(padding: margin, child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                ? [const Color(0xDE213549), const Color(0xD4132639)]
                : [const Color(0xEBF8FCFF), const Color(0xDCE6F1FA)],
            ),
            border: Border.all(color: border.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: dark ? .17 : .07),
                blurRadius: 22, offset: const Offset(0, 7)),
            ],
          ),
          child: child,
        ),
      ),
    ));
  }
}
