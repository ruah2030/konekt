import 'network/api_failure.dart';

/// Résultat d'un appel de repository : succès ou [ApiFailure], sans exception.
sealed class Result<T> {
  const Result();

  R when<R>({required R Function(T value) ok, required R Function(ApiFailure failure) err}) => switch (this) {
    Ok<T>(:final value) => ok(value),
    Err<T>(:final failure) => err(failure),
  };

  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  ApiFailure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  bool get isOk => this is Ok<T>;

  /// Exécute [body] et convertit toute exception en [Err].
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } catch (e) {
      return Err(ApiFailure.from(e));
    }
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final ApiFailure failure;
}
