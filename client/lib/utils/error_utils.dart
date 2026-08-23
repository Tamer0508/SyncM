import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import 'app_globals.dart';
import 'notifications.dart';

/// Текст ошибки для человека.
///
/// Локализация берётся из переданного контекста, а если его нет — из
/// навигатора: ошибку иногда показывают из провайдера, куда дерево виджетов
/// не дотягивается. Совсем без локализации остаётся последняя линия обороны —
/// английский текст, потому что он читается везде.
String getUserFriendlyError(Object? error, [BuildContext? context]) {
  final l = _localizations(context);
  if (l == null) return _fallback(error);

  if (error is String) return error;

  if (error is ApiException) {
    return _fromApiException(error, l);
  }

  if (error is SocketException) {
    return l.errorNoInternet;
  }

  if (error is http.ClientException) {
    return kIsWeb ? l.errorServerUnreachable : l.errorConnectionDropped;
  }

  if (error is TimeoutException) {
    return l.errorServerSlow;
  }

  if (error is HandshakeException) {
    return l.errorHandshake;
  }

  if (error is FormatException) {
    return l.errorBadResponse;
  }

  final text = error?.toString() ?? '';
  if (text.contains('XMLHttpRequest error') || text.contains('Failed to fetch')) {
    return l.errorNetwork;
  }

  if (text.contains('GoogleSignInException') || text.contains('PlatformException')) {
    if (isUserCancelled(error)) return l.errorSignInCancelled;
    if (text.contains('network') || text.contains('NETWORK')) {
      return l.errorGoogleUnreachable;
    }
    if (text.contains('DEVELOPER_ERROR') || text.contains('10:')) {
      return l.errorGoogleMisconfigured;
    }
    return l.errorGoogleFailed;
  }

  return l.errorGenericRetry;
}

L? _localizations(BuildContext? context) {
  final target = context ?? navigatorKey.currentContext;
  if (target == null) return null;

  try {
    return L.of(target);
  } catch (_) {
    // Дерево ещё не построено или делегаты не подключены — не повод падать
    // на показе ошибки.
    return null;
  }
}

/// Что показать, когда локализации нет вовсе.
String _fallback(Object? error) {
  if (error is String) return error;
  if (error is ApiException) {
    final server = error.serverMessage;
    if (server != null && server.isNotEmpty) return server;
    if (error.message.isNotEmpty) return error.message;
  }
  return 'Something went wrong.';
}

String _fromApiException(ApiException error, L l) {
  final server = error.serverMessage;
  final hasReadableServerMessage = server != null &&
      server.isNotEmpty &&
      server.length < 120 &&
      !server.contains('Error:') &&
      !server.contains('Exception');

  switch (error.statusCode) {
    case 401:
      return l.errorSessionExpired;
    case 403:
      return hasReadableServerMessage ? server : l.errorForbidden;
    case 404:
      return hasReadableServerMessage ? server : l.errorNotFound;
    case 409:
      return hasReadableServerMessage ? server : l.errorConflict;
    case 429:
      return l.errorTooManyRequests;
    case 502:
    case 503:
    case 504:
      return l.errorServerUnavailable;
    case 500:
      return l.errorServerFailure;
  }

  if (hasReadableServerMessage) return server;

  // error.message — служебный текст для журнала («Ошибка получения плейлистов»
  // и подобное). Человеку он ничего не объясняет и не переводится.
  return l.errorGeneric;
}

void showError(BuildContext context, Object? error, {bool force = false}) {
  if (!context.mounted) return;
  if (!force && error is ApiException && error.suppressUiNotification) return;

  if (!force && isUserCancelled(error)) return;

  showAppNotification(
    context,
    message: getUserFriendlyError(error, context),
    type: NotificationType.error,
  );
}

void showSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  showAppNotification(context, message: message, type: NotificationType.success);
}

bool isUserCancelled(Object? error) {
  final text = error?.toString().toLowerCase() ?? '';
  return text.contains('canceled') ||
      text.contains('cancelled') ||
      text.contains('sign_in_canceled') ||
      text.contains('popup_closed');
}

bool isUnauthorized(Object? error) => error is ApiException && error.statusCode == 401;
