import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';

class ComicSansParser extends ComicParser {
  static const String _baseUrl = 'https://lc3.cosmicscans.asia';
  static const String _mangaPrefix = '$_baseUrl/manga';

  final http.Client _client;

  // Cache untuk list results dengan expiry time
  final Map<String, CachedResult> _listCache = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // Limit concurrent requests untuk batch operations
  static const int _maxConcurrentRequests = 3;

  ComicSansParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'ComicSans';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'ID';

  /// Check if cache is valid
  bool _isCacheValid(String key) {
    final cached = _listCache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < _cacheExpiry;
  }

  /// Get from cache
  List<ComicItem>? _getFromCache(String key) {
    if (_isCacheValid(key)) {
      return _listCache[key]?.items;
    }
    _listCache.remove(key);
    return null;
  }

  /// Save to cache
  void _saveToCache(String key, List<ComicItem> items) {
    _listCache[key] = CachedResult(items: items, timestamp: DateTime.now());
  }

  /// Helper to parse comic items from HTML
  List<ComicItem> _parseComicItems(Document doc, String prefix) {
    final items = <ComicItem>[];
    final elements = doc.querySelectorAll('.listupd .bsx a');

    for (final el in elements) {
      final href = el.attributes['href']?.trim() ?? '';

      // Get title from .bigor .tt or fallback to title attribute
      var title = el.querySelector('.bigor .tt')?.text.trim() ?? '';
      if (title.isEmpty) {
        title = el.attributes['title']?.trim() ?? '';
      }

      final thumbnail =
          el.querySelector('.limit img')?.attributes['src']?.trim() ?? '';
      final type = el.querySelector('.limit .type')?.text.trim() ?? '';
      final chapter = el.querySelector('.epxs')?.text.trim() ?? '';
      final rating = el.querySelector('.numscore')?.text.trim() ?? '';

      if (href.isNotEmpty && title.isNotEmpty) {
        items.add(
          ComicItem(
            title: title,
            href: _trimPrefix(href, prefix),
            thumbnail: thumbnail,
            type: type,
            chapter: chapter,
            rating: rating,
          ),
        );
      }
    }

    return items;
  }

  /// Helper to trim URL prefix
  String _trimPrefix(String url, String prefix) {
    if (url.startsWith(prefix)) {
      return url.substring(prefix.length);
    }
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
    const cacheKey = 'popular-1';

    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$_baseUrl/manga/?page=1&status=&type=&order=popular';
    final doc = await _fetchAndParse(url);
    final results = _parseComicItems(doc, _mangaPrefix);

    // Save to cache
    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchRecommended() async {
    const cacheKey = 'recommended-1';

    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$_baseUrl/manga/?page=1&status=&type=&order=update';
    final doc = await _fetchAndParse(url);
    final results = _parseComicItems(doc, _mangaPrefix);

    // Save to cache
    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final cacheKey = 'newest-$page';

    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$_baseUrl/manga/?page=$page&status=&type=&order=latest';
    final doc = await _fetchAndParse(url);

    // Check for "no result"
    final noResult = doc.querySelector('.listupd center.noresult');
    if (noResult != null) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc, _mangaPrefix);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Save to cache
    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    final cacheKey = 'all-$page';

    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$_baseUrl/manga/?page=$page&status=&type=&order=';
    final doc = await _fetchAndParse(url);

    final noResult = doc.querySelector('.listupd center.noresult');
    if (noResult != null) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc, _mangaPrefix);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Save to cache
    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final cacheKey = 'search-$encodedQuery';

    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$_baseUrl/?s=$encodedQuery';
    final doc = await _fetchAndParse(url);

    // Check for "no result" message
    final noResult = doc.querySelector('.listupd center h3');
    if (noResult != null) {
      throw Exception('No results found');
    }

    final items = _parseComicItems(doc, _mangaPrefix);
    if (items.isEmpty) {
      throw Exception('No results found');
    }

    // Save to cache
    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    return fetchFiltered(page: page, genre: genre, order: 'popular');
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    // Build cache key from parameters
    final cacheKey = 'filtered-$page-$genre-$status-$type-$order';

    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final genreParam = genre ?? '';
    final statusParam = status ?? '';
    final typeParam = type ?? '';
    final orderParam = order ?? '';

    final url =
        '$_baseUrl/manga/?page=$page&genre[]=$genreParam&status=$statusParam&type=$typeParam&order=$orderParam';
    final doc = await _fetchAndParse(url);

    final noResult = doc.querySelector('.listupd center.noresult');
    if (noResult != null) {
      throw Exception('Page not found');
    }

    final items = _parseComicItems(doc, _mangaPrefix);
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Save to cache
    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    final url = '$_baseUrl/manga/';
    final doc = await _fetchAndParse(url);

    final genres = <Genre>[];
    final elements = doc.querySelectorAll('ul.dropdown-menu.c4.genrez li');

    for (final el in elements) {
      final value =
          el.querySelector('input.genre-item')?.attributes['value']?.trim() ??
          '';
      final title = el.querySelector('label')?.text.trim() ?? '';

      if (value.isEmpty) continue;

      // Remove negative sign and use clean value as href
      final cleanVal = value.replaceFirst('-', '');
      final href = '/$cleanVal/';

      genres.add(Genre(title: title.isNotEmpty ? title : value, href: href));
    }

    return genres;
  }

  /// Batch fetch multiple lists efficiently
  Future<Map<String, List<ComicItem>>> fetchMultipleLists({
    bool popular = false,
    bool recommended = false,
    bool newest = false,
    int limit = 6,
  }) async {
    final Map<String, List<ComicItem>> results = {};
    final List<Future<void>> futures = [];

    if (popular) {
      futures.add(
        fetchPopular().then((items) {
          results['popular'] = items.take(limit).toList();
        }),
      );
    }

    if (recommended) {
      futures.add(
        fetchRecommended().then((items) {
          results['recommended'] = items.take(limit).toList();
        }),
      );
    }

    if (newest) {
      futures.add(
        fetchNewest().then((items) {
          results['newest'] = items.take(limit).toList();
        }),
      );
    }

    // Wait for all requests to complete
    await Future.wait(futures);

    return results;
  }

  /// Fetch multiple genres in batch
  Future<Map<String, List<ComicItem>>> fetchMultipleGenres(
    List<String> genres, {
    int limit = 6,
  }) async {
    final Map<String, List<ComicItem>> results = {};

    // Limit concurrent requests
    for (var i = 0; i < genres.length; i += _maxConcurrentRequests) {
      final batch = genres.skip(i).take(_maxConcurrentRequests);
      final futures = batch.map((genre) async {
        try {
          final items = await fetchByGenre(genre);
          results[genre] = items.take(limit).toList();
        } catch (e) {
          results[genre] = [];
        }
      });

      await Future.wait(futures);
    }

    return results;
  }

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    final url = '$_baseUrl/manga/$href';
    final doc = await _fetchAndParse(url);

    final article = doc.querySelector('article.hentry');
    if (article == null) {
      throw Exception('Comic not found');
    }

    // Extract basic info
    final title = article.querySelector('h1.entry-title')?.text.trim() ?? '';

    // Alternative title - find the b tag containing "Alternative Titles"
    String altTitle = '';
    for (final b in article.querySelectorAll('.wd-full b')) {
      if (b.text.contains('Alternative Titles')) {
        altTitle = b.nextElementSibling?.text.trim() ?? '';
        break;
      }
    }

    final thumbnail =
        article
            .querySelector('.thumbook .thumb img')
            ?.attributes['src']
            ?.trim() ??
        '';

    final description =
        article.querySelector('.entry-content-single')?.text.trim() ?? '';

    // Status - find .imptdt that contains "Status" text
    String status = '';
    for (final imptdt in article.querySelectorAll('.tsinfo .imptdt')) {
      if (imptdt.text.contains('Status')) {
        status = imptdt.querySelector('i')?.text.trim() ?? '';
        break;
      }
    }

    // Type - find .imptdt that contains "Type" text
    String type = '';
    for (final imptdt in article.querySelectorAll('.tsinfo .imptdt')) {
      if (imptdt.text.contains('Type')) {
        type = imptdt.querySelector('a')?.text.trim() ?? '';
        break;
      }
    }

    // Released - find .fmed that contains "Released" text
    String released = '';
    for (final fmed in article.querySelectorAll('.fmed')) {
      if (fmed.text.contains('Released')) {
        released = fmed.querySelector('span')?.text.trim() ?? '';
        break;
      }
    }

    // Author - find .fmed that contains "Author" text
    String author = '';
    for (final fmed in article.querySelectorAll('.fmed')) {
      if (fmed.text.contains('Author')) {
        author = fmed.querySelector('span')?.text.trim() ?? '';
        break;
      }
    }

    // Updated On - find .fmed that contains "Updated On" text
    String updatedOn = '';
    for (final fmed in article.querySelectorAll('.fmed')) {
      if (fmed.text.contains('Updated On')) {
        final timeEl = fmed.querySelector('span time');
        if (timeEl != null) {
          updatedOn = timeEl.attributes['datetime']?.trim() ?? '';
        }
        if (updatedOn.isEmpty) {
          updatedOn = fmed.querySelector('span')?.text.trim() ?? '';
        }
        break;
      }
    }

    var rating =
        article
            .querySelector('.rating-prc .num')
            ?.attributes['content']
            ?.trim() ??
        '';
    if (rating.isEmpty) {
      rating = article.querySelector('.rating-prc .num')?.text.trim() ?? '';
    }

    // Extract genres
    final genres = <Genre>[];

    // Find the .wd-full div that contains "Genres"
    for (final wdFull in article.querySelectorAll('.wd-full')) {
      if (wdFull.text.contains('Genres') || wdFull.text.contains('Genre')) {
        final genreElements = wdFull.querySelectorAll('.mgen a');
        final genrePrefix = '$_baseUrl/genres';

        for (final el in genreElements) {
          final genreTitle = el.text.trim();
          final genreHref = el.attributes['href']?.trim() ?? '';

          if (genreTitle.isNotEmpty) {
            genres.add(
              Genre(
                title: genreTitle,
                href: _trimPrefix(genreHref, genrePrefix),
              ),
            );
          }
        }
        break;
      }
    }

    // Latest chapter - find .inepcx that contains "New Chapter"
    String latestChapter = '';
    for (final inepcx in article.querySelectorAll('.lastend .inepcx')) {
      if (inepcx.text.contains('New Chapter') ||
          inepcx.text.contains('Chapter')) {
        latestChapter = inepcx.querySelector('.epcurlast')?.text.trim() ?? '';
        if (latestChapter.isNotEmpty) break;
      }
    }

    // Extract chapters
    final chapters = <Chapter>[];
    final chapterElements = article.querySelectorAll('.eplister ul.clstyle li');

    for (final el in chapterElements) {
      final chapterTitle = el.querySelector('.chapternum')?.text.trim() ?? '';
      final chapterHref =
          el.querySelector('a')?.attributes['href']?.trim() ?? '';
      final chapterDate = el.querySelector('.chapterdate')?.text.trim() ?? '';

      if (chapterTitle.isNotEmpty && chapterHref.isNotEmpty) {
        chapters.add(
          Chapter(
            title: chapterTitle,
            href: _trimPrefix(chapterHref, _baseUrl),
            date: chapterDate,
          ),
        );
      }
    }

    return ComicDetail(
      href: href,
      title: title,
      altTitle: altTitle,
      thumbnail: thumbnail,
      description: description,
      status: status,
      type: type,
      released: released,
      author: author,
      updatedOn: updatedOn,
      rating: rating,
      latestChapter: latestChapter,
      genres: genres,
      chapters: chapters,
    );
  }

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    final url = '$_baseUrl/$href';
    final response = await _client.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final body = response.body;

    // Extract title
    final title = doc.querySelector('h1.entry-title')?.text.trim() ?? '';

    // Extract panels from multiple sources
    final panels = <String>[];
    final found = <String>{};

    void addPanel(String url) {
      var cleanUrl = url.trim();
      if (cleanUrl.isEmpty) return;

      // Normalize protocol-relative URLs
      if (cleanUrl.startsWith('//')) {
        cleanUrl = 'https:$cleanUrl';
      }

      // Ensure absolute URL
      if (!cleanUrl.startsWith('http') && cleanUrl.startsWith('/')) {
        cleanUrl = '$_baseUrl$cleanUrl';
      }

      if (cleanUrl.isEmpty) return;

      // Skip ads but keep manga images
      if ((cleanUrl.toLowerCase().contains('haka4d') ||
              cleanUrl.toLowerCase().contains('banner') ||
              cleanUrl.toLowerCase().contains('gif')) &&
          !cleanUrl.contains('uploads/manga-images')) {
        return;
      }

      if (!found.contains(cleanUrl)) {
        found.add(cleanUrl);
        panels.add(cleanUrl);
      }
    }

    // 1. Try #readerarea.rdminimal
    final readerArea = doc.querySelector('#readerarea.rdminimal');
    if (readerArea != null) {
      final imgRegex = RegExp(r'''<img\s+src=['"]([^'"]+)['"]''');
      final matches = imgRegex.allMatches(readerArea.outerHtml);

      for (final match in matches) {
        if (match.groupCount > 0) {
          final imgUrl = match.group(1) ?? '';
          if (imgUrl.contains('uploads/manga-images') ||
              imgUrl.contains('/chapter-')) {
            addPanel(imgUrl);
          }
        }
      }
    }

    // 2. Standard selectors
    if (panels.isEmpty) {
      final images = doc.querySelectorAll('#readerarea img, .rdminimal img');
      for (final img in images) {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty &&
            (src.contains('uploads/manga-images') ||
                src.contains('/chapter-') ||
                !src.contains('gif'))) {
          addPanel(src);
        }
      }
    }

    // 3. Parse from JavaScript
    if (panels.isEmpty && body.contains('ts_reader.run')) {
      final sourceRegex = RegExp(
        r'"sources":\s*\[\{[^}]*"images":\s*\[(.*?)\]',
      );
      final sourceMatch = sourceRegex.firstMatch(body);

      if (sourceMatch != null && sourceMatch.groupCount > 0) {
        final imgUrlRegex = RegExp(r'"([^"]*uploads/manga-images[^"]*)"');
        final imgMatches = imgUrlRegex.allMatches(sourceMatch.group(1) ?? '');

        for (final match in imgMatches) {
          if (match.groupCount > 0) {
            final imgUrl = (match.group(1) ?? '').replaceAll(r'\/', '/');
            addPanel(imgUrl);
          }
        }
      }
    }

    // Extract navigation from JavaScript
    var prev = '';
    var next = '';

    final prevRegex = RegExp(r'"prevUrl":"([^"]+)"');
    final nextRegex = RegExp(r'"nextUrl":"([^"]+)"');

    final prevMatch = prevRegex.firstMatch(body);
    if (prevMatch != null && prevMatch.groupCount > 0) {
      prev = _trimPrefix(
        (prevMatch.group(1) ?? '').replaceAll(r'\/', '/'),
        _baseUrl,
      );
    }

    final nextMatch = nextRegex.firstMatch(body);
    if (nextMatch != null && nextMatch.groupCount > 0) {
      next = _trimPrefix(
        (nextMatch.group(1) ?? '').replaceAll(r'\/', '/'),
        _baseUrl,
      );
    }

    // Fallback navigation from HTML
    if (prev.isEmpty) {
      final prevHref =
          doc
              .querySelector('.nextprev a.ch-prev-btn, .chnav .ch-prev-btn')
              ?.attributes['href'] ??
          '';
      if (prevHref.isNotEmpty && !prevHref.contains('#')) {
        prev = _trimPrefix(prevHref, _baseUrl);
      }
    }

    if (next.isEmpty) {
      final nextHref =
          doc
              .querySelector('.nextprev a.ch-next-btn, .chnav .ch-next-btn')
              ?.attributes['href'] ??
          '';
      if (nextHref.isNotEmpty && !nextHref.contains('#')) {
        next = _trimPrefix(nextHref, _baseUrl);
      }
    }

    return ReadChapter(title: title, prev: prev, next: next, panel: panels);
  }

  /// Clear all caches
  void clearCache() {
    _listCache.clear();
  }

  /// Clear only list cache
  void clearListCache() {
    _listCache.clear();
  }

  /// Dispose HTTP client
  void dispose() {
    _client.close();
    clearCache();
  }
}
