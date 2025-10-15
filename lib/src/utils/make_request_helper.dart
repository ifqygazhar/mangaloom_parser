import 'dart:convert';

import 'package:http/http.dart';

/// Helper method untuk membuat HTTP request dengan headers yang sesuai
Future<Map<String, dynamic>> helperMakeRequest({
  required String url,
  required Client client,
  required String baseUrl,
  String customUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
}) async {
  final response = await client.get(
    Uri.parse(url),
    headers: {
      'User-Agent': customUserAgent,
      'Accept': 'application/json',
      'Referer': baseUrl,
      'sec-fetch-dest': 'empty',
    },
  );

  if (response.statusCode != 200) {
    throw Exception('API returned status code: ${response.statusCode}');
  }

  return json.decode(response.body) as Map<String, dynamic>;
}
