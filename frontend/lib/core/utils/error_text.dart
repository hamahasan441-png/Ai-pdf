import 'dart:async' show TimeoutException;
import 'dart:io' show FileSystemException, SocketException, HttpException;

import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// What went wrong, in the terms a person can act on.
enum ErrorKind { file, noSpace, network, timeout, permission, badFile, encrypted, tooLarge, unknown }

/// An exception that knows which [ErrorKind] it is (PDF reading and export
/// errors implement this), so it is shown with the right message.
abstract interface class KindedError {
  ErrorKind get errorKind;
}

ErrorKind errorKindOf(Object e) {
  if (e is KindedError) return e.errorKind;
  if (e is FileSystemException) {
    // ENOSPC: the disk is full.
    return e.osError?.errorCode == 28 ? ErrorKind.noSpace : ErrorKind.file;
  }
  if (e is TimeoutException) return ErrorKind.timeout;
  if (e is SocketException || e is HttpException) return ErrorKind.network;
  if (e is DioException) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout =>
        ErrorKind.timeout,
      DioExceptionType.connectionError => ErrorKind.network,
      _ => ErrorKind.unknown,
    };
  }
  if (e is PlatformException && (e.code.toLowerCase().contains('permission') || e.code.toLowerCase().contains('denied'))) {
    return ErrorKind.permission;
  }
  if (e is FormatException) return ErrorKind.badFile;
  if (e is OutOfMemoryError) return ErrorKind.tooLarge;
  return ErrorKind.unknown;
}

/// A short, translated message for [e] to show instead of its raw text. The
/// raw error still goes to the debug log for diagnosis.
String describeError(Object e, AppLocalizations? l10n) {
  debugPrint('error shown to user: $e');
  if (l10n == null) return 'Something went wrong. Please try again.';
  return switch (errorKindOf(e)) {
    ErrorKind.file => l10n.errorFile,
    ErrorKind.noSpace => l10n.errorNoSpace,
    ErrorKind.network => l10n.errorNetwork,
    ErrorKind.timeout => l10n.errorTimeout,
    ErrorKind.permission => l10n.errorPermission,
    ErrorKind.badFile => l10n.errorBadFile,
    ErrorKind.encrypted => l10n.errorEncrypted,
    ErrorKind.tooLarge => l10n.errorTooLarge,
    ErrorKind.unknown => l10n.errorGeneric,
  };
}
