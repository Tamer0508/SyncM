import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import 'notifications.dart';

String getUserFriendlyError(Object? error) {
  if (error is String) return error;

  if (error is ApiException) {
    return _fromApiException(error);
  }

  if (error is SocketException) {
    return 'Нет подключения к интернету. Проверьте сеть.';
  }

  if (error is http.ClientException) {
    return kIsWeb
        ? 'Не удалось связаться с сервером. Проверьте соединение.'
        : 'Соединение прервалось. Попробуйте ещё раз.';
  }

  if (error is TimeoutException) {
    return 'Сервер долго не отвечает. Попробуйте позже.';
  }

  if (error is HandshakeException) {
    return 'Не удалось установить защищённое соединение.';
  }

  if (error is FormatException) {
    return 'Сервер вернул неожиданный ответ. Попробуйте обновить.';
  }

  final text = error?.toString() ?? '';
  if (text.contains('XMLHttpRequest error') || text.contains('Failed to fetch')) {
    return 'Ошибка сети. Проверьте соединение.';
  }

  return 'Что-то пошло не так. Попробуйте снова.';
}

String _fromApiException(ApiException error) {
  final server = error.serverMessage;
  final hasReadableServerMessage = server != null &&
      server.isNotEmpty &&
      server.length < 120 &&
      !server.contains('Error:') &&
      !server.contains('Exception');

  switch (error.statusCode) {
    case 401:
      return 'Сессия истекла. Войдите заново.';
    case 403:
      return hasReadableServerMessage ? server : 'Недостаточно прав для этого действия.';
    case 404:
      return hasReadableServerMessage ? server : 'Не найдено.';
    case 409:
      return hasReadableServerMessage ? server : 'Действие уже выполняется или невозможно сейчас.';
    case 429:
      return 'Слишком много запросов. Немного подождите.';
    case 502:
    case 503:
    case 504:
      return 'Сервер временно недоступен. Попробуйте через минуту.';
    case 500:
      return 'Ошибка на сервере. Мы уже знаем о проблеме.';
  }

  if (hasReadableServerMessage) return server;
  return error.message.isNotEmpty ? error.message : 'Что-то пошло не так.';
}

void showError(BuildContext context, Object? error, {bool force = false}) {
  if (!context.mounted) return;
  if (!force && error is ApiException && error.suppressUiNotification) return;

  showAppNotification(
    context,
    message: getUserFriendlyError(error),
    type: NotificationType.error,
  );
}

void showSuccess(BuildContext context, String message) {
  if (!context.mounted) return;
  showAppNotification(context, message: message, type: NotificationType.success);
}

bool isUnauthorized(Object? error) => error is ApiException && error.statusCode == 401;