import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

void main() {
  final parsers = <String, ComicParser Function()>{
    'Shinigami': () => ShinigamiParser(),
    'Webtoon': () => WebtoonParser(),
    'MangaPlus': () => MangaPlusParser(),
    'Komiku': () => KomikuParser(),
    'Ikiru': () => IkiruParser(),
    'Bbato': () => BbatoParser(),
  };

  for (final entry in parsers.entries) {
    group(entry.key, () {
      test('fetchNewest returns results', () async {
        final parser = entry.value();
        try {
          final results = await parser
              .fetchNewest()
              .timeout(const Duration(seconds: 30));
          // ignore: avoid_print
          print('[${entry.key}] fetchNewest -> ${results.length} items');
          expect(results, isNotEmpty);
        } catch (e) {
          // ignore: avoid_print
          print('[${entry.key}] fetchNewest FAILED -> $e');
          rethrow;
        }
      }, timeout: const Timeout(Duration(seconds: 45)));
    });
  }
}
