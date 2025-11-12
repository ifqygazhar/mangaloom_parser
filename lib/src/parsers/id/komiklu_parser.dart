import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

class KomikluParser extends ComicParser {
  static const String _baseUrl = 'https://v2.komiklu.com';

  final http.Client _client;

  // Cache untuk list results dengan expiry time
  final Map<String, CachedResult> _listCache = {};

  // Limit concurrent requests untuk batch operations
  static const int _maxConcurrentRequests = 3;

  KomikluParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'Komiklu';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'ID';

  /// Common headers for requests
  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': baseUrl,
  };

  /// Available genres for Komiklu (hardcoded based on the site)
  static final List<Genre> _availableGenres = [
    Genre(title: 'Action', href: '/action/'),
    Genre(title: 'Adult', href: '/adult/'),
    Genre(title: 'Adventure', href: '/adventure/'),
    Genre(title: 'Comedy', href: '/comedy/'),
    Genre(title: 'Drama', href: '/drama/'),
    Genre(title: 'Ecchi', href: '/ecchi/'),
    Genre(title: 'Fantasy', href: '/fantasy/'),
    Genre(title: 'Harem', href: '/harem/'),
    Genre(title: 'Historical', href: '/historical/'),
    Genre(title: 'Horror', href: '/horror/'),
    Genre(title: 'Josei', href: '/josei/'),
    Genre(title: 'Martial Arts', href: '/martial-arts/'),
    Genre(title: 'Mature', href: '/mature/'),
    Genre(title: 'Mystery', href: '/mystery/'),
    Genre(title: 'Psychological', href: '/psychological/'),
    Genre(title: 'Romance', href: '/romance/'),
    Genre(title: 'School Life', href: '/school-life/'),
    Genre(title: 'Sci-fi', href: '/sci-fi/'),
    Genre(title: 'Seinen', href: '/seinen/'),
    Genre(title: 'Shounen', href: '/shounen/'),
    Genre(title: 'Slice of Life', href: '/slice-of-life/'),
    Genre(title: 'Sports', href: '/sports/'),
    Genre(title: 'Supernatural', href: '/supernatural/'),
    Genre(title: 'Tragedy', href: '/tragedy/'),
  ];

  /// Check if cache is valid
  bool _isCacheValid(String key) {
    final cached = _listCache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < cacheExpiry;
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

  /// Helper to make absolute URL
  String _toAbsoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('/')) {
      return '$baseUrl$url';
    }
    return '$baseUrl/$url';
  }

  /// Helper to extract relative URL and clean it
  String _toRelativeUrl(String url) {
    if (url.startsWith(baseUrl)) {
      url = url.substring(baseUrl.length);
    } else if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      url = uri.path;
      if (uri.query.isNotEmpty) {
        url = '$url?${uri.query}';
      }
    }

    // Ensure leading slash
    if (!url.startsWith('/')) {
      url = '/$url';
    }

    return url;
  }

  /// Parse comic list from article elements (used in ajax responses)
  List<ComicItem> _parseComicListFromArticles(Document doc) {
    final items = <ComicItem>[];
    final articles = doc.querySelectorAll('article');

    for (final article in articles) {
      try {
        final title = article.querySelector('h4 a')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        var href = article.querySelector('h4 a')?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        href = _toRelativeUrl(href);

        var thumbnail = article.querySelector('a img')?.attributes['src'] ?? '';
        if (thumbnail.isNotEmpty) {
          thumbnail = _toAbsoluteUrl(thumbnail);
        }

        final chapter =
            article.querySelector('div.text-sky-400')?.text.trim() ?? '';

        var rating =
            article.querySelector('div.text-yellow-400')?.text.trim() ?? '';
        rating = rating.replaceAll('⭐', '').trim();

        items.add(
          ComicItem(
            title: title,
            href: href,
            thumbnail: thumbnail,
            rating: rating,
            chapter: chapter,
            type: 'Manga',
          ),
        );
      } catch (e) {
        continue;
      }
    }

    return items;
  }

  /// Parse comic list from page.php (different structure)
  List<ComicItem> _parseComicListFromPage(Document doc) {
    final items = <ComicItem>[];

    // Check for no results
    if (doc.querySelector('#comicContainer center.noresult') != null) {
      return items;
    }

    final articles = doc.querySelectorAll('article');

    for (final article in articles) {
      try {
        final title = article.querySelector('h4 a')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        var href = article.querySelector('h4 a')?.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        href = _toRelativeUrl(href);

        var thumbnail = article.querySelector('a img')?.attributes['src'] ?? '';
        if (thumbnail.isNotEmpty) {
          thumbnail = _toAbsoluteUrl(thumbnail);
        }

        String chapter = '';
        final chapterDivs = article.querySelectorAll(
          'div.flex.justify-between div.text-sky-400',
        );
        for (final div in chapterDivs) {
          final text = div.text.trim();
          if (text.toLowerCase().contains('chapter')) {
            chapter = text;
            break;
          }
        }

        var rating =
            article.querySelector('div.text-yellow-400')?.text.trim() ?? '';
        rating = rating.replaceAll('⭐', '').trim();

        items.add(
          ComicItem(
            title: title,
            href: href,
            thumbnail: thumbnail,
            rating: rating,
            type: 'Manga',
            chapter: chapter,
          ),
        );
      } catch (e) {
        continue;
      }
    }

    return items;
  }

  @override
  Future<List<ComicItem>> fetchPopular() async {
    const cacheKey = 'popular-1';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/ajax_filter.php?yearTo=9999&sort=rating-desc';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load popular: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicListFromArticles(doc);

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchRecommended() async {
    const cacheKey = 'recommended-1';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/ajax_filter.php?yearTo=9999&sort=newest';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load recommended: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicListFromArticles(doc);

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final cacheKey = 'newest-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    // Ajax filter doesn't support pagination, always page 1
    final url = '$baseUrl/ajax_filter.php?yearTo=9999&sort=year-desc';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load newest: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicListFromArticles(doc);

    if (results.isEmpty) {
      throw Exception('No results found');
    }

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    final cacheKey = 'all-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/page.php?page=$page';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load all: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicListFromPage(doc);

    if (results.isEmpty) {
      throw Exception('Page not found');
    }

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final cacheKey = 'search-$encodedQuery';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/search.php?q=$encodedQuery';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to search: ${response.statusCode}');
    }

    try {
      final List<dynamic> jsonResults = jsonDecode(response.body);
      final items = <ComicItem>[];

      for (final result in jsonResults) {
        final title = result['title']?.toString() ?? '';
        if (title.isEmpty) continue;

        var href = '/comic_detail.php?title=$title';

        // Cover/thumbnail
        var thumbnail = result['cover']?.toString() ?? '';
        if (thumbnail.isNotEmpty) {
          thumbnail = _toAbsoluteUrl(thumbnail);
        }

        var rating = result['rating']?.toString() ?? '';
        if (rating.isNotEmpty && !rating.contains('/')) {
          rating = '$rating/10';
        }

        final year = result['year']?.toString() ?? '';

        items.add(
          ComicItem(
            title: title,
            href: href,
            thumbnail: thumbnail,
            rating: rating,
            chapter: year,
            type: 'Manga',
          ),
        );
      }

      if (items.isEmpty) {
        throw Exception('No results found');
      }

      _saveToCache(cacheKey, items);

      return items;
    } catch (e) {
      throw Exception('Failed to parse search results: $e');
    }
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final cacheKey = 'genre-$genre-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    // Ajax filter doesn't support pagination, always page 1
    final url =
        '$baseUrl/ajax_filter.php?filterGenre=$genre&yearTo=9999&sort=newest';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load genre: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicListFromArticles(doc);

    if (results.isEmpty) {
      throw Exception('No results found');
    }

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    final cacheKey = 'filtered-$page-$genre-$status-$type-$order';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    // Build URL based on filter type
    String url;
    if (genre != null && genre.isNotEmpty) {
      url =
          '$baseUrl/ajax_filter.php?filterGenre=$genre&yearTo=9999&sort=newest';
    } else if (order == 'rating-desc' || order == 'popular') {
      // Popular filter
      url = '$baseUrl/ajax_filter.php?yearTo=9999&sort=rating-desc';
    } else {
      url = '$baseUrl/ajax_filter.php?yearTo=9999&sort=newest';
    }

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load filtered: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicListFromArticles(doc);

    if (results.isEmpty) {
      throw Exception('No results found');
    }

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    // Return hardcoded genres
    return _availableGenres;
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

    final url = _toAbsoluteUrl(href);
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load detail: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    var title = doc.querySelector('h1.text-3xl.font-bold')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = doc.querySelector('h1')?.text.trim() ?? '';
    }

    if (title.isEmpty) {
      throw Exception('Comic not found');
    }

    var thumbnail =
        doc
            .querySelector('img.w-56.h-80.object-cover.rounded-lg.shadow-lg')
            ?.attributes['src'] ??
        '';
    if (thumbnail.isEmpty) {
      thumbnail =
          doc.querySelector('main section img')?.attributes['src'] ?? '';
    }
    if (thumbnail.isNotEmpty) {
      thumbnail = _toAbsoluteUrl(thumbnail);
    }

    final author =
        doc.querySelector('span.text-sky-400.font-medium')?.text.trim() ?? '';

    var rating =
        doc.querySelector('span.ml-2.text-sm.text-gray-400')?.text.trim() ?? '';
    rating = rating.replaceAll('(', '').replaceAll(')', '').trim();

    final description =
        doc.querySelector('p.text-gray-300.leading-relaxed')?.text.trim() ?? '';

    String year = '';
    String status = '';

    final infoSpans = doc.querySelectorAll(
      'div.flex.items-center.gap-4.text-gray-400 > span.flex.items-center.gap-1',
    );
    for (final span in infoSpans) {
      // Check for year (span.text-gray-200 containing 4 digits)
      final yearText =
          span.querySelector('span.text-gray-200')?.text.trim() ?? '';
      if (yearText.length == 4 && int.tryParse(yearText) != null) {
        year = yearText;
      }

      // Check for status (span.text-sky-400.font-semibold)
      final statusText =
          span.querySelector('span.text-sky-400.font-semibold')?.text.trim() ??
          '';
      if (statusText == 'OnGoing' || statusText == 'Completed') {
        status = statusText;
      }
    }

    final genres = <Genre>[];
    final genreElements = doc.querySelectorAll(
      'div.flex.flex-wrap.gap-2 span.bg-gray-800.text-gray-200.text-sm',
    );
    for (final el in genreElements) {
      final genreTitle = el.text.trim();
      if (genreTitle.isNotEmpty && genreTitle.length < 30) {
        final slug = genreTitle.toLowerCase().replaceAll(' ', '-');
        genres.add(Genre(title: genreTitle, href: '/$slug/'));
      }
    }

    final chapters = <Chapter>[];
    final chapterElements = doc.querySelectorAll(
      'ul#chapterContainer li.chapter-item',
    );
    for (final li in chapterElements) {
      final chapterTitle =
          li.querySelector('span.chapter-name')?.text.trim() ?? '';
      var chapterHref = li.querySelector('a')?.attributes['href'] ?? '';

      if (chapterTitle.isNotEmpty && chapterHref.isNotEmpty) {
        chapterHref = _toRelativeUrl(chapterHref);

        chapters.add(Chapter(title: chapterTitle, href: chapterHref, date: ''));
      }
    }

    return ComicDetail(
      href: _toRelativeUrl(href),
      title: title,
      altTitle: '',
      thumbnail: thumbnail,
      description: description,
      status: status,
      type: 'Manga',
      released: year,
      author: author,
      updatedOn: '',
      rating: rating,
      latestChapter: chapters.isNotEmpty ? chapters.first.title : null,
      genres: genres,
      chapters: chapters,
    );
  }

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    final url = _toAbsoluteUrl(href);
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final title = doc.querySelector('h1.text-2xl.font-bold')?.text.trim() ?? '';

    if (title.isEmpty) {
      throw Exception('Chapter not found');
    }

    // Extract prev chapter from "Previous Chapter" button
    // CSS :contains() is not supported, so we search through all <a> elements
    String prev = '';
    final allLinks = doc.querySelectorAll('a[href]');
    for (final link in allLinks) {
      final text = link.text.trim();
      if (text.contains('Previous Chapter') || text.contains('Previous')) {
        final prevHref = link.attributes['href'] ?? '';
        if (prevHref.isNotEmpty && prevHref != '#') {
          prev = _toRelativeUrl(prevHref);
          if (prev.isEmpty || prev == '/') {
            prev = '';
          }
          break;
        }
      }
    }

    // Extract next chapter from "Next Chapter" button
    String next = '';
    for (final link in allLinks) {
      final text = link.text.trim();
      if (text.contains('Next Chapter') || text.contains('Next')) {
        final nextHref = link.attributes['href'] ?? '';
        if (nextHref.isNotEmpty && nextHref != '#') {
          next = _toRelativeUrl(nextHref);
          if (next.isEmpty || next == '/') {
            next = '';
          }
          break;
        }
      }
    }

    final images = <String>[];
    final imageElements = doc.querySelectorAll('div#viewer img.webtoon-img');
    for (final img in imageElements) {
      // Try data-src first (for lazy loading), then fallback to src
      var src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        images.add(src);
      }
    }

    if (images.isEmpty) {
      throw Exception('No images found in chapter');
    }

    return ReadChapter(title: title, prev: prev, next: next, panel: images);
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
