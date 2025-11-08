import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

final jsRuntime = getJavascriptRuntime();

class BatotoParser extends ComicParser {
  static const String _baseUrl = 'https://ato.to';

  final http.Client _client;

  final Map<String, CachedResult> _listCache = {};

  static const int _maxConcurrentRequests = 3;

  BatotoParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'Batoto';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'EN';

  /// Common headers for requests
  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': baseUrl,
  };

  /// Available genres for Batoto
  static final List<Genre> _availableGenres = [];

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

  /// Helper to extract relative URL
  String _toRelativeUrl(String url) {
    if (url.startsWith(baseUrl)) {
      return url.substring(baseUrl.length);
    }
    if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      return uri.path;
    }
    return url;
  }

  /// Parse date string to timestamp
  int _parseChapterDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 0;

    try {
      final parts = dateStr.toLowerCase().split(' ');
      if (parts.length < 2) return 0;

      final value = int.tryParse(parts[0]) ?? 0;
      final unit = parts[1];

      final now = DateTime.now();
      DateTime targetDate;

      if (unit.contains('sec')) {
        targetDate = now.subtract(Duration(seconds: value));
      } else if (unit.contains('min')) {
        targetDate = now.subtract(Duration(minutes: value));
      } else if (unit.contains('hour')) {
        targetDate = now.subtract(Duration(hours: value));
      } else if (unit.contains('day')) {
        targetDate = now.subtract(Duration(days: value));
      } else if (unit.contains('week')) {
        targetDate = now.subtract(Duration(days: value * 7));
      } else if (unit.contains('month')) {
        targetDate = DateTime(now.year, now.month - value, now.day);
      } else if (unit.contains('year')) {
        targetDate = DateTime(now.year - value, now.month, now.day);
      } else {
        return 0;
      }

      return targetDate.millisecondsSinceEpoch;
    } catch (e) {
      return 0;
    }
  }

  /// Format timestamp to date string
  String _formatDate(int timestamp) {
    if (timestamp == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get sort order parameter
  String _getSortOrderParam(String order) {
    switch (order) {
      case 'alphabetical':
        return 'title.az';
      case 'updated':
        return 'update.za';
      case 'newest':
        return 'create.za';
      case 'popular':
        return 'views_a.za';
      case 'popular_year':
        return 'views_y.za';
      case 'popular_month':
        return 'views_m.za';
      case 'popular_week':
        return 'views_w.za';
      case 'popular_today':
        return 'views_d.za';
      case 'popular_hour':
        return 'views_h.za';
      default:
        return 'update.za';
    }
  }

  /// Parse manga list from HTML
  List<ComicItem> _parseComicList(Document doc) {
    final items = <ComicItem>[];
    final root = doc.getElementById('series-list');
    if (root == null) return items;

    for (final div in root.children) {
      try {
        final a = div.querySelector('a');
        if (a == null) continue;

        final href = a.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        var title = div.querySelector('.item-title')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final thumbnail =
            div.querySelector('img[src]')?.attributes['src'] ?? '';
        final altTitle = div.querySelector('.item-alias')?.text.trim() ?? '';

        final flagElement = div.querySelector('em.item-flag[data-lang]');
        if (flagElement != null) {
          final flagCode =
              flagElement.attributes['data-lang']?.trim().toUpperCase() ?? '';
          if (flagCode.isNotEmpty) {
            var code = "[$flagCode]";
            title = '$code - $title';
          }
        }

        items.add(
          ComicItem(
            title: title,
            href: _toRelativeUrl(href),
            thumbnail: thumbnail.isNotEmpty ? _toAbsoluteUrl(thumbnail) : '',
            rating: '',
            type: altTitle,
          ),
        );
      } catch (e) {
        continue;
      }
    }

    return items;
  }

  /// Check if page has results
  bool _hasResults(Document doc, int page) {
    // Check for no matches message
    if (doc.querySelector('.browse-no-matches') != null) {
      return false;
    }

    // Check active page number
    final activePages = doc.querySelectorAll(
      'nav ul.pagination > li.page-item.active a',
    );
    if (activePages.isNotEmpty) {
      // Ambil halaman aktif terakhir dari pagination
      final lastActivePage = activePages.last.text.trim();

      // Jika text berisi "..." berarti ini halaman pertama yang menampilkan "1 ..."
      if (lastActivePage.contains('...')) {
        final pageNum =
            int.tryParse(lastActivePage.split('...').first.trim()) ?? 1;
        return pageNum == page;
      }

      // Jika text adalah angka biasa
      final activePageNum = int.tryParse(lastActivePage) ?? 0;
      if (activePageNum > 0 && activePageNum != page) {
        return false;
      }
    }

    // Jika tidak ada pagination (halaman 1 atau halaman tunggal), periksa apakah ada series-list
    final seriesList = doc.getElementById('series-list');
    return seriesList != null && seriesList.children.isNotEmpty;
  }

  @override
  Future<List<ComicItem>> fetchPopular() async {
    const cacheKey = 'popular-1';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/browse?sort=views_a.za';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load popular: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);

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

    final url = '$baseUrl/browse?sort=views_w.za';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load recommended: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);

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

    final url = '$baseUrl/browse?sort=create.za&page=$page';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load newest: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final items = _parseComicList(doc);

    // Jika tidak ada items, throw exception
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Check if this is the correct page (optional, untuk validasi)
    if (!_hasResults(doc, page)) {
      // Jika validation gagal tapi ada items, kembalikan items
      // (ini untuk handle edge case di halaman 1)
      if (items.isNotEmpty) {
        _saveToCache(cacheKey, items);
        return items;
      }
      throw Exception('Page not found');
    }

    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    final cacheKey = 'all-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/browse?sort=update.za&page=$page';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load all: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final items = _parseComicList(doc);

    // Jika tidak ada items, throw exception
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Check if this is the correct page (optional, untuk validasi)
    if (!_hasResults(doc, page)) {
      // Jika validation gagal tapi ada items, kembalikan items
      // (ini untuk handle edge case di halaman 1)
      if (items.isNotEmpty) {
        _saveToCache(cacheKey, items);
        return items;
      }
      throw Exception('Page not found');
    }

    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final cacheKey = 'search-$encodedQuery';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/search?word=$encodedQuery';

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to search: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    if (doc.querySelector('.browse-no-matches') != null) {
      throw Exception('No results found');
    }

    final items = _parseComicList(doc);
    if (items.isEmpty) {
      throw Exception('No results found');
    }

    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final cacheKey = 'genre-$genre-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final url = '$baseUrl/browse?genres=$genre&page=$page';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load genre: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final items = _parseComicList(doc);

    // Jika tidak ada items, throw exception
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Check if this is the correct page (optional, untuk validasi)
    if (!_hasResults(doc, page)) {
      // Jika validation gagal tapi ada items, kembalikan items
      if (items.isNotEmpty) {
        _saveToCache(cacheKey, items);
        return items;
      }
      throw Exception('Page not found');
    }

    _saveToCache(cacheKey, items);

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
    final cacheKey = 'filtered-$page-$genre-$status-$type-$order';

    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      return cached;
    }

    final sortParam = order != null ? _getSortOrderParam(order) : 'update.za';
    final genreParam = genre ?? '';
    final statusParam = status ?? '';

    final url =
        '$baseUrl/browse?sort=$sortParam&genres=$genreParam&release=$statusParam&page=$page';

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load filtered: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    final items = _parseComicList(doc);

    // Jika tidak ada items, throw exception
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    // Check if this is the correct page (optional, untuk validasi)
    if (!_hasResults(doc, page)) {
      // Jika validation gagal tapi ada items, kembalikan items
      if (items.isNotEmpty) {
        _saveToCache(cacheKey, items);
        return items;
      }
      throw Exception('Page not found');
    }

    _saveToCache(cacheKey, items);

    return items;
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    // Return cached genres if available
    if (_availableGenres.isNotEmpty) {
      return _availableGenres;
    }

    final url = '$baseUrl/browse';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load genres: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final scripts = doc.querySelectorAll('script');

    for (final script in scripts) {
      final scriptText = script.text;

      // Look for _genres object using more flexible regex
      final genresIndex = scriptText.indexOf('const _genres =');
      if (genresIndex == -1) continue;

      // Find the start of the object
      final startIndex = scriptText.indexOf('{', genresIndex);
      if (startIndex == -1) continue;

      // Find the matching closing brace
      var braceCount = 0;
      var endIndex = -1;
      for (var i = startIndex; i < scriptText.length; i++) {
        if (scriptText[i] == '{') {
          braceCount++;
        } else if (scriptText[i] == '}') {
          braceCount--;
          if (braceCount == 0) {
            endIndex = i + 1;
            break;
          }
        }
      }

      if (endIndex == -1) continue;

      try {
        final genresJson = scriptText.substring(startIndex, endIndex);

        final json = jsonDecode(genresJson) as Map<String, dynamic>;

        // Iterate through all genres
        for (final key in json.keys) {
          final item = json[key];

          // Check if item is a Map (genre object)
          if (item is Map<String, dynamic>) {
            final title = item['text'] as String?;
            final file = item['file'] as String?;

            if (title != null && file != null) {
              _availableGenres.add(
                Genre(
                  title: _toTitleCase(title),
                  href: file, // Simpan file saja, bukan dengan '/'
                ),
              );
            }
          }
        }

        // Sort genres alphabetically
        _availableGenres.sort((a, b) => a.title.compareTo(b.title));

        return _availableGenres;
      } catch (e) {
        throw Exception('Failed to parse genres JSON: $e');
      }
    }

    throw Exception('Genres list not found in scripts');
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

  /// Convert string to title case
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? ''
              : word[0].toUpperCase() + word.substring(1).toLowerCase(),
        )
        .join(' ');
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
    final root = doc.getElementById('mainer');
    if (root == null) {
      throw Exception('Comic not found');
    }

    final details = root.querySelector('.detail-set');
    if (details == null) {
      throw Exception('Comic details not found');
    }

    final title = root.querySelector('h3.item-title')?.text.trim() ?? '';

    final coverUrl = details.querySelector('img[src]')?.attributes['src'] ?? '';

    final descriptionElement = details.querySelector(
      '#limit-height-body-summary',
    );
    final descriptionHtml = descriptionElement
        ?.querySelector('.limit-html')
        ?.innerHtml
        .trim();
    final description = descriptionHtml ?? '';

    final attrs =
        details.querySelector('.attr-main')?.querySelectorAll('.attr-item') ??
        [];
    final attrMap = <String, Element>{};
    for (final attr in attrs) {
      final key = attr.children.isNotEmpty ? attr.children[0].text.trim() : '';
      final value = attr.children.length > 1 ? attr.children[1] : attr;
      if (key.isNotEmpty) {
        attrMap[key] = value;
      }
    }

    final author = attrMap['Authors:']?.text.trim() ?? '';

    final statusText = attrMap['Original work:']?.text.trim() ?? '';
    String status = '';
    switch (statusText) {
      case 'Ongoing':
        status = 'Ongoing';
        break;
      case 'Completed':
        status = 'Completed';
        break;
      case 'Cancelled':
        status = 'Cancelled';
        break;
      case 'Hiatus':
        status = 'Hiatus';
        break;
      default:
        status = statusText;
    }

    final genres = <Genre>[];
    final genreElements = attrMap['Genres:']?.querySelectorAll('span') ?? [];
    for (final el in genreElements) {
      final genreTitle = el.text.trim();
      if (genreTitle.isNotEmpty) {
        genres.add(
          Genre(
            title: genreTitle,
            href: '/${genreTitle.toLowerCase().replaceAll(' ', '_')}/',
          ),
        );
      }
    }

    final chapters = <Chapter>[];
    final episodeList = root
        .querySelector('.episode-list')
        ?.querySelector('.main');
    if (episodeList != null) {
      final chapterDivs = episodeList.children.toList().reversed.toList();
      for (var i = 0; i < chapterDivs.length; i++) {
        final div = chapterDivs[i];
        final a = div.querySelector('a.chapt');
        if (a == null) continue;

        final chHref = a.attributes['href'] ?? '';
        if (chHref.isEmpty) continue;

        final chTitle = a.text.trim();
        final extra = div.querySelector('.extra');

        final dateText =
            extra?.querySelectorAll('i').lastOrNull?.text.trim() ?? '';
        final timestamp = _parseChapterDate(dateText);

        chapters.add(
          Chapter(
            title: chTitle.isNotEmpty ? chTitle : 'Chapter ${i + 1}',
            href: _toRelativeUrl(chHref),
            date: _formatDate(timestamp),
          ),
        );
      }
    }

    return ComicDetail(
      href: _toRelativeUrl(href),
      title: title,
      altTitle: '',
      thumbnail: coverUrl.isNotEmpty ? _toAbsoluteUrl(coverUrl) : '',
      description: description,
      status: status,
      type: genres.isNotEmpty ? genres.first.title : '',
      released: '',
      author: author,
      updatedOn: '',
      rating: '',
      latestChapter: chapters.isNotEmpty ? chapters.last.title : null,
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

    final title = doc.querySelector('title')?.text.trim() ?? '';

    // Extract navigation - FIXED: menggunakan selector yang lebih spesifik dari HTML
    String prev = '';
    String next = '';

    // Previous chapter - cari tombol dengan class 'btn' dan text 'Prev'
    final prevButtons = doc.querySelectorAll('a.btn[href]');
    for (final btn in prevButtons) {
      final text = btn.text.trim();
      if (text.contains('Prev') || text.contains('◀')) {
        final href = btn.attributes['href'] ?? '';
        // Pastikan ini chapter link, bukan detail link
        if (href.isNotEmpty && href.contains('/chapter/')) {
          prev = _toRelativeUrl(href);
          break;
        }
      }
    }

    // Next chapter - cari tombol dengan text 'Next' atau yang tidak ada text 'Prev'/'Detail'
    final nextButtons = doc.querySelectorAll('a.btn[href]');
    for (final btn in nextButtons) {
      final text = btn.text.trim();
      final href = btn.attributes['href'] ?? '';

      // Skip jika ini tombol prev atau detail
      if (text.contains('Prev') ||
          text.contains('◀') ||
          text.contains('Detail') ||
          text.isEmpty) {
        continue;
      }

      // Cek apakah ini chapter link
      if (href.contains('/chapter/')) {
        next = _toRelativeUrl(href);
        break;
      }
    }

    if (prev.isEmpty || next.isEmpty) {
      final navContainers = doc.querySelectorAll('.episode-nav');
      for (final nav in navContainers) {
        if (prev.isEmpty) {
          final prevLink = nav.querySelector('.nav-prev a[href*="/chapter/"]');
          if (prevLink != null) {
            prev = _toRelativeUrl(prevLink.attributes['href'] ?? '');
          }
        }

        if (next.isEmpty) {
          final nextLink = nav.querySelector('.nav-next a[href*="/chapter/"]');
          if (nextLink != null) {
            final href = nextLink.attributes['href'] ?? '';
            // Pastikan bukan link ke detail page
            if (!href.contains('/series/')) {
              next = _toRelativeUrl(href);
            }
          }
        }
      }
    }

    final scripts = doc.querySelectorAll('script');
    List<String> panels = [];

    for (final script in scripts) {
      final scriptText = script.text;

      // Look for imgHttps array
      final imgHttpsIndex = scriptText.indexOf('const imgHttps =');
      if (imgHttpsIndex == -1) continue;

      final startIndex = scriptText.indexOf('[', imgHttpsIndex);
      final endIndex = scriptText.indexOf(';', startIndex);
      if (startIndex == -1 || endIndex == -1) continue;

      try {
        final imagesJson = scriptText.substring(startIndex, endIndex);
        final images = jsonDecode(imagesJson) as List;

        final batoPassMatch = RegExp(
          r'const batoPass\s*=\s*([^;]+);',
          dotAll: true,
        ).firstMatch(scriptText);

        final batoWordMatch = RegExp(
          r'const batoWord\s*=\s*"([^"]+)"',
        ).firstMatch(scriptText);

        if (batoPassMatch == null || batoWordMatch == null) {
          throw Exception('Cannot find batoPass or batoWord');
        }

        final batoPassRaw = batoPassMatch.group(1)!.trim();
        final batoWord = batoWordMatch.group(1)!;

        final password = jsRuntime.evaluate(batoPassRaw).stringResult;

        // Decrypt batoWord
        final decrypted = _decryptAES(batoWord, password);
        final args = jsonDecode(decrypted) as List;

        for (var i = 0; i < images.length; i++) {
          final url = images[i] as String;
          final imageUrl = args.isNotEmpty && i < args.length
              ? '$url?${args[i]}'
              : url;
          panels.add(imageUrl);
        }

        break;
      } catch (e) {
        throw Exception('Failed to parse images: $e');
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    return ReadChapter(title: title, prev: prev, next: next, panel: panels);
  }

  /// Decrypt AES encrypted data
  String _decryptAES(String encryptedBase64, String password) {
    try {
      // Decode base64
      final cipherData = base64.decode(encryptedBase64);

      final saltData = cipherData.sublist(8, 16);

      // Generate key and IV
      final keyIv = _generateKeyAndIV(
        keyLength: 32,
        ivLength: 16,
        salt: saltData,
        password: utf8.encode(password),
      );

      final encryptedData = cipherData.sublist(16);

      // Decrypt
      final key = encrypt.Key(keyIv.key);
      final iv = encrypt.IV(keyIv.iv);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );

      final decrypted = encrypter.decryptBytes(
        encrypt.Encrypted(encryptedData),
        iv: iv,
      );

      return utf8.decode(decrypted);
    } catch (e) {
      throw Exception('Failed to decrypt: $e');
    }
  }

  /// Generate AES key and IV from password and salt
  ({Uint8List key, Uint8List iv}) _generateKeyAndIV({
    required int keyLength,
    required int ivLength,
    required Uint8List salt,
    required Uint8List password,
  }) {
    final digestLength = 16; // MD5 digest length
    final requiredLength =
        ((keyLength + ivLength + digestLength - 1) ~/ digestLength) *
        digestLength;
    final generatedData = Uint8List(requiredLength);
    var generatedLength = 0;

    while (generatedLength < keyLength + ivLength) {
      final digest = md5.convert([
        if (generatedLength > 0)
          ...generatedData.sublist(
            generatedLength - digestLength,
            generatedLength,
          ),
        ...password,
        ...salt,
      ]);

      final hashBytes = Uint8List.fromList(digest.bytes);

      generatedData.setRange(
        generatedLength,
        generatedLength + digestLength,
        hashBytes,
      );
      generatedLength += digestLength;
    }

    return (
      key: generatedData.sublist(0, keyLength),
      iv: ivLength > 0
          ? generatedData.sublist(keyLength, keyLength + ivLength)
          : Uint8List(0),
    );
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
