import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'http_client_factory.dart';

class ApiTransport {
  ApiTransport({
    http.Client? client,
    void Function()? onReachable,
    void Function(String reason)? onUnreachable,
  })  : _client = client ?? createHttpClient(),
        _onReachable = onReachable,
        _onUnreachable = onUnreachable;

  final http.Client _client;
  final void Function()? _onReachable;
  final void Function(String reason)? _onUnreachable;

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

  Future<ApiPayload> putBytes(
    Uri uri, {
    required List<int> body,
    Map<String, String>? headers,
  }) {
    final resolvedHeaders = <String, String>{...?headers};
    if (!_containsHeader(resolvedHeaders, 'Content-Type')) {
      resolvedHeaders['Content-Type'] = 'application/octet-stream';
    }

    final request = http.Request('PUT', uri)
      ..headers.addAll(resolvedHeaders)
      ..bodyBytes = body;

    return send(request);
  }

  Future<ApiPayload> send(http.BaseRequest request) {
    return _sendStreamed(
      () => _client.send(request),
    );
  }

  Future<ApiPayload> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request();
      _onReachable?.call();
      return _parseResponse(response);
    } on ApiException {
      rethrow;
    } on Exception {
      _onUnreachable?.call('Unable to reach the API.');
      throw const ApiException(
        statusCode: 0,
        message: 'Unable to reach the API.',
      );
    }
  }

  Future<ApiPayload> _sendStreamed(
    Future<http.StreamedResponse> Function() request,
  ) async {
    try {
      final response = await request();
      _onReachable?.call();
      return _parseResponse(await http.Response.fromStream(response));
    } on ApiException {
      rethrow;
    } on Exception {
      _onUnreachable?.call('Unable to reach the API.');
      throw const ApiException(
        statusCode: 0,
        message: 'Unable to reach the API.',
      );
    }
  }

  ApiPayload _parseResponse(http.Response response) {
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

  bool _containsHeader(Map<String, String> headers, String name) {
    final normalizedName = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == normalizedName) {
        return true;
      }
    }
    return false;
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
