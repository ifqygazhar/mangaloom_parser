import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

/// Full scraping health-check for the Bbato (EN) source.
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
    // bbato.com intermittently drops connections; retry a couple of times so
    // transient network failures don't mask a real parser/selector bug.
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await fn();
        results[name] = '✅ SUCCESS';
        return true;
      } catch (e) {
        lastError = e;
        // ignore: avoid_print
        print('   [Bbato] $name attempt $attempt/$maxAttempts failed: $e');
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    results[name] = '❌ FAILED: $lastError';
    return false;
  }

  group('BbatoParser - Full Scraping Health Check', () {
    late BbatoParser parser;

    setUp(() {
      parser = BbatoParser();
    });

    tearDown(() {
      parser.dispose();
    });

    test('imageHeaders contains bbato.com Referer', () {
      // CDN (cdn2.merrypsycho.xyz) blocks image requests without the
      // correct Referer (403). Root referer bypasses the CDN block.
      expect(parser.sourceName, 'Bbato');
      expect(parser.language, 'EN');
      expect(parser.imageHeaders['Referer'], 'https://bbato.com/');
      expect(parser.imageHeaders['User-Agent'], isNotEmpty);
    });

    test('fetchPopular', () async {
      final ok = await runScrape('fetchPopular', () async {
        final items = await parser.fetchPopular();
        // ignore: avoid_print
        print('   [Bbato] fetchPopular -> ${items.length} items');
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
        print('   [Bbato] fetchRecommended -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchRecommended']);
    });

    test('fetchNewest', () async {
      final ok = await runScrape('fetchNewest', () async {
        final items = await parser.fetchNewest(page: 1);
        // ignore: avoid_print
        print('   [Bbato] fetchNewest -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchNewest']);
    });

    test('search', () async {
      final ok = await runScrape('search', () async {
        final items = await parser.search('one piece');
        // ignore: avoid_print
        print('   [Bbato] search("one piece") -> ${items.length} items');
      });
      expect(ok, isTrue, reason: results['search']);
    });

    test('fetchGenres', () async {
      final ok = await runScrape('fetchGenres', () async {
        final genres = await parser.fetchGenres();
        // ignore: avoid_print
        print('   [Bbato] fetchGenres -> ${genres.length} genres');
        expect(genres, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchGenres']);
    });

    test('fetchByGenre', () async {
      final ok = await runScrape('fetchByGenre', () async {
        final items = await parser.fetchByGenre('/action/');
        // ignore: avoid_print
        print('   [Bbato] fetchByGenre(action) -> ${items.length} items');
      });
      expect(ok, isTrue, reason: results['fetchByGenre']);
    });

    test('fetchFiltered', () async {
      final ok = await runScrape('fetchFiltered', () async {
        final items = await parser.fetchFiltered(
          page: 1,
          genre: 'action',
          status: 'ongoing',
          type: 'manga',
          order: 'recently_updated',
        );
        // ignore: avoid_print
        print('   [Bbato] fetchFiltered -> ${items.length} items');
      });
      expect(ok, isTrue, reason: results['fetchFiltered']);
    });

    test('fetchDetail', () async {
      final ok = await runScrape('fetchDetail', () async {
        // Grab a real href from newest
        final list = await parser.fetchNewest();
        expect(list, isNotEmpty);
        final detail = await parser.fetchDetail(list.first.href);
        // ignore: avoid_print
        print('   [Bbato] fetchDetail -> "${detail.title}" | '
            '${detail.chapters.length} chapters | genres: ${detail.genres.length}');
        expect(detail.title, isNotEmpty);
        expect(detail.chapters, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchDetail']);
    });

    test('fetchChapter', () async {
      final ok = await runScrape('fetchChapter', () async {
        final list = await parser.fetchNewest();
        expect(list, isNotEmpty);
        final detail = await parser.fetchDetail(list.first.href);
        expect(detail.chapters, isNotEmpty);

        final chapter = await parser.fetchChapter(detail.chapters.first.href);
        // ignore: avoid_print
        print('   [Bbato] fetchChapter -> "${chapter.title}" | '
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
      print('   BBATO SOURCE SCRAPING SUMMARY');
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
