import 'package:flutter_test/flutter_test.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

void main() {
  group('IkiruParser', () {
    late IkiruParser parser;

    setUp(() {
      parser = IkiruParser();
    });

    tearDown(() {
      parser.dispose();
    });

    test('fetchPopular returns results', () async {
      final results = await parser.fetchPopular();
      print('Ikiru got ${results.length} results');
      expect(results, isNotEmpty);
      final first = results.first;
      print('First: ${first.title} | ${first.href}');
      expect(first.title, isNotEmpty);
      expect(first.href, isNotEmpty);
    });

    test('fetchByGenre returns results', () async {
      final results = await parser.fetchByGenre('/genre/action/');
      print('Ikiru genre got ${results.length} results');
      expect(results, isNotEmpty);
      print('First: ${results.first.title}');
    });
  });
}
