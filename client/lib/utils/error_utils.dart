import 'dart:io';
import 'dart:async';
import '../services/api_service.dart';

String getUserFriendlyError(dynamic error) {
  if (error is ApiException) {
    return error.userMessage;
  }
  if (error is SocketException) {
    return 'Нет подключения к интернету. Проверьте сеть.';
  }
  if (error is TimeoutException) {
    return 'Сервер долго не отвечает. Попробуйте позже.';
  }
  if (error is FormatException) {
    return 'Ошибка обработки данных. Попробуйте обновить.';
  }
  if (error.toString().contains('XMLHttpRequest error')) {
    return 'Ошибка сети. Проверьте соединение.';
  }
  return 'Произошла ошибка. Попробуйте снова.';
}