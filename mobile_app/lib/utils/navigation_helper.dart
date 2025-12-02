import 'package:flutter/material.dart';

/// Helper class for INSTANT navigation - no delays
class NavigationHelper {
  /// INSTANT navigation - shows page immediately, no transition delay
  static Future<T?> pushFast<T extends Object?>(
    BuildContext context,
    Widget page, {
    bool maintainState = true,
    bool fullscreenDialog = false,
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // INSTANT - no animation delay
          return child;
        },
        transitionDuration: Duration.zero, // ZERO delay
        reverseTransitionDuration: Duration.zero, // ZERO delay
        maintainState: maintainState,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }

  /// INSTANT replacement - zero delay
  static Future<T?> pushReplacementFast<T extends Object?, TO extends Object?>(
    BuildContext context,
    Widget page, {
    TO? result,
  }) {
    return Navigator.of(context).pushReplacement<T, TO>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      result: result,
    );
  }

  /// INSTANT push and remove - zero delay
  static Future<T?> pushAndRemoveUntilFast<T extends Object?>(
    BuildContext context,
    Widget page,
    RoutePredicate predicate,
  ) {
    return Navigator.of(context).pushAndRemoveUntil<T>(
      PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      predicate,
    );
  }
}

