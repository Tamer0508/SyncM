import 'dart:async';
import 'dart:math';

typedef RetryPredicate = bool Function(Exception error);

Future<T> retryWithBackoff<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(milliseconds: 250),
  double jitterFactor = 0.3,
  RetryPredicate? shouldRetry,
}) async {
  final random = Random();
  Exception? lastException;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (error is! Exception) rethrow;
      lastException = error;
      final retry = shouldRetry?.call(error) ?? true;
      if (!retry || attempt >= maxAttempts - 1) {
        rethrow;
      }

      final delayMultiplier = pow(2, attempt);
      final jitter = random.nextDouble() * jitterFactor;
      final delayMs = (initialDelay.inMilliseconds * delayMultiplier * (1 + jitter)).round();
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  throw lastException ?? Exception('Retry failed after $maxAttempts attempts');
}
