import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client createHttpClient({bool withCredentials = true}) {
  final client = BrowserClient()..withCredentials = withCredentials;
  return client;
}
