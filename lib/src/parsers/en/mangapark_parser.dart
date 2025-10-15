import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';

class MangaParkParser extends ComicParser {
  static const String _baseUrl = 'https://comicpark.to';

  final http.Client _client;

  // NSFW tags yang akan difilter
  static const Map<String, bool> _nsfwTags = {
    'hentai': true,
    'adult': false,
    'mature': false,
    'smut': true,
    'ecchi': false,
    'gore': true,
    'bloody': true,
  };

  MangaParkParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'MangaPark';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'EN';

  /// Helper to check if content has NSFW tags
  bool _hasNSFWContent(List<String> tags) {
    for (final tag in tags) {
      final cleanTag = tag.toLowerCase().trim();
      if (_nsfwTags.containsKey(cleanTag) && _nsfwTags[cleanTag] == true) {
        return true;
      }
    }
    return false;
  }

  /// Helper to extract tags from elements
  List<String> _extractTags(Element element, String selector) {
    final tags = <String>[];
    for (final el in element.querySelectorAll(selector)) {
      final tag = el.text.trim().toLowerCase();
      if (tag.isNotEmpty) {
        tags.add(tag);
      }
    }
    return tags;
  }

  /// Helper to parse comic items from HTML
  List<ComicItem> _parseComicItems(Document doc) {
    final items = <ComicItem>[];
    final elements = doc.querySelectorAll('div.grid.gap-5 div.flex.border-b');

    for (final el in elements) {
      final href = el.querySelector('a')?.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;

      // Extract tags to check for NSFW
      final tags = _extractTags(el, 'span.whitespace-nowrap');
      if (_hasNSFWContent(tags)) continue;

      final title = el.querySelector('h3')?.text.trim() ?? '';
      if (title.isEmpty) continue;

      final thumbnail =
          "$baseUrl/${el.querySelector('img')?.attributes['src']?.trim() ?? ''}";
      final ratingText =
          el.querySelector('span.text-yellow-500')?.text.trim() ?? '';

      // Parse rating - convert from x/10 format
      String rating = '';
      if (ratingText.isNotEmpty) {
        final match = RegExp(r'[\d.]+').firstMatch(ratingText);
        if (match != null) {
          final val = double.tryParse(match.group(0) ?? '');
          if (val != null) {
            rating = val.toStringAsFixed(1);
          }
        }
      }

      items.add(
        ComicItem(
          title: title,
          href: _trimPrefix(href),
          thumbnail: thumbnail.isNotEmpty ? thumbnail : '',
          rating: rating,
        ),
      );
    }

    return items;
  }

  /// Helper to trim URL prefix
  String _trimPrefix(String url) {
    if (url.startsWith(_baseUrl)) {
      return url.substring(_baseUrl.length);
    }
    return url;
  }

  /// Helper to make HTTP request and parse HTML
  Future<Document> _fetchAndParse(String url) async {
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to load page: ${response.statusCode}');
    }

    return html_parser.parse(response.body);
  }

  @override
  Future<List<ComicItem>> fetchPopular() async {
    final url = '$_baseUrl/search?sortby=views_d000';
    final doc = await _fetchAndParse(url);
    return _parseComicItems(doc);
  }

  @override
  Future<List<ComicItem>> fetchRecommended() async {
    final url = '$_baseUrl/search?sortby=views_d000';
    final doc = await _fetchAndParse(url);
    return _parseComicItems(doc);
  }

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final url = '$_baseUrl/search?sortby=field_update&page=$page';
    final doc = await _fetchAndParse(url);

    // Check for no results
    final gridContainer = doc.querySelector('div.grid.gap-5');
    if (gridContainer == null || gridContainer.children.isEmpty) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    final url = '$_baseUrl/search?sortby=field_score&page=$page';
    final doc = await _fetchAndParse(url);

    final gridContainer = doc.querySelector('div.grid.gap-5');
    if (gridContainer == null || gridContainer.children.isEmpty) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items;
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    // Exclude NSFW genres in search
    final url = '$_baseUrl/search?word=$encodedQuery';
    final doc = await _fetchAndParse(url);

    final gridContainer = doc.querySelector('div.grid.gap-5');
    if (gridContainer == null || gridContainer.children.isEmpty) {
      throw Exception('No results found');
    }

    final items = _parseComicItems(doc);
    if (items.isEmpty) {
      throw Exception('No results found');
    }

    return items;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final url = '$_baseUrl/search?genres=$genre&sortby=field_score&page=$page';
    final doc = await _fetchAndParse(url);

    final gridContainer = doc.querySelector('div.grid.gap-5');
    if (gridContainer == null || gridContainer.children.isEmpty) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items;
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    final genreParam = genre ?? '';
    final statusParam = status ?? '';
    final typeParam = type ?? '';
    final orderParam = order ?? 'field_score';

    final url =
        '$_baseUrl/search?genres=$genreParam,$typeParam&status=$statusParam&sortby=$orderParam&page=$page';
    final doc = await _fetchAndParse(url);

    final gridContainer = doc.querySelector('div.grid.gap-5');
    if (gridContainer == null || gridContainer.children.isEmpty) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items;
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    final url = '$_baseUrl/search';
    final doc = await _fetchAndParse(url);

    final genres = <Genre>[];
    final seen = <String>{};

    // Find div.flex-col that contains "Genres" text, then get genre elements
    Element? genresContainer;

    for (final div in doc.querySelectorAll('div.flex-col')) {
      // Check if this div contains "Genres" text
      if (div.text.contains('Genres')) {
        genresContainer = div;
        break;
      }
    }

    // If we found the genres container, extract genre elements from it
    if (genresContainer != null) {
      final genreElements = genresContainer.querySelectorAll(
        'div.whitespace-nowrap',
      );

      for (final el in genreElements) {
        final title =
            el.querySelector('span.whitespace-nowrap')?.text.trim() ?? '';
        final key = el.attributes['q:key']?.trim() ?? '';

        if (title.isEmpty || key.isEmpty) continue;

        // Skip NSFW genres
        if (_nsfwTags.containsKey(title.toLowerCase()) &&
            _nsfwTags[title.toLowerCase()] == true) {
          continue;
        }

        // Avoid duplicates
        if (seen.contains(key)) continue;
        seen.add(key);

        genres.add(Genre(title: title, href: '/$key/'));
      }
    }

    return genres;
  }

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    // Build URL
    String url = href;
    if (!href.startsWith('http')) {
      final cleanHref = href.startsWith('/') ? href : '/$href';
      url = '$_baseUrl$cleanHref';
    }

    final doc = await _fetchAndParse(url);

    // Extract title
    String title = doc.querySelector('h3.text-lg')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = doc.querySelector('div[q\\:key="tz_6"] h3')?.text.trim() ?? '';
    }

    if (title.isEmpty) {
      throw Exception('Comic not found');
    }

    // Alternative title
    String altTitle = '';
    final altElements = doc.querySelectorAll('div[q\\:key="tz_2"] span');
    if (altElements.isNotEmpty) {
      final firstAlt = altElements.first.text.trim();
      if (!firstAlt.contains('/')) {
        altTitle = firstAlt;
      }
    }

    // Thumbnail
    String thumbnail =
        doc
            .querySelector('div[q\\:key="17_2"] img')
            ?.attributes['src']
            ?.trim() ??
        '';
    if (thumbnail.isEmpty) {
      thumbnail =
          doc.querySelector('img[alt]')?.attributes['src']?.trim() ?? '';
    }
    if (thumbnail.isNotEmpty && !thumbnail.startsWith('http')) {
      thumbnail = '$_baseUrl$thumbnail';
    }

    // Description
    final descParts = <String>[];
    for (final el in doc.querySelectorAll(
      'react-island div.limit-html div.limit-html-p',
    )) {
      final text = el.text.trim();
      if (text.isNotEmpty && !text.startsWith('Included one-shot')) {
        descParts.add(text);
      }
    }
    final description = descParts.join('\n');

    // Status
    String status = '';
    for (final el in doc.querySelectorAll(
      'div[q\\:key="Yn_8"] span.font-bold',
    )) {
      status = el.text.trim();
      if (status.isNotEmpty) break;
    }

    // Author
    final authors = <String>[];
    final authorElements = doc.querySelectorAll('div[q\\:key="tz_4"] a');
    for (var i = 0; i < authorElements.length && i < 3; i++) {
      final authorText = authorElements[i].text.trim();
      if (authorText.isNotEmpty) {
        authors.add(authorText);
      }
    }
    final author = authors.join(', ');

    // Rating - Using Total Views
    String rating = '';
    for (final el in doc.querySelectorAll(
      'div[q\\:key="jN_2"] div.flex.flex-wrap span',
    )) {
      final text = el.text.trim();
      if (text.startsWith('Total:')) {
        rating = text.substring(6).trim();
        break;
      }
    }

    // Genres - with NSFW filter
    final genres = <Genre>[];
    for (final el in doc.querySelectorAll(
      'div[q\\:key="30_2"] span.whitespace-nowrap',
    )) {
      final genreTitle = el.text.trim();
      if (genreTitle.isEmpty) continue;

      // Skip NSFW genres
      if (_nsfwTags.containsKey(genreTitle.toLowerCase()) &&
          _nsfwTags[genreTitle.toLowerCase()] == true) {
        continue;
      }

      genres.add(
        Genre(title: genreTitle, href: '/${genreTitle.toLowerCase()}/'),
      );
    }

    // Type from first genre
    final type = genres.isNotEmpty ? genres.first.title : '';

    // Chapters
    final chapters = <Chapter>[];
    for (final el in doc.querySelectorAll(
      'div[data-name="chapter-list"] div.group > div[q\\:key]',
    )) {
      final chTitle = el.querySelector('a')?.text.trim() ?? '';
      final chHref = el.querySelector('a')?.attributes['href']?.trim() ?? '';

      // Extract date from time element
      String chDate = '';
      final timeEl = el.querySelector('time span[data-passed]');
      if (timeEl != null) {
        chDate = timeEl.text.trim();
      }

      if (chTitle.isEmpty || chHref.isEmpty) continue;

      chapters.add(
        Chapter(title: chTitle, href: _trimPrefix(chHref), date: chDate),
      );
    }

    // Reverse chapters order (oldest first)
    final reversedChapters = chapters.reversed.toList();

    // Latest chapter
    final latestChapter = chapters.isNotEmpty ? chapters.first.title : '';

    return ComicDetail(
      href: _trimPrefix(href),
      title: title,
      altTitle: altTitle,
      thumbnail: thumbnail,
      description: description,
      status: status,
      type: type,
      author: author,
      rating: rating,
      latestChapter: latestChapter,
      genres: genres,
      chapters: reversedChapters,
      released: '', // MangaPark doesn't have released date in the same format
      updatedOn: '', // Could be extracted if needed
    );
  }

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    // Build URL
    String url = href;
    if (!href.startsWith('http')) {
      final cleanHref = href.startsWith('/') ? href : '/$href';
      url = '$_baseUrl$cleanHref';
    }

    final response = await _client.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    // Extract title
    String title = doc.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = doc.querySelector('h2')?.text.trim() ?? '';
    }
    if (title.isEmpty) {
      title = doc.querySelector('h3')?.text.trim() ?? '';
    }

    // Extract navigation
    String prev = '';
    String next = '';

    // Prev Chapter - look for button with q:key="0B_11"
    final prevElements = doc.querySelectorAll(
      'a.btn.btn-sm.btn-outline.btn-primary[q\\:key="0B_11"]',
    );
    for (final el in prevElements) {
      final prevHref = el.attributes['href']?.trim() ?? '';
      if (prevHref.contains('/title/')) {
        // Make sure it's not just linking to detail page
        final parts = prevHref.split('/');
        if (parts.length > 2 && prevHref != parts.sublist(0, 3).join('/')) {
          prev = _trimPrefix(prevHref);
          break;
        }
      }
    }

    // Fallback for prev
    if (prev.isEmpty) {
      final prevFallback = doc.querySelectorAll('a.btn[q\\:key="0B_11"]');
      for (final el in prevFallback) {
        final prevHref = el.attributes['href']?.trim() ?? '';
        if (prevHref.isNotEmpty && prevHref.contains('/title/')) {
          prev = _trimPrefix(prevHref);
          break;
        }
      }
    }

    // Next Chapter - look for button with q:key="0B_15"
    final nextElements = doc.querySelectorAll(
      'a.btn.btn-sm.btn-outline.btn-primary[q\\:key="0B_15"]',
    );
    for (final el in nextElements) {
      final nextHref = el.attributes['href']?.trim() ?? '';
      if (nextHref.contains('/title/')) {
        // Make sure it's not just linking to detail page
        final parts = nextHref.split('/');
        if (parts.length > 2 && nextHref != parts.sublist(0, 3).join('/')) {
          next = _trimPrefix(nextHref);
          break;
        }
      }
    }

    // Check if this is the last chapter (button becomes "Back to Detail" with q:key="0B_17")
    if (next.isEmpty) {
      final backButton = doc.querySelectorAll('a.btn[q\\:key="0B_17"]');
      for (final el in backButton) {
        final backHref = el.attributes['href']?.trim() ?? '';
        // If it's a detail page link (no chapter number), it means this is the last chapter
        if (backHref.contains('/title/') &&
            !backHref.contains('-ch-') &&
            !RegExp(r'/\d+$').hasMatch(backHref)) {
          next = ''; // Last chapter
          break;
        }
      }
    }

    // Extract images from script tags
    final panels = <String>[];
    final seen = <String>{};

    for (final script in doc.querySelectorAll('script')) {
      final scriptText = script.text;

      // Skip if doesn't contain relevant content
      if (!scriptText.contains('comic-') && !scriptText.contains('manga-')) {
        continue;
      }

      // Find all image URLs
      final regex = RegExp(
        r'"(https?://[^"]+\.(?:jpg|jpeg|jfif|pjpeg|pjp|png|webp|avif|gif)[^"]*)"',
      );
      final matches = regex.allMatches(scriptText);

      for (final match in matches) {
        if (match.groupCount > 0) {
          final imgUrl = match.group(1) ?? '';
          if (imgUrl.isNotEmpty && !seen.contains(imgUrl)) {
            panels.add(imgUrl);
            seen.add(imgUrl);
          }
        }
      }
    }

    if (panels.isEmpty) {
      throw Exception('Failed to extract chapter images');
    }

    return ReadChapter(title: title, prev: prev, next: next, panel: panels);
  }

  /// Dispose HTTP client
  void dispose() {
    _client.close();
  }
}
