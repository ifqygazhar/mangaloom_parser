import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

/// Full scraping health-check for the FlameComics (EN) source.
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

  group('FlameComicsParser - Full Scraping Health Check', () {
    late FlameComicsParser parser;

    setUp(() {
      parser = FlameComicsParser();
    });

    tearDown(() {
      parser.dispose();
    });

    test('fetchPopular', () async {
      final ok = await runScrape('fetchPopular', () async {
        final items = await parser.fetchPopular();
        // ignore: avoid_print
        print('   [FlameComics] fetchPopular -> ${items.length} items');
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
        print('   [FlameComics] fetchNewest -> ${items.length} items');
        expect(items, isNotEmpty);
      });
      expect(ok, isTrue, reason: results['fetchNewest']);
    });

    test('search', () async {
      final ok = await runScrape('search', () async {
        final items = await parser.search('30 years');
        // ignore: avoid_print
        print('   [FlameComics] search -> ${items.length} items');
      });
      expect(ok, isTrue, reason: results['search']);
    });

    test('fetchDetail + fetchChapter', () async {
      final ok = await runScrape('fetchDetail+Chapter', () async {
        final list = await parser.fetchPopular();
        expect(list, isNotEmpty);

        final detail = await parser.fetchDetail(list.first.href);
        // ignore: avoid_print
        print('   [FlameComics] fetchDetail -> "${detail.title}" | '
            '${detail.chapters.length} chapters');
        expect(detail.title, isNotEmpty);

        if (detail.chapters.isNotEmpty) {
          final chapter = await parser.fetchChapter(detail.chapters.first.href);
          // ignore: avoid_print
          print('   [FlameComics] fetchChapter -> "${chapter.title}" | '
              '${chapter.panel.length} images');
          expect(chapter.panel, isNotEmpty);
          for (var i = 0; i < (chapter.panel.length > 2 ? 2 : chapter.panel.length); i++) {
            // ignore: avoid_print
            print('      [img ${i + 1}] ${chapter.panel[i]}');
          }
        }
      });
      expect(ok, isTrue, reason: results['fetchDetail+Chapter']);
    });

    test('PRINT FINAL SUMMARY', () {
      // ignore: avoid_print
      print('\n══════════════════════════════════════════════════');
      // ignore: avoid_print
      print('   FLAMECOMICS SOURCE SCRAPING SUMMARY');
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