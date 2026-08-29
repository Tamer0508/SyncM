import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

L? get appL10n {
  final context = navigatorKey.currentContext;
  if (context == null) return null;

  try {
    return L.of(context);
  } catch (_) {
    return null;
  }
}
