import 'package:flutter/foundation.dart';

/// Debug logger utility for printing exceptions and errors.
class DebugLogger {
  /// Logs an exception with stack trace.
  static void logException(
    dynamic exception,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? additionalInfo,
  }) {
    if (kDebugMode) {
      final buffer = StringBuffer();

      if (context != null) {
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
        buffer.writeln('Exception in: $context');
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
      } else {
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
        buffer.writeln('Exception occurred');
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
      }

      buffer.writeln('Exception: ${exception.toString()}');
      buffer.writeln('Type: ${exception.runtimeType}');

      if (additionalInfo != null && additionalInfo.isNotEmpty) {
        buffer.writeln('\nAdditional Info:');
        additionalInfo.forEach((key, value) {
          buffer.writeln('  $key: $value');
        });
      }

      if (stackTrace != null) {
        buffer.writeln('\nStack Trace:');
        buffer.writeln(stackTrace.toString());
      }

      buffer.writeln('═══════════════════════════════════════════════════════');

      debugPrint(buffer.toString());
    }
  }

  /// Logs an error with optional context.
  static void logError(
    String message, {
    String? context,
    Map<String, dynamic>? additionalInfo,
  }) {
    if (kDebugMode) {
      final buffer = StringBuffer();

      if (context != null) {
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
        buffer.writeln('Error in: $context');
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
      } else {
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
        buffer.writeln('Error occurred');
        buffer.writeln(
          '═══════════════════════════════════════════════════════',
        );
      }

      buffer.writeln('Message: $message');

      if (additionalInfo != null && additionalInfo.isNotEmpty) {
        buffer.writeln('\nAdditional Info:');
        additionalInfo.forEach((key, value) {
          buffer.writeln('  $key: $value');
        });
      }

      buffer.writeln('═══════════════════════════════════════════════════════');

      debugPrint(buffer.toString());
    }
  }

  /// Wraps an async function with exception logging.
  static Future<T> catchAsync<T>(
    Future<T> Function() fn, {
    String? context,
    T? defaultValue,
    bool shouldRethrow = false,
  }) async {
    try {
      return await fn();
    } catch (e, stackTrace) {
      logException(e, stackTrace, context: context);
      if (shouldRethrow) {
        rethrow;
      }
      if (defaultValue != null) {
        return defaultValue;
      }
      throw e;
    }
  }

  /// Wraps a sync function with exception logging.
  static T catchSync<T>(
    T Function() fn, {
    String? context,
    T? defaultValue,
    bool shouldRethrow = false,
  }) {
    try {
      return fn();
    } catch (e, stackTrace) {
      logException(e, stackTrace, context: context);
      if (shouldRethrow) {
        rethrow;
      }
      if (defaultValue != null) {
        return defaultValue;
      }
      throw e;
    }
  }
}
