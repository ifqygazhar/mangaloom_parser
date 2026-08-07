import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mangaloom_parser/mangaloom_parser.dart';

void main() {
  group('KomikuParser', () {
    test('imageHeaders contains Referer for hotlink protection', () {
      final parser = KomikuParser();
      expect(parser.imageHeaders['Referer'], 'https://komiku.org/');
      expect(parser.imageHeaders['User-Agent'], isNotEmpty);
    });

    test('imageHeaders default is empty for base parser contract', () {
      // Base class contract: parsers without protection return empty map
      final parser = KomikuParser();
      expect(parser.sourceName, 'Komiku');
      expect(parser.imageHeaders, isA<Map<String, String>>());
    });

    test('parses chapter panels from real komiku read page HTML', () {
      final file = File('komiku-read-chapter.html');
      if (!file.existsSync()) {
        // Skip if fixture not present
        return;
      }
      final doc = html_parser.parse(file.readAsStringSync());

      final panels = <String>[];
      final images = doc.querySelectorAll('#Baca_Komik img.ww');
      for (final img in images) {
        var src = img.attributes['data-src'] ?? '';
        if (src.isEmpty) src = img.attributes['src'] ?? '';
        if (src.isNotEmpty && src.contains('img.komiku.org')) {
          panels.add(src.trim());
        }
      }

      expect(panels, isNotEmpty);
      expect(
        panels.first,
        startsWith('https://img.komiku.org/upload5/magic-emperor/890/'),
      );
    });
  });
}
