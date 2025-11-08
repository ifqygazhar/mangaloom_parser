import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/src/utils/cache.dart';
import 'package:uuid/uuid.dart'; // tambahkan di pubspec.yaml: uuid: ^4.0.0
import 'package:mangaloom_parser/mangaloom_parser.dart';

class MangaPlusParser extends ComicParser {
  static const String _apiUrl = 'https://jumpg-webapi.tokyo-cdn.com/api';
  static const String _baseUrl = 'https://mangaplus.shueisha.co.jp';
  static const String _sourceLang = 'INDONESIAN';

  // User-Agent yang sama persis dengan Kotlin
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final http.Client _client;
  final String _sessionToken;

  // Cache untuk results dengan expiry time
  final Map<String, _CachedResult> _apiCache = {};

  // Limit hasil default
  static const int _defaultLimit = 10;

  // Cache untuk all titles
  Map<String, dynamic>? _allTitlesCache;
  DateTime? _allTitlesCacheTime;

  MangaPlusParser({http.Client? client})
    : _client = client ?? http.Client(),
      _sessionToken = const Uuid().v4(); // Generate UUID v4 proper

  @override
  String get sourceName => 'MangaPlus';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'ID';

  /// Headers untuk semua request - EXACTLY sama dengan Kotlin
  Map<String, String> _getHeaders() => {
    'Session-Token': _sessionToken,
    'User-Agent': _userAgent,
  };

  /// Headers for image requests
  Map<String, String> get imageHeaders => {'User-Agent': _userAgent};

  /// Check if cache is valid
  bool _isCacheValid(String key) {
    final cached = _apiCache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < cacheExpiry;
  }

  /// Get from cache
  dynamic _getFromCache(String key) {
    if (_isCacheValid(key)) {
      return _apiCache[key]?.data;
    }
    _apiCache.remove(key);
    return null;
  }

  /// Save to cache
  void _saveToCache(String key, dynamic data) {
    _apiCache[key] = _CachedResult(data: data, timestamp: DateTime.now());
  }

  /// Helper untuk melakukan API call dengan caching
  Future<Map<String, dynamic>> _apiCall(
    String endpoint, {
    bool useCache = true,
  }) async {
    if (useCache) {
      final cached = _getFromCache(endpoint);
      if (cached != null && cached is Map<String, dynamic>) {
        return cached;
      }
    }

    // Build URL - pastikan format query parameter benar
    final urlString = '$_apiUrl$endpoint';
    final uri = Uri.parse(urlString);

    // Tambahkan format=json ke query parameters yang sudah ada
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['format'] = 'json';

    final finalUri = uri.replace(queryParameters: queryParams);

    try {
      final response = await _client.get(finalUri, headers: _getHeaders());

      if (response.statusCode != 200) {
        throw Exception('Failed to load data: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // Check for success
      if (json.containsKey('success')) {
        final result = json['success'] as Map<String, dynamic>;

        if (useCache) {
          _saveToCache(endpoint, result);
        }

        return result;
      }

      if (json.containsKey('error')) {
        final error = json['error'] as Map<String, dynamic>;

        // Try to get error popups
        if (error.containsKey('popups')) {
          final popups = error['popups'] as List<dynamic>;

          // Find first popup without language (general error)
          for (final popup in popups) {
            if (popup is! Map<String, dynamic>) continue;

            // Check if it's a general error (no language field or null language)
            final language = popup['language'];
            if (language == null) {
              final subject = popup['subject'] as String?;
              final body = popup['body'] as String?;

              // Special handling for manga_viewer Not Found
              if (subject == 'Not Found' && endpoint.contains('manga_viewer')) {
                throw Exception('This chapter has expired');
              }

              // Return the error body message if available
              if (body != null && body.isNotEmpty) {
                throw Exception(body);
              }

              // Return subject if body not available
              if (subject != null && subject.isNotEmpty) {
                throw Exception(subject);
              }
            }
          }
        }

        // If no specific error message found, try to get action field
        final errorAction = error['action'] as String?;
        if (errorAction != null && errorAction.isNotEmpty) {
          throw Exception(errorAction);
        }

        // Generic error
        throw Exception('Unknown Error');
      }

      throw Exception('Invalid API response');
    } catch (e) {
      rethrow;
    }
  }

  /// Helper untuk filter manga berdasarkan bahasa
  List<ComicItem> _filterAndMapManga(
    List<dynamic> titles, {
    String? query,
    int? limit,
  }) {
    final items = <ComicItem>[];
    int count = 0;

    for (final item in titles) {
      // Early exit if limit reached
      if (limit != null && count >= limit) break;

      if (item is! Map<String, dynamic>) continue;

      final language = item['language'] as String? ?? 'ENGLISH';
      if (language != _sourceLang) continue;

      final name = item['name'] as String? ?? '';
      final author = (item['author'] as String? ?? '')
          .split('/')
          .map((e) => e.trim())
          .join(', ');

      if (query != null && query.isNotEmpty) {
        if (!name.toLowerCase().contains(query.toLowerCase()) &&
            !author.toLowerCase().contains(query.toLowerCase())) {
          continue;
        }
      }

      final titleId = item['titleId']?.toString() ?? '';
      if (titleId.isEmpty) continue;

      items.add(
        ComicItem(
          title: name,
          href: titleId,
          thumbnail: item['portraitImageUrl'] as String? ?? '',
          type: null,
          chapter: null,
          rating: null,
        ),
      );

      count++;
    }

    return items;
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
        fetchPopular(limit: limit)
            .then((items) {
              results['popular'] = items;
            })
            .catchError((e) {
              results['popular'] = [];
            }),
      );
    }

    if (recommended) {
      futures.add(
        fetchRecommended(limit: limit)
            .then((items) {
              results['recommended'] = items;
            })
            .catchError((e) {
              results['recommended'] = [];
            }),
      );
    }

    if (newest) {
      futures.add(
        fetchNewest(limit: limit)
            .then((items) {
              results['newest'] = items;
            })
            .catchError((e) {
              results['newest'] = [];
            }),
      );
    }

    // Wait for all requests to complete
    await Future.wait(futures);

    return results;
  }

  @override
  Future<List<ComicItem>> fetchPopular({int limit = _defaultLimit}) async {
    final json = await _apiCall('/title_list/ranking');
    final titles = json['titleRankingView']?['titles'] as List<dynamic>? ?? [];
    return _filterAndMapManga(titles, limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchRecommended({int limit = _defaultLimit}) async {
    // MangaPlus doesn't have separate recommended, use popular
    return fetchPopular(limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchNewest({
    int page = 1,
    int limit = _defaultLimit,
  }) async {
    final json = await _apiCall('/title_list/updated');
    final latestTitles =
        json['titleUpdatedView']?['latestTitle'] as List<dynamic>? ?? [];

    final titles = <dynamic>[];
    for (final item in latestTitles) {
      if (item is Map<String, dynamic> && item.containsKey('title')) {
        titles.add(item['title']);
      }
    }

    return _filterAndMapManga(titles, limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchAll({
    int page = 1,
    int limit = _defaultLimit,
  }) async {
    // Load cache if not exists or expired
    if (_allTitlesCache == null ||
        _allTitlesCacheTime == null ||
        DateTime.now().difference(_allTitlesCacheTime!) >= cacheExpiry) {
      _allTitlesCache = await _apiCall('/title_list/allV2');
      _allTitlesCacheTime = DateTime.now();
    }

    final allTitlesGroups =
        _allTitlesCache?['allTitlesViewV2']?['AllTitlesGroup']
            as List<dynamic>? ??
        [];

    final allTitles = <dynamic>[];
    for (final group in allTitlesGroups) {
      if (group is Map<String, dynamic> && group.containsKey('titles')) {
        final titles = group['titles'] as List<dynamic>? ?? [];
        allTitles.addAll(titles);
      }
    }

    // Filter first, then paginate
    final filteredItems = _filterAndMapManga(allTitles);

    // Client-side pagination
    final offset = (page - 1) * limit;
    if (offset >= filteredItems.length) {
      return [];
    }

    return filteredItems.skip(offset).take(limit).toList();
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    if (query.isEmpty) {
      return fetchAll();
    }

    // MangaPlus uses local search - use cached all titles
    if (_allTitlesCache == null ||
        _allTitlesCacheTime == null ||
        DateTime.now().difference(_allTitlesCacheTime!) >= cacheExpiry) {
      _allTitlesCache = await _apiCall('/title_list/allV2');
      _allTitlesCacheTime = DateTime.now();
    }

    final allTitlesGroups =
        _allTitlesCache?['allTitlesViewV2']?['AllTitlesGroup']
            as List<dynamic>? ??
        [];

    final allTitles = <dynamic>[];
    for (final group in allTitlesGroups) {
      if (group is Map<String, dynamic> && group.containsKey('titles')) {
        final titles = group['titles'] as List<dynamic>? ?? [];
        allTitles.addAll(titles);
      }
    }

    return _filterAndMapManga(allTitles, query: query);
  }

  @override
  Future<List<ComicItem>> fetchByGenre(
    String genre, {
    int page = 1,
    int limit = _defaultLimit,
  }) async {
    // MangaPlus doesn't support genre filtering
    return fetchAll(page: page, limit: limit);
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
    int limit = _defaultLimit,
  }) async {
    // MangaPlus has limited filtering
    if (order == 'popular' || order == 'popularity') {
      return fetchPopular(limit: limit);
    } else if (order == 'update' || order == 'updated' || order == 'latest') {
      return fetchNewest(limit: limit);
    }
    return fetchAll(page: page, limit: limit);
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    // MangaPlus doesn't have genre system
    return [];
  }

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    final json = await _apiCall('/title_detailV3?title_id=$href');
    final titleDetailView =
        json['titleDetailView'] as Map<String, dynamic>? ?? {};
    final title = titleDetailView['title'] as Map<String, dynamic>? ?? {};

    final name = title['name'] as String? ?? '';
    // final titleId = title['titleId']?.toString() ?? href;
    final author = (title['author'] as String? ?? '')
        .split('/')
        .map((e) => e.trim())
        .join(', ');
    final thumbnail = title['portraitImageUrl'] as String? ?? '';
    final overview = titleDetailView['overview'] as String? ?? '';

    final titleLabels =
        titleDetailView['titleLabels'] as Map<String, dynamic>? ?? {};
    final releaseSchedule = titleLabels['releaseSchedule'] as String? ?? '';
    final isCompleted =
        releaseSchedule == 'DISABLED' || releaseSchedule == 'COMPLETED';

    final nonAppearanceInfo =
        titleDetailView['nonAppearanceInfo'] as String? ?? '';
    final isHiatus = nonAppearanceInfo.contains('on a hiatus');

    String status;
    if (isCompleted) {
      status = 'Completed';
    } else if (isHiatus) {
      status = 'Hiatus';
    } else {
      status = 'Ongoing';
    }

    final viewingPeriod =
        titleDetailView['viewingPeriodDescription'] as String? ?? '';
    String description = overview;
    if (viewingPeriod.isNotEmpty && !isCompleted) {
      description += '\n\n$viewingPeriod';
    }

    final chapterListGroup =
        titleDetailView['chapterListGroup'] as List<dynamic>? ?? [];
    final chapters = _parseChapters(
      chapterListGroup,
      title['language'] as String? ?? 'ENGLISH',
    );

    // Latest chapter
    String? latestChapter;
    if (chapters.isNotEmpty) {
      latestChapter = chapters.first.title;
    }

    return ComicDetail(
      href: href,
      title: name,
      altTitle: '',
      thumbnail: thumbnail,
      description: description,
      status: status,
      type: 'Manga',
      released: '',
      author: author,
      updatedOn: '',
      rating: '',
      latestChapter: latestChapter,
      genres: [],
      chapters: chapters,
    );
  }

  /// Parse chapters from API response
  List<Chapter> _parseChapters(
    List<dynamic> chapterListGroup,
    String language,
  ) {
    final allChapters = <Map<String, dynamic>>[];

    for (final group in chapterListGroup) {
      if (group is! Map<String, dynamic>) continue;

      final firstChapters = group['firstChapterList'] as List<dynamic>? ?? [];
      final lastChapters = group['lastChapterList'] as List<dynamic>? ?? [];

      for (final ch in firstChapters) {
        if (ch is Map<String, dynamic>) {
          allChapters.add(ch);
        }
      }
      for (final ch in lastChapters) {
        if (ch is Map<String, dynamic>) {
          allChapters.add(ch);
        }
      }
    }

    final chapters = <Chapter>[];
    for (final chapter in allChapters) {
      final chapterId = chapter['chapterId']?.toString() ?? '';
      final subtitle = chapter['subTitle'] as String? ?? '';

      if (chapterId.isEmpty || subtitle.isEmpty) continue;

      // final chapterName = chapter['name'] as String? ?? '';
      final timestamp = chapter['startTimeStamp'] as int? ?? 0;
      final date = timestamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              timestamp * 1000,
            ).toString().split(' ')[0]
          : '';

      chapters.add(Chapter(title: subtitle, href: chapterId, date: date));
    }

    return chapters;
  }

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    // Don't cache chapter viewer as it may expire
    final json = await _apiCall(
      '/manga_viewer?chapter_id=$href&split=yes&img_quality=super_high',
      useCache: false,
    );

    final mangaViewer = json['mangaViewer'] as Map<String, dynamic>? ?? {};
    final pages = mangaViewer['pages'] as List<dynamic>? ?? [];

    final title = mangaViewer['chapterName'] as String? ?? 'Chapter $href';
    final panels = <String>[];

    for (final page in pages) {
      if (page is! Map<String, dynamic>) continue;

      final mangaPage = page['mangaPage'] as Map<String, dynamic>?;
      if (mangaPage == null) continue;

      final imageUrl = mangaPage['imageUrl'] as String? ?? '';
      final encryptionKey = mangaPage['encryptionKey'] as String? ?? '';

      if (imageUrl.isEmpty) continue;

      final fullUrl = encryptionKey.isEmpty
          ? imageUrl
          : '$imageUrl#$encryptionKey';
      panels.add(fullUrl);
    }

    if (panels.isEmpty) {
      throw Exception('No pages found in chapter');
    }

    // MangaPlus doesn't provide prev/next in viewer API
    return ReadChapter(title: title, prev: '', next: '', panel: panels);
  }

  /// Decode image with XOR cipher if encryption key is present
  Uint8List? decodeImage(Uint8List imageBytes, String? encryptionKey) {
    if (encryptionKey == null || encryptionKey.isEmpty) {
      return imageBytes;
    }

    try {
      final keyBytes = <int>[];
      for (int i = 0; i < encryptionKey.length; i += 2) {
        final hexByte = encryptionKey.substring(i, i + 2);
        keyBytes.add(int.parse(hexByte, radix: 16));
      }

      // XOR decode
      final decoded = Uint8List(imageBytes.length);
      for (int i = 0; i < imageBytes.length; i++) {
        decoded[i] = imageBytes[i] ^ keyBytes[i % keyBytes.length];
      }

      return decoded;
    } catch (e) {
      // Return original if decoding fails
      return imageBytes;
    }
  }

  /// Helper to fetch and decode image
  Future<Uint8List> fetchImage(String url) async {
    String imageUrl = url;
    String? encryptionKey;

    // Extract encryption key from fragment
    if (url.contains('#')) {
      final parts = url.split('#');
      imageUrl = parts[0];
      encryptionKey = parts.length > 1 ? parts[1] : null;
    }

    final response = await _client.get(
      Uri.parse(imageUrl),
      headers: imageHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load image: ${response.statusCode}');
    }

    final imageBytes = response.bodyBytes;

    // Decode if encrypted
    if (encryptionKey != null && encryptionKey.isNotEmpty) {
      return decodeImage(imageBytes, encryptionKey) ?? imageBytes;
    }

    return imageBytes;
  }

  /// Clear all caches
  void clearCache() {
    _apiCache.clear();
    _allTitlesCache = null;
    _allTitlesCacheTime = null;
  }

  /// Clear only API cache (keep all titles cache)
  void clearApiCache() {
    _apiCache.clear();
  }

  void dispose() {
    _client.close();
    clearCache();
  }
}

/// Cache result model
class _CachedResult {
  final dynamic data;
  final DateTime timestamp;

  _CachedResult({required this.data, required this.timestamp});
}
