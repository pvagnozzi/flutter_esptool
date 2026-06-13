// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_error.dart';

/// Represents the outcome of an ESP operation.
sealed class Result<T> {
  /// Creates a [Result].
  const Result();

  /// Folds this result into a single value.
  R fold<R>(
      R Function(T value) onSuccess, R Function(EspError error) onFailure);

  /// Maps a success value into another result value.
  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(value: final value) => Success<R>(transform(value)),
      Failure<T>(error: final error) => Failure<R>(error),
    };
  }

  /// Whether this result is a success.
  bool get isSuccess => this is Success<T>;

  /// Whether this result is a failure.
  bool get isFailure => this is Failure<T>;

  /// Creates a successful result.
  static Result<T> success<T>(T value) => Success<T>(value);

  /// Creates a failed result.
  static Result<T> failure<T>(EspError error) => Failure<T>(error);
}

/// A successful [Result].
final class Success<T> extends Result<T> {
  /// Creates a success result.
  const Success(this.value);

  /// The successful value.
  final T value;

  @override
  R fold<R>(
      R Function(T value) onSuccess, R Function(EspError error) onFailure) {
    return onSuccess(value);
  }
}

/// A failed [Result].
final class Failure<T> extends Result<T> {
  /// Creates a failed result.
  const Failure(this.error);

  /// The failure payload.
  final EspError error;

  @override
  R fold<R>(
      R Function(T value) onSuccess, R Function(EspError error) onFailure) {
    return onFailure(error);
  }
}
