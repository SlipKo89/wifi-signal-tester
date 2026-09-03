import 'package:flutter/material.dart';

/// Shared screen/sheet inset policy.
///
/// Android edge-to-edge layouts may draw the Scaffold body behind the gesture
/// or three-button navigation area. Every app screen wraps its body with this
/// widget so the last row remains scrollable fully above system controls. A
/// small minimum gap also keeps content from touching the edge on desktop.
class AppSafeArea extends StatelessWidget {
  final Widget child;

  const AppSafeArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        maintainBottomViewPadding: true,
        child: child,
      );
}
