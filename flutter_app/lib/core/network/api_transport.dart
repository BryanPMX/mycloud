import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'http_client_factory.dart';

class ApiTransport {
  ApiTransport({http.Client? client}) : _client = client ?? createHttpClient();

  final http.Client _client;

  Future<ApiPayload> get(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return _send(
      () => _client.get(uri, headers: headers),
    );
  }

  Future<ApiPayload> postJson(
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) {
    return _send(
      () => _client.post(
        uri,
        headers: _jsonHeaders(headers),
        body: jsonEncode(body ?? const <String, Object?>{}),
      ),
    );
  }

  Future<ApiPayload> patchJson(
    Uri uri, {
    required Object body,
    Map<String, String>? headers,
  }) {
    return _send(
      () => _client.patch(
        uri,
        headers: _jsonHeaders(headers),
        body: jsonEncode(body),
      ),
    );
  }

  Future<ApiPayload> delete(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return _send(
      () => _client.delete(uri, headers: headers),
    );
  }

  Future<ApiPayload> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request();
      final payload = _decodeBody(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          statusCode: response.statusCode,
          message: _messageFromPayload(payload),
          code: _codeFromPayload(payload),
        );
      }

      return ApiPayload(
        statusCode: response.statusCode,
        headers: response.headers,
        body: payload,
      );
    } on ApiException {
      rethrow;
    } on Exception {
      throw const ApiException(
        statusCode: 0,
        message: 'Unable to reach the API.',
      );
    }
  }

  Map<String, String> _jsonHeaders(Map<String, String>? headers) {
    return <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };
  }

  Object? _decodeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return jsonDecode(trimmed);
  }

  String _messageFromPayload(Object? payload) {
    if (payload is Map<String, dynamic>) {
      final message = payload['error'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }

    return 'Request failed.';
  }

  String? _codeFromPayload(Object? payload) {
    if (payload is Map<String, dynamic>) {
      final code = payload['code'];
      if (code is String && code.trim().isNotEmpty) {
        return code;
      }
    }

    return null;
  }

  void dispose() {
    _client.close();
  }
}

class ApiPayload {
  const ApiPayload({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Object? body;

  Map<String, dynamic> asMap() {
    if (body is Map<String, dynamic>) {
      return body! as Map<String, dynamic>;
    }

    throw const FormatException('Expected a JSON object response.');
  }
}
