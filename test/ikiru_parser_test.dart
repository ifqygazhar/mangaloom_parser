import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

/// Full scraping health-check for the Ikiru source.
///
/// Runs every public fetch/scrape endpoint against the live site and prints
/// whether each one succeeds. A passing test means the endpoint returned data
/// without throwing. Individual results are shown in the console.
void main() {
  final results = <String, String>{};

  Future<bool> runScrape(
    String name,
    Future<void> Function() fn,
  ) async {
    try {
      await fn();
      results[name] = '✅ SUCCESS';
      return true;
    } catch (e) {
      results[name] = '❌ FAILED: $e';
      return false;
    }
  }

  group('IkiruParser - Full Scraping Health Check', () {
    late IkiruParser parser;

    setUp(() {
      parser = IkiruParser();
    });

    test('chapterImageHeaders contains ikiru.id Referer (chapter only)', () {
      // Chapter images need Referer: ikiru.id, but thumbnails/list do NOT —
      // the Referer is intentionally scoped to chapterImageHeaders only.
      expect(parser.chapterImageHeaders['Referer'], 'https://ikiru.id/');
      expect(parser.chapterImageHeaders['User-Agent'], isNotEmpty);
      // imageHeaders (thumbnails/list) should be empty to avoid blocking them.
      expect(parser.imageHeaders['Referer'], isNull);
    });

    tearDown(() {
      parser.dispose();
    });

    test('fetchPopular', () async {
      final ok = await runScrape('fetchPopular', () async {
        final items = await parser.fetchPopular();
        // ignore: avoid_print
        print('   [Ikiru] fetchPopular -> ${items.length} items');
        expect(items, isNotEmpty);
        // ignore: avoid_print
        print('   First: ${items.first.title} | ${items.first.href}');
      });
      expect(ok, isTrue, reason: results['fetchPopular']);
    });

    test('fetchRecommended', () async {
      final ok = await runScrape('fetchRecommended', () async {
        final items = await parser.fetchRecommended();
        // ignore: avoid_print
        print('   [Ikiru] fetchRecommended -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchRecommended']);
    });

    test('fetchNewest', () async {
      final ok = await runScrape('fetchNewest', () async {
        final items = await parser.fetchNewest(page: 1);
        // ignore: avoid_print
        print('   [Ikiru] fetchNewest -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchNewest']);
    });

    test('fetchAll', () async {
      final ok = await runScrape('fetchAll', () async {
        final items = await parser.fetchAll(page: 1);
        // ignore: avoid_print
        print('   [Ikiru] fetchAll -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchAll']);
    });

    test('search', () async {
      final ok = await runScrape('search', () async {
        final items = await parser.search('one piece');
        // ignore: avoid_print
        print('   [Ikiru] search("one piece") -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['search']);
    });

    test('fetchGenres', () async {
      final ok = await runScrape('fetchGenres', () async {
        final genres = await parser.fetchGenres();
        // ignore: avoid_print
        print('   [Ikiru] fetchGenres -> ${genres.length} genres');
        expect(genres, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchGenres']);
    });

    test('fetchByGenre', () async {
      final ok = await runScrape('fetchByGenre', () async {
        final items = await parser.fetchByGenre('/genre/action/');
        // ignore: avoid_print
        print('   [Ikiru] fetchByGenre(action) -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchByGenre']);
    });

    test('fetchFiltered', () async {
      final ok = await runScrape('fetchFiltered', () async {
        final items = await parser.fetchFiltered(
          page: 1,
          type: 'Manhwa',
          order: 'update',
        );
        // ignore: avoid_print
        print('   [Ikiru] fetchFiltered -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchFiltered']);
    });

    test('fetchDetail', () async {
      final ok = await runScrape('fetchDetail', () async {
        // Grab a real href from newest for a valid detail target
        final list = await parser.fetchNewest();
        expect(list, isNotEmpty);
        final detail = await parser.fetchDetail(list.first.href);
        // ignore: avoid_print
        print('   [Ikiru] fetchDetail -> "${detail.title}" | '
            '${detail.chapters.length} chapters | genres: ${detail.genres.length}');
        expect(detail.title, isNotEmpty);
        expect(detail.chapters, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchDetail']);
    });

    test('fetchChapter', () async {
      final ok = await runScrape('fetchChapter', () async {
        // Get a real detail to obtain a chapter href
        final list = await parser.fetchNewest();
        expect(list, isNotEmpty);
        final detail = await parser.fetchDetail(list.first.href);
        expect(detail.chapters, isNotEmpty);

        final chapter = await parser.fetchChapter(detail.chapters.first.href);
        // ignore: avoid_print
        print('   [Ikiru] fetchChapter -> "${chapter.title}" | '
            '${chapter.panel.length} images');
        expect(chapter.panel, isNotEmpty);

        // Print each image URL
        for (var i = 0; i < chapter.panel.length; i++) {
          // ignore: avoid_print
          print('      [img ${i + 1}] ${chapter.panel[i]}');
        }
      });
      expect(ok, isTrue, reason: results['fetchChapter']);
    });

    test('PRINT FINAL SUMMARY', () {
      // ignore: avoid_print
      print('\n══════════════════════════════════════════════════');
      // ignore: avoid_print
      print('   IKIRU SOURCE SCRAPING SUMMARY');
      // ignore: avoid_print
      print('══════════════════════════════════════════════════');
      var pass = 0;
      results.forEach((name, status) {
        // ignore: avoid_print
        print('   $name: $status');
        if (status.startsWith('✅')) pass++;
      });
      // ignore: avoid_print
      print('══════════════════════════════════════════════════');
      // ignore: avoid_print
      print('   TOTAL: $pass/${results.length} succeeded');
      // ignore: avoid_print
      print('══════════════════════════════════════════════════\n');
    });
  });
}
