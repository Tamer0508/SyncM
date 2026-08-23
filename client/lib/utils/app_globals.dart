import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Словарь для мест без BuildContext: провайдеров, фоновой службы, обработчиков
/// сокета. Возвращает null, пока приложение не построило первый кадр, — звать
/// его оттуда и не нужно.
L? get appL10n {
  final context = navigatorKey.currentContext;
  if (context == null) return null;

  try {
    return L.of(context);
  } catch (_) {
    // Делегаты ещё не подключены — не повод падать.
    return null;
  }
}
