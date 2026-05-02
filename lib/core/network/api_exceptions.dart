class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  ApiException(this.message, {this.statusCode, this.cause});

  @override
  String toString() => 'ApiException(statusCode=$statusCode, message=$message)';
}

class UnauthorizedException extends ApiException {
  UnauthorizedException([super.message = 'Unauthorized']) : super(statusCode: 401);
}

class ForbiddenException extends ApiException {
  ForbiddenException([super.message = 'Forbidden']) : super(statusCode: 403);
}

