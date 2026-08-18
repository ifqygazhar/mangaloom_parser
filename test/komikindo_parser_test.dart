import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

/// Full scraping health-check for the Komikindo (ID) source.
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

  group('KomikindoParser - Full Scraping Health Check', () {
    late KomikindoParser parser;

    setUp(() {
      parser = KomikindoParser();
    });

    tearDown(() {
      parser.dispose();
    });

    test('fetchPopular', () async {
      final ok = await runScrape('fetchPopular', () async {
        final items = await parser.fetchPopular();
        // ignore: avoid_print
        print('   [Komikindo] fetchPopular -> ${items.length} items');
        expect(items, isNotEmpty);
        // ignore: avoid_print
        print('   First: ${items.first.title} | ${items.first.href}');
      });
      expect(ok, isTrue, reason: results['fetchPopular']);
    });

    test('fetchNewest', () async {
      final ok = await runScrape('fetchNewest', () async {
        final items = await parser.fetchNewest();
        // ignore: avoid_print
        print('   [Komikindo] fetchNewest -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchNewest']);
    });

    test('search', () async {
      final ok = await runScrape('search', () async {
        final items = await parser.search('solo');
        // ignore: avoid_print
        print('   [Komikindo] search -> ${items.length} items');
      });
      expect(ok, isTrue, reason: results['search']);
    });

    test('fetchGenres', () async {
      final ok = await runScrape('fetchGenres', () async {
        final genres = await parser.fetchGenres();
        // ignore: avoid_print
        print('   [Komikindo] fetchGenres -> ${genres.length} genres');
        expect(genres, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchGenres']);
    });

    test('fetchDetail + fetchChapter', () async {
      final ok = await runScrape('fetchDetail+Chapter', () async {
        final list = await parser.fetchPopular();
        expect(list, isNotEmpty);

        final detail = await parser.fetchDetail(list.first.href);
        // ignore: avoid_print
        print('   [Komikindo] fetchDetail -> "${detail.title}" | '
            '${detail.chapters.length} chapters');
        expect(detail.title, isNotEmpty);
        expect(detail.chapters, isNotEmpty);

        final chapter = await parser.fetchChapter(detail.chapters.first.href);
        // ignore: avoid_print
        print('   [Komikindo] fetchChapter -> "${chapter.title}" | '
            '${chapter.panel.length} images');
        expect(chapter.panel, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchDetail+Chapter']);
    });

    test('PRINT FINAL SUMMARY', () {
      // ignore: avoid_print
      print('\n══════════════════════════════════════════════════');
      // ignore: avoid_print
      print('   KOMIKINDO SOURCE SCRAPING SUMMARY');
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