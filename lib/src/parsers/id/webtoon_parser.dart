import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

class WebtoonParser extends ComicParser {
  static const String _mobileApiDomain = 'm.webtoons.com';
  static const String _staticDomain = 'webtoon-phinf.pstatic.net';
  static const String _languageCode = 'id';

  final http.Client _client;

  // Cache viewer links for chapters
  final Map<String, String> _viewerLinkCache = {};

  // NEW: Cache untuk list results dengan expiry time
  final Map<String, CachedResult> _listCache = {};

  // NEW: Limit hasil default untuk performa lebih baik
  static const int _defaultPageSize = 10;
  static const int _maxConcurrentRequests = 3;

  WebtoonParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'Webtoons';

  @override
  String get baseUrl => 'https://www.webtoons.com';

  @override
  String get language => 'ID';

  /// Common headers for all requests
  Map<String, String> get _headers => {
    'User-Agent': 'nApps (Android 12;; linewebtoon; 3.1.0)',
    'Referer': baseUrl,
  };

  /// Headers for image requests
  Map<String, String> get imageHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
    'Referer': '$baseUrl/',
  };

  /// Available genres for Webtoons
  static final List<Genre> _availableGenres = [
    Genre(title: 'Action', href: '/action'),
    Genre(title: 'Comedy', href: '/comedy'),
    Genre(title: 'Drama', href: '/drama'),
    Genre(title: 'Fantasy', href: '/fantasy'),
    Genre(title: 'Horror', href: '/horror'),
    Genre(title: 'Romance', href: '/romance'),
    Genre(title: 'Sci-Fi', href: '/sf'),
    Genre(title: 'Slice of Life', href: '/slice_of_life'),
    Genre(title: 'Sports', href: '/sports'),
    Genre(title: 'Supernatural', href: '/supernatural'),
    Genre(title: 'Thriller', href: '/thriller'),
    Genre(title: 'Historical', href: '/historical'),
    Genre(title: 'Mystery', href: '/mystery'),
    Genre(title: 'Superhero', href: '/super_hero'),
    Genre(title: 'Heartwarming', href: '/heartwarming'),
    Genre(title: 'Graphic Novel', href: '/graphic_novel'),
    Genre(title: 'Informative', href: '/tiptoon'),
  ];

  /// Extract title_no from URL
  int _extractTitleNo(String url) {
    final regex = RegExp(r'title_no=(\d+)');
    final match = regex.firstMatch(url);
    if (match != null) {
      return int.parse(match.group(1)!);
    }
    // If url is just the number
    final cleanUrl = url.replaceAll('/', '');
    return int.parse(cleanUrl);
  }

  /// Convert absolute URL for static resources
  String _toAbsoluteUrl(String url, String domain) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    return 'https://$domain$url';
  }

  /// NEW: Check if cache is valid
  bool _isCacheValid(String key) {
    final cached = _listCache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < cacheExpiry;
  }

  /// NEW: Get from cache
  List<ComicItem>? _getFromCache(String key) {
    if (_isCacheValid(key)) {
      return _listCache[key]?.items;
    }
    _listCache.remove(key);
    return null;
  }

  /// NEW: Save to cache
  void _saveToCache(String key, List<ComicItem> items) {
    _listCache[key] = CachedResult(items: items, timestamp: DateTime.now());
  }

  /// Create ComicItem from HTML element (OPTIMIZED)
  ComicItem _createMangaFromElement(Element element, {Genre? selectedGenre}) {
    final href = element.attributes['href'] ?? '';
    final titleNo = _extractTitleNo(href);

    final title =
        element.querySelector('.title, .card_title')?.text.trim() ?? '';

    final thumbnailUrl = element.querySelector('img')?.attributes['src'] ?? '';

    return ComicItem(
      title: title,
      href: '/$titleNo/',
      thumbnail: _toAbsoluteUrl(thumbnailUrl, _staticDomain),
      type: selectedGenre?.title,
    );
  }

  /// Get sort order parameter
  String _getSortOrderParam(String order) {
    switch (order) {
      case 'popular':
        return 'MANA';
      case 'rating':
        return 'LIKEIT';
      case 'latest':
        return 'UPDATE';
      default:
        return 'MANA';
    }
  }

  /// OPTIMIZED: Fetch list with caching and limit
  Future<List<ComicItem>> _fetchList(
    String rankingType, {
    int page = 1,
    int limit = _defaultPageSize,
  }) async {
    final cacheKey = '$rankingType-$page-$limit';
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/$_languageCode/ranking/$rankingType';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load data: ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    final elements = document.querySelectorAll(
      '.webtoon_list li a, .card_wrap .card_item a',
    );

    if (elements.isEmpty) {
      return [];
    }

    // Optimized pagination with limit
    final offset = (page - 1) * limit;
    final results = elements
        .map((e) => _createMangaFromElement(e))
        .skip(offset)
        .take(limit)
        .toList();

    _saveToCache(cacheKey, results);

    return results;
  }

  /// NEW: Batch fetch multiple lists efficiently
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
        _fetchList('popular', limit: limit).then((items) {
          results['popular'] = items;
        }),
      );
    }

    if (recommended) {
      futures.add(
        _fetchList('trending', limit: limit).then((items) {
          results['recommended'] = items;
        }),
      );
    }

    if (newest) {
      futures.add(
        _fetchList('originals', limit: limit).then((items) {
          results['newest'] = items;
        }),
      );
    }

    // Wait for all requests to complete
    await Future.wait(futures);

    return results;
  }

  /// NEW: Fetch multiple genres in batch
  Future<Map<String, List<ComicItem>>> fetchMultipleGenres(
    List<String> genres, {
    int limit = 6,
  }) async {
    final Map<String, List<ComicItem>> results = {};

    for (var i = 0; i < genres.length; i += _maxConcurrentRequests) {
      final batch = genres.skip(i).take(_maxConcurrentRequests);
      final futures = batch.map((genre) async {
        try {
          final items = await fetchByGenre(genre, page: 1, limit: limit);
          results[genre] = items;
        } catch (e) {
          results[genre] = [];
        }
      });

      await Future.wait(futures);
    }

    return results;
  }

  @override
  Future<List<ComicItem>> fetchPopular({int limit = _defaultPageSize}) async {
    return _fetchList('popular', limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchRecommended({
    int limit = _defaultPageSize,
  }) async {
    return _fetchList('trending', limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchNewest({
    int page = 1,
    int limit = _defaultPageSize,
  }) async {
    return _fetchList('originals', page: page, limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchAll({
    int page = 1,
    int limit = _defaultPageSize,
  }) async {
    return _fetchList('popular', page: page, limit: limit);
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final cacheKey = 'search-$encodedQuery';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/$_languageCode/search?keyword=$encodedQuery';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to search: ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    final elements = document.querySelectorAll(
      '.webtoon_list li a, .card_wrap .card_item a',
    );

    if (elements.isEmpty) {
      throw Exception('No results found');
    }

    final results = elements.map((e) => _createMangaFromElement(e)).toList();

    _saveToCache(cacheKey, results);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(
    String genre, {
    int page = 1,
    int limit = _defaultPageSize,
  }) async {
    final cacheKey = 'genre-$genre-$page-$limit';
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    // Find genre URL path
    final genreObj = _availableGenres.firstWhere(
      (g) => g.title.toLowerCase() == genre.toLowerCase(),
      orElse: () => Genre(title: genre, href: '/$genre'),
    );

    final genreUrlPath = genreObj.href.replaceAll('/', '');
    final sortParam = _getSortOrderParam('popular');
    final url =
        '$baseUrl/$_languageCode/genres/$genreUrlPath?sortOrder=$sortParam';

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load genre: ${response.statusCode}');
    }

    final document = html_parser.parse(response.body);
    final elements = document.querySelectorAll(
      '.webtoon_list li a, .card_wrap .card_item a',
    );

    if (elements.isEmpty) {
      throw Exception('Page not found');
    }

    // Client-side pagination with limit
    final offset = (page - 1) * limit;
    final results = elements
        .map((e) => _createMangaFromElement(e, selectedGenre: genreObj))
        .skip(offset)
        .take(limit)
        .toList();

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
    int limit = _defaultPageSize,
  }) async {
    // Webtoons doesn't support complex filtering, use genre if provided
    if (genre != null && genre.isNotEmpty) {
      return fetchByGenre(genre, page: page, limit: limit);
    }

    // Use order if provided
    final rankingType = order == 'rating'
        ? 'trending'
        : order == 'latest'
        ? 'originals'
        : 'popular';
    return _fetchList(rankingType, page: page, limit: limit);
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    return _availableGenres;
  }

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    final titleNo = _extractTitleNo(href);
    final detailsUrl =
        '$baseUrl/$_languageCode/drama/placeholder/list?title_no=$titleNo';

    final response = await _client.get(
      Uri.parse(detailsUrl),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load detail: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    String title =
        doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        '';
    if (title.isEmpty) {
      title = doc.querySelector('h1.subj, h3.subj')?.text.trim() ?? '';
    }

    String description =
        doc
            .querySelector('meta[property="og:description"]')
            ?.attributes['content'] ??
        '';
    if (description.isEmpty) {
      description =
          doc.querySelector('#_asideDetail p.summary')?.text.trim() ?? '';
    }
    if (description.isEmpty) {
      description =
          doc.querySelector('.detail_header .summary')?.text.trim() ?? '';
    }

    String coverUrl =
        doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
        '';
    if (coverUrl.isNotEmpty) {
      coverUrl = _toAbsoluteUrl(coverUrl, _staticDomain);
    }

    String author =
        doc
            .querySelector('meta[property="com-linewebtoon:webtoon:author"]')
            ?.attributes['content'] ??
        '';
    if (author.isEmpty || author == 'null') {
      author =
          doc.querySelector('.detail_header .info .author')?.text.trim() ?? '';
    }
    if (author.isEmpty || author == 'null') {
      author = doc.querySelector('.author_area')?.text.trim() ?? '';
    }

    final genreElements = doc.querySelectorAll('.detail_header .info .genre');
    final genreElementsAlt = genreElements.isEmpty
        ? doc.querySelectorAll('h2.genre')
        : genreElements;
    final genres = genreElementsAlt.map((e) {
      final genreTitle = e.text.trim();
      return Genre(
        title: genreTitle,
        href: '/${genreTitle.toLowerCase().replaceAll(' ', '_')}/',
      );
    }).toList();

    String status = 'Unknown';
    final dayInfo =
        doc.querySelector('#_asideDetail p.day_info')?.text.trim() ??
        doc.querySelector('.day_info')?.text.trim() ??
        '';
    if (dayInfo.contains('UP') ||
        dayInfo.contains('EVERY') ||
        dayInfo.contains('NOUVEAU')) {
      status = 'Ongoing';
    } else if (dayInfo.contains('END') ||
        dayInfo.contains('COMPLETED') ||
        dayInfo.contains('TERMINÉ')) {
      status = 'Completed';
    }

    // Fetch episodes/chapters
    final chapters = await _fetchEpisodes(titleNo, title);
    final reversedChapters = chapters.reversed.toList();

    return ComicDetail(
      href: href,
      title: title,
      altTitle: '',
      thumbnail: coverUrl,
      description: description,
      status: status,
      type: 'Webtoon',
      released: '',
      author: author,
      updatedOn: '',
      rating: '0.0',
      latestChapter: reversedChapters.isNotEmpty
          ? reversedChapters.first.title
          : null,
      genres: genres,
      chapters: reversedChapters,
    );
  }

  /// Fetch episodes from mobile API
  Future<List<Chapter>> _fetchEpisodes(int titleNo, String mangaTitle) async {
    final url =
        'https://$_mobileApiDomain/api/v1/webtoon/$titleNo/episodes?pageSize=99999';

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load episodes: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = json['result'] as Map<String, dynamic>?;

    if (result == null) {
      throw Exception('No episodes found for title $titleNo');
    }

    final episodeList = result['episodeList'] as List?;
    if (episodeList == null || episodeList.isEmpty) {
      return [];
    }

    final chapters = <Chapter>[];
    for (final ep in episodeList) {
      final episode = ep as Map<String, dynamic>;
      final episodeTitle = episode['episodeTitle'] as String? ?? '';
      final episodeNo = episode['episodeNo'] as int;
      final exposureDate = episode['exposureDateMillis'] as int?;
      final viewerLink = episode['viewerLink'] as String? ?? '';

      // Store viewer link in cache
      final chapterHref = '/$titleNo/$episodeNo/';
      if (viewerLink.isNotEmpty) {
        _viewerLinkCache[chapterHref] = viewerLink;
      }

      // Format date
      String date = '';
      if (exposureDate != null) {
        final dateTime = DateTime.fromMillisecondsSinceEpoch(exposureDate);
        date =
            '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
      }

      final chapterTitle = episodeTitle.isNotEmpty
          ? '$mangaTitle - $episodeTitle'
          : '$mangaTitle - Episode $episodeNo';

      chapters.add(Chapter(title: chapterTitle, href: chapterHref, date: date));
    }

    return chapters;
  }

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    final parts = href.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length < 2) {
      throw Exception('Invalid chapter href format');
    }

    final titleNo = int.parse(parts[0]);
    final episodeNo = int.parse(parts[1]);

    String viewerUrl = _viewerLinkCache[href] ?? '';

    if (viewerUrl.isEmpty) {
      // If not in cache, fetch episodes to populate cache (title not needed here)
      await _fetchEpisodes(titleNo, '');
      viewerUrl = _viewerLinkCache[href] ?? '';
    }

    // If still empty, construct a basic URL (fallback)
    if (viewerUrl.isEmpty) {
      viewerUrl =
          '$baseUrl/$_languageCode/viewer?title_no=$titleNo&episode_no=$episodeNo';
    } else {
      // Make sure viewer link is absolute URL
      viewerUrl = _toAbsoluteUrl(viewerUrl, domain);
    }

    final response = await _client.get(Uri.parse(viewerUrl), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final title =
        doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
        'Episode $episodeNo';

    List<String> panels = [];

    // Try multiple selectors in priority order
    final selectors = [
      'div#_imageList > img',
      'canvas[data-url]',
      'img[src*="$_staticDomain"], img[data-url*="$_staticDomain"]',
    ];

    for (final selector in selectors) {
      final imageElements = doc.querySelectorAll(selector);
      if (imageElements.isNotEmpty) {
        panels = imageElements
            .map((e) {
              final url = e.attributes['data-url'] ?? e.attributes['src'] ?? '';
              return url;
            })
            .where((url) => url.isNotEmpty)
            .toList();

        if (panels.isNotEmpty) break;
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    // Determine prev/next chapters
    String prev = '';
    String next = '';

    // Try to get navigation from page
    final prevLink = doc.querySelector('a.pg_prev:not(.off)');
    if (prevLink != null) {
      final prevHref = prevLink.attributes['href'] ?? '';
      if (prevHref.isNotEmpty) {
        final prevMatch = RegExp(r'episode_no=(\d+)').firstMatch(prevHref);
        if (prevMatch != null) {
          prev = '/$titleNo/${prevMatch.group(1)}/';
        }
      }
    }

    final nextLink = doc.querySelector('a.pg_next:not(.off)');
    if (nextLink != null) {
      final nextHref = nextLink.attributes['href'] ?? '';
      if (nextHref.isNotEmpty) {
        final nextMatch = RegExp(r'episode_no=(\d+)').firstMatch(nextHref);
        if (nextMatch != null) {
          next = '/$titleNo/${nextMatch.group(1)}/';
        }
      }
    }

    if (prev.isEmpty && episodeNo > 1) {
      prev = '/$titleNo/${episodeNo - 1}/';
    }
    if (next.isEmpty) {
      next = '/$titleNo/${episodeNo + 1}/';
    }

    return ReadChapter(title: title, prev: prev, next: next, panel: panels);
  }

  /// NEW: Clear all caches
  void clearCache() {
    _listCache.clear();
    _viewerLinkCache.clear();
  }

  /// NEW: Clear only list cache
  void clearListCache() {
    _listCache.clear();
  }

  /// Dispose HTTP client
  void dispose() {
    _client.close();
    clearCache();
  }

  // Getter for domain (used in _toAbsoluteUrl)
  String get domain =>
      baseUrl.replaceAll('https://', '').replaceAll('http://', '');
}
