import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

/// Base parser for NatsuId WordPress theme
/// Theme: https://themesinfo.com/natsu_id-theme-wordpress-c8x1c
/// Author: Dzul Qurnain
///
/// This is an abstract class that handles the common logic for all
/// Natsu-based manga sites. Subclasses only need to provide [domain]
/// and optionally override specific methods.
abstract class NatsuParser extends ComicParser {
  final http.Client _client;
  final Map<String, CachedResult> _listCache = {};

  /// Cached nonce for advanced search requests
  String? _nonce;

  NatsuParser({http.Client? client}) : _client = client ?? http.Client();

  // ── Abstract getters (must be provided by subclasses) ──────────

  /// The domain of the site (e.g. "kiryuu03.com")
  String get domain;

  // ── Common headers ─────────────────────────────────────────────

  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Referer': 'https://$domain/',
    'Origin': 'https://$domain',
  };

  // ── URL helpers ────────────────────────────────────────────────

  String toAbsoluteUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return 'https://$domain$url';
    return 'https://$domain/$url';
  }

  String toRelativeUrl(String url) {
    final domainVariants = ['https://$domain', 'http://$domain'];
    for (final prefix in domainVariants) {
      if (url.startsWith(prefix)) {
        url = url.substring(prefix.length);
        break;
      }
    }
    if (url.startsWith('http')) {
      final uri = Uri.parse(url);
      url = uri.path;
      if (uri.query.isNotEmpty) url = '$url?${uri.query}';
    }
    if (!url.startsWith('/')) url = '/$url';
    return url;
  }

  /// Extracts the bare slug from a genre path.
  /// e.g. "/genre/action/" → "action", "/action/" → "action", "action" → "action"
  String _extractSlug(String genre) {
    return genre
        .replaceAll(RegExp(r'^.*/genre/'), '')
        .replaceAll(RegExp(r'^/'), '')
        .replaceAll(RegExp(r'/$'), '');
  }

  // ── Cache helpers ──────────────────────────────────────────────

  bool _isCacheValid(String key) {
    final cached = _listCache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < cacheExpiry;
  }

  List<ComicItem>? _getFromCache(String key) {
    if (_isCacheValid(key)) return _listCache[key]?.items;
    _listCache.remove(key);
    return null;
  }

  void _saveToCache(String key, List<ComicItem> items) {
    _listCache[key] = CachedResult(items: items, timestamp: DateTime.now());
  }

  // ── Nonce ──────────────────────────────────────────────────────

  /// Fetches (and caches) the CSRF nonce required by advanced search.
  Future<String> _getNonce() async {
    if (_nonce != null) return _nonce!;

    final url =
        'https://$domain/wp-admin/admin-ajax.php?type=search_form&action=get_nonce';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch nonce: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final nonceValue =
        doc.querySelector('input[name="search_nonce"]')?.attributes['value'] ??
        '';
    if (nonceValue.isEmpty) {
      throw Exception('Nonce not found in response');
    }

    _nonce = nonceValue;
    return _nonce!;
  }

  // ── HTTP POST (multipart) ─────────────────────────────────────

  /// Sends a multipart POST and returns the parsed HTML document.
  Future<Document> _httpPost(
    String url,
    Map<String, String> form, {
    Map<String, String>? extraHeaders,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));

    // Add common headers
    request.headers.addAll(_headers);

    // Add extra headers if provided
    if (extraHeaders != null) {
      request.headers.addAll(extraHeaders);
    }

    // Add form fields
    form.forEach((key, value) {
      request.fields[key] = value;
    });

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('POST $url failed: ${response.statusCode}');
    }

    return html_parser.parse(response.body);
  }

  // ── Core advanced search ───────────────────────────────────────

  /// The core method that builds the multipart form and calls the
  /// NatsuId WordPress advanced search endpoint, matching the Kotlin
  /// `getListPage()` implementation.
  Future<List<ComicItem>> _advancedSearch({
    int page = 1,
    String orderby = 'popular',
    String? query,
    List<String>? genres,
    List<String>? genresExclude,
    String? status,
    String? type,
  }) async {
    final url =
        'https://$domain/wp-admin/admin-ajax.php?action=advanced_search';

    final nonce = await _getNonce();

    final form = <String, String>{};
    form['nonce'] = nonce;

    // Genre inclusion
    form['inclusion'] = 'OR';
    if (genres != null && genres.isNotEmpty) {
      final slugs = genres.map(_extractSlug).toList();
      form['genre'] = jsonEncode(slugs);
    } else {
      form['genre'] = '[]';
    }

    // Genre exclusion
    form['exclusion'] = 'OR';
    if (genresExclude != null && genresExclude.isNotEmpty) {
      final slugs = genresExclude.map(_extractSlug).toList();
      form['genre_exclude'] = jsonEncode(slugs);
    } else {
      form['genre_exclude'] = '[]';
    }

    form['page'] = page.toString();
    form['author'] = '[]';
    form['artist'] = '[]';
    form['project'] = '0';

    // Type filter
    if (type != null && type.isNotEmpty) {
      final typeList = <String>[];
      switch (type.toLowerCase()) {
        case 'manga':
          typeList.add('manga');
          break;
        case 'manhwa':
          typeList.add('manhwa');
          break;
        case 'manhua':
          typeList.add('manhua');
          break;
        case 'comic':
        case 'comics':
          typeList.add('comic');
          break;
        case 'novel':
          typeList.add('novel');
          break;
        default:
          typeList.add(type.toLowerCase());
      }
      form['type'] = jsonEncode(typeList);
    } else {
      form['type'] = '[]';
    }

    // Status filter
    if (status != null && status.isNotEmpty) {
      final statusList = <String>[];
      switch (status.toLowerCase()) {
        case 'ongoing':
          statusList.add('ongoing');
          break;
        case 'completed':
          statusList.add('completed');
          break;
        case 'hiatus':
        case 'on-hiatus':
          statusList.add('on-hiatus');
          break;
        default:
          statusList.add(status.toLowerCase());
      }
      form['status'] = jsonEncode(statusList);
    } else {
      form['status'] = '[]';
    }

    form['order'] = 'desc';
    form['orderby'] = orderby;

    if (query != null && query.isNotEmpty) {
      form['query'] = query;
    }

    final doc = await _httpPost(url, form);
    return parseMangaList(doc);
  }

  // ── Parse manga list ──────────────────────────────────────────

  /// Parses the HTML response from advanced search into [ComicItem]s.
  /// Matches Kotlin's `parseMangaList()`.
  List<ComicItem> parseMangaList(Document doc) {
    final items = <ComicItem>[];

    final divElements = doc.querySelectorAll('body > div');
    for (final div in divElements) {
      try {
        // Find the main manga link
        final mainLink = div.querySelector('a[href*="/manga/"]');
        if (mainLink == null) continue;

        final href = toRelativeUrl(mainLink.attributes['href'] ?? '');
        if (href.contains('/chapter-')) continue;

        // Title
        final titleEl =
            div.querySelector('a.text-base') ??
            div.querySelector('a.text-white') ??
            div.querySelector('h1');
        String title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) {
          title = mainLink.attributes['title']?.trim() ?? '';
        }
        if (title.isEmpty) {
          title = mainLink.text.trim();
        }
        if (title.isEmpty) continue;

        // Cover image
        final imgEl = div.querySelector('img');
        String thumbnail =
            imgEl?.attributes['src'] ??
            imgEl?.attributes['data-src'] ??
            imgEl?.attributes['data-lazy-src'] ??
            '';
        if (thumbnail.isNotEmpty) {
          thumbnail = toAbsoluteUrl(thumbnail);
        }

        // Rating — store raw text (e.g. "8.0") without normalization
        final ratingEl =
            div.querySelector('.numscore') ??
            div.querySelector('span.text-yellow-400');
        String? rating;
        if (ratingEl != null) {
          final ratingText = ratingEl.text.trim();
          if (double.tryParse(ratingText) != null) {
            rating = ratingText;
          }
        }

        // State / type
        Element? stateEl = div.querySelector('span.bg-accent');
        if (stateEl == null) {
          for (final p in div.querySelectorAll('p')) {
            final pText = p.text.toLowerCase();
            if (pText.contains('ongoing') ||
                pText.contains('completed') ||
                pText.contains('hiatus')) {
              stateEl = p;
              break;
            }
          }
        }
        String? comicType;
        if (stateEl != null) {
          final stateText = stateEl.text.toLowerCase();
          if (stateText.contains('ongoing')) {
            comicType = 'Ongoing';
          } else if (stateText.contains('completed')) {
            comicType = 'Completed';
          } else if (stateText.contains('hiatus')) {
            comicType = 'Hiatus';
          }
        }

        items.add(
          ComicItem(
            title: title,
            href: href,
            thumbnail: thumbnail,
            rating: rating,
            type: comicType,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return items;
  }

  // ── ComicParser interface ──────────────────────────────────────

  @override
  String get baseUrl => 'https://$domain';

  @override
  Future<List<ComicItem>> fetchPopular() async {
    const cacheKey = 'natsu-popular-1';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final results = await _advancedSearch(page: 1, orderby: 'popular');
    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> fetchRecommended() async {
    const cacheKey = 'natsu-recommended-1';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final results = await _advancedSearch(page: 1, orderby: 'rating');
    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final cacheKey = 'natsu-newest-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final results = await _advancedSearch(page: page, orderby: 'updated');
    if (results.isEmpty) throw Exception('Page not found');

    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    final cacheKey = 'natsu-all-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final results = await _advancedSearch(page: page, orderby: 'title');
    if (results.isEmpty) throw Exception('Page not found');

    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final cacheKey = 'natsu-search-$encodedQuery';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final results = await _advancedSearch(page: 1, query: query);
    if (results.isEmpty) throw Exception('No results found');

    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final cacheKey = 'natsu-genre-$genre-$page';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final results = await _advancedSearch(
      page: page,
      genres: [genre],
      orderby: 'popular',
    );
    if (results.isEmpty) throw Exception('No results found');

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
    final cacheKey = 'natsu-filtered-$page-$genre-$status-$type-$order';

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // Map order param to NatsuId orderby
    String orderby;
    switch (order?.toLowerCase()) {
      case 'popular':
      case 'popularity':
        orderby = 'popular';
        break;
      case 'latest':
      case 'updated':
        orderby = 'updated';
        break;
      case 'rating':
        orderby = 'rating';
        break;
      case 'title':
      case 'alphabetical':
        orderby = 'title';
        break;
      default:
        orderby = 'popular';
    }

    final results = await _advancedSearch(
      page: page,
      orderby: orderby,
      genres: genre != null && genre.isNotEmpty ? [genre] : null,
      status: status,
      type: type,
    );

    if (results.isEmpty) throw Exception('No results found');

    _saveToCache(cacheKey, results);
    return results;
  }

  // ── Genres ─────────────────────────────────────────────────────

  @override
  Future<List<Genre>> fetchGenres() async {
    try {
      // Try WP JSON API first (more reliable)
      final url =
          'https://$domain/wp-json/wp/v2/genre?per_page=100&page=1&orderby=count&order=desc';
      final response = await _client.get(Uri.parse(url), headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonArray = jsonDecode(response.body);
        final genres = <Genre>[];

        for (final item in jsonArray) {
          final slug = (item['slug'] as String?)?.trim() ?? '';
          final name = (item['name'] as String?)?.trim() ?? '';
          if (slug.isEmpty || name.isEmpty) continue;

          genres.add(Genre(title: _toTitleCase(name), href: '/$slug/'));
        }

        if (genres.isNotEmpty) return genres;
      }
    } catch (_) {
      // Fallback below
    }

    // Fallback: scrape /advanced-search/ page
    try {
      final url = 'https://$domain/advanced-search/';
      final response = await _client.get(Uri.parse(url), headers: _headers);

      if (response.statusCode != 200) return [];

      final doc = html_parser.parse(response.body);
      final scripts = doc.querySelectorAll('script');

      String? scriptData;
      for (final script in scripts) {
        final data = script.text;
        if (data.contains('var searchTerms')) {
          scriptData = data;
          break;
        }
      }

      if (scriptData == null) return [];

      final jsonString = scriptData
          .substring(
            scriptData.indexOf('var searchTerms =') +
                'var searchTerms ='.length,
          )
          .trim();
      final endIndex = jsonString.lastIndexOf(';');
      final cleanJson = endIndex > 0
          ? jsonString.substring(0, endIndex)
          : jsonString;

      final json = jsonDecode(cleanJson) as Map<String, dynamic>;
      final genreObject = json['genre'] as Map<String, dynamic>?;
      if (genreObject == null) return [];

      final genres = <Genre>[];
      for (final entry in genreObject.entries) {
        final item = entry.value as Map<String, dynamic>?;
        if (item == null) continue;
        final taxonomy = item['taxonomy'] as String? ?? '';
        if (taxonomy != 'genre') continue;

        final slug = (item['slug'] as String?)?.trim() ?? '';
        final name = (item['name'] as String?)?.trim() ?? '';
        if (slug.isEmpty || name.isEmpty) continue;

        genres.add(Genre(title: _toTitleCase(name), href: '/$slug/'));
      }

      return genres;
    } catch (_) {
      return [];
    }
  }

  // ── Detail ─────────────────────────────────────────────────────

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final absUrl = toAbsoluteUrl(href);
    final response = await _client.get(Uri.parse(absUrl), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load detail: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    // ── Manga ID for chapter loading
    String mangaId = '';

    // Try hx-get attribute
    final hxEl = doc.querySelector('[hx-get*="manga_id="]');
    if (hxEl != null) {
      final hxGet = hxEl.attributes['hx-get'] ?? '';
      final match = RegExp(r'manga_id=([^&]+)').firstMatch(hxGet);
      if (match != null) mangaId = match.group(1)?.trim() ?? '';
    }

    // Try input / data attribute
    if (mangaId.isEmpty) {
      final idEl = doc.querySelector('input#manga_id, [data-manga-id]');
      if (idEl != null) {
        mangaId = idEl.attributes['value']?.trim() ?? '';
        if (mangaId.isEmpty) {
          mangaId = idEl.attributes['data-manga-id']?.trim() ?? '';
        }
      }
    }

    // Fallback: extract from URL
    if (mangaId.isEmpty) {
      final match = RegExp(r'/manga/([^/]+)').firstMatch(href);
      if (match != null) mangaId = match.group(1) ?? '';
    }

    // ── Title
    final titleEl = doc.querySelector('h1[itemprop="name"]');
    final title = titleEl?.text.trim() ?? '';

    // ── Alt titles
    String altTitle = '';
    if (titleEl != null && titleEl.nextElementSibling != null) {
      altTitle = titleEl.nextElementSibling!.text.trim();
    }

    // ── Description
    final descEls = doc.querySelectorAll('div[itemprop="description"]');
    final description = descEls
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n\n');

    // ── Cover
    String thumbnail =
        doc.querySelector('div[itemprop="image"] > img')?.attributes['src'] ??
        '';
    if (thumbnail.isEmpty) {
      thumbnail =
          doc
              .querySelector('div[itemprop="image"] > img')
              ?.attributes['data-src'] ??
          '';
    }
    if (thumbnail.isNotEmpty) {
      thumbnail = toAbsoluteUrl(thumbnail);
    }

    // ── Genres
    final genreEls = doc.querySelectorAll('a[itemprop="genre"]');
    final genres = <Genre>[];
    for (final a in genreEls) {
      final genreHref = a.attributes['href'] ?? '';
      final slug = genreHref
          .replaceAll(RegExp(r'.*/genre/'), '')
          .replaceAll(RegExp(r'/$'), '');
      final name = a.text.trim();
      if (slug.isNotEmpty && name.isNotEmpty) {
        genres.add(Genre(title: _toTitleCase(name), href: '/$slug/'));
      }
    }

    // ── Info fields helper
    String? findInfoText(String key) {
      final infoElements = doc.querySelectorAll('div.space-y-2 > .flex');
      for (final el in infoElements) {
        final h4 = el.querySelector('h4');
        if (h4 != null && h4.text.toLowerCase().contains(key.toLowerCase())) {
          return el.querySelector('p.font-normal')?.text.trim();
        }
      }
      return null;
    }

    // ── Status
    final stateText = findInfoText('Status')?.toLowerCase() ?? '';
    String status;
    if (stateText.contains('ongoing')) {
      status = 'Ongoing';
    } else if (stateText.contains('completed')) {
      status = 'Completed';
    } else if (stateText.contains('hiatus')) {
      status = 'Hiatus';
    } else {
      status = 'Unknown';
    }

    // ── Author
    final author = findInfoText('Author') ?? '';

    // ── Type
    final typeText = findInfoText('Type') ?? '';

    // ── Rating
    final ratingText =
        doc.querySelector('.numscore, span.text-yellow-400')?.text.trim() ?? '';

    // ── Chapters
    final chapters = await _loadChapters(mangaId, absUrl);

    return ComicDetail(
      href: toRelativeUrl(href),
      title: title.isNotEmpty ? title : href,
      altTitle: altTitle,
      thumbnail: thumbnail,
      description: description,
      status: status,
      type: typeText,
      released: '',
      author: author,
      updatedOn: '',
      rating: ratingText,
      latestChapter: chapters.isNotEmpty ? chapters.first.title : null,
      genres: genres,
      chapters: chapters,
    );
  }

  // ── Load chapters (paginated AJAX) ─────────────────────────────

  /// Loads all chapters for a manga by paginating through
  /// `admin-ajax.php?action=chapter_list`.
  Future<List<Chapter>> _loadChapters(
    String mangaId,
    String mangaAbsoluteUrl,
  ) async {
    final chapters = <Chapter>[];

    final extraHeaders = <String, String>{
      'HX-Request': 'true',
      'HX-Target': 'chapter-list',
      'HX-Trigger': 'chapter-list',
      'HX-Current-URL': mangaAbsoluteUrl,
      'Referer': mangaAbsoluteUrl,
    };

    for (int page = 1; page <= 50; page++) {
      final url =
          'https://$domain/wp-admin/admin-ajax.php'
          '?manga_id=$mangaId'
          '&page=$page'
          '&action=chapter_list';

      try {
        final response = await _client.get(
          Uri.parse(url),
          headers: {..._headers, ...extraHeaders},
        );

        // HTTP 520 means no more pages
        if (response.statusCode == 520) break;

        if (response.statusCode != 200) {
          throw Exception(
            'Failed to load chapters page $page: ${response.statusCode}',
          );
        }

        final doc = html_parser.parse(response.body);
        final chapterElements = doc.querySelectorAll(
          'div#chapter-list > div[data-chapter-number]',
        );

        if (chapterElements.isEmpty) break;

        for (final element in chapterElements) {
          final a = element.querySelector('a');
          if (a == null) continue;

          final href = toRelativeUrl(a.attributes['href'] ?? '');
          if (href.isEmpty) continue;

          final chapterTitle =
              element.querySelector('div.font-medium span')?.text.trim() ?? '';

          final dateStr = element.querySelector('time')?.text.trim() ?? '';
          final date = _parseDate(dateStr);

          chapters.add(Chapter(title: chapterTitle, href: href, date: date));
        }
      } catch (e) {
        // If it's a network / 520 error, stop paginating
        if (e.toString().contains('520')) break;
        rethrow;
      }
    }

    // Return in ascending order (oldest first) — Kotlin does .reversed()
    return chapters.reversed.toList();
  }

  // ── Read chapter ───────────────────────────────────────────────

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final chapterUrl = toAbsoluteUrl(href);
    final response = await _client.get(
      Uri.parse(chapterUrl),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    // ── Title
    String title = doc.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = doc.querySelector('title')?.text.trim() ?? '';
    }

    // ── Images — default selector for NatsuParser
    final panels = parseChapterImages(doc);

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    // ── Prev / Next navigation
    String prev = '';
    String next = '';

    // Try common navigation selectors
    Element? prevLink =
        doc.querySelector('a[rel="prev"]') ?? doc.querySelector('a.prev');
    if (prevLink == null) {
      for (final a in doc.querySelectorAll('a')) {
        if (a.text.toLowerCase().contains('prev')) {
          prevLink = a;
          break;
        }
      }
    }
    if (prevLink != null) {
      prev = toRelativeUrl(prevLink.attributes['href'] ?? '');
    }

    Element? nextLink =
        doc.querySelector('a[rel="next"]') ?? doc.querySelector('a.next');
    if (nextLink == null) {
      for (final a in doc.querySelectorAll('a')) {
        if (a.text.toLowerCase().contains('next')) {
          nextLink = a;
          break;
        }
      }
    }
    if (nextLink != null) {
      next = toRelativeUrl(nextLink.attributes['href'] ?? '');
    }

    return ReadChapter(title: title, prev: prev, next: next, panel: panels);
  }

  /// Parses chapter images from the document.
  /// Subclasses can override this to use different selectors.
  List<String> parseChapterImages(Document doc) {
    // Default selector: main section section > img
    final imgs = doc.querySelectorAll('main section section > img');
    final panels = <String>[];

    for (final img in imgs) {
      final src =
          img.attributes['src'] ??
          img.attributes['data-src'] ??
          img.attributes['data-lazy-src'] ??
          '';
      if (src.isNotEmpty && !src.contains('data:image')) {
        panels.add(toAbsoluteUrl(src));
      }
    }

    return panels;
  }

  // ── Date parsing ───────────────────────────────────────────────

  /// Parses relative dates ("X ago") and "MMM dd, yyyy" formats.
  String _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';

    try {
      if (dateStr.contains('ago')) {
        final match = RegExp(r'(\d+)').firstMatch(dateStr);
        final number = int.tryParse(match?.group(1) ?? '') ?? 0;
        if (number == 0) return '';

        final now = DateTime.now();
        DateTime date;

        if (dateStr.contains('min')) {
          date = now.subtract(Duration(minutes: number));
        } else if (dateStr.contains('hour')) {
          date = now.subtract(Duration(hours: number));
        } else if (dateStr.contains('day')) {
          date = now.subtract(Duration(days: number));
        } else if (dateStr.contains('week')) {
          date = now.subtract(Duration(days: number * 7));
        } else if (dateStr.contains('month')) {
          date = DateTime(now.year, now.month - number, now.day);
        } else if (dateStr.contains('year')) {
          date = DateTime(now.year - number, now.month, now.day);
        } else {
          return dateStr;
        }

        return _formatDate(date);
      }

      // Try "MMM dd, yyyy" format (e.g. "Feb 25, 2026")
      final months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };

      final match = RegExp(r'(\w+)\s+(\d+),?\s+(\d{4})').firstMatch(dateStr);
      if (match != null) {
        final monthStr = match.group(1)!.toLowerCase().substring(0, 3);
        final day = int.tryParse(match.group(2)!) ?? 1;
        final year = int.tryParse(match.group(3)!) ?? 2000;
        final month = months[monthStr] ?? 1;

        return _formatDate(DateTime(year, month, day));
      }

      // Return as-is if we can't parse
      return dateStr;
    } catch (_) {
      return dateStr;
    }
  }

  /// Formats a [DateTime] as "MMM dd, yyyy" (e.g. "Feb 25, 2026").
  String _formatDate(DateTime date) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = monthNames[date.month - 1];
    return '$month ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  // ── String helpers ─────────────────────────────────────────────

  /// Converts a string to Title Case.
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  // ── Batch helpers ──────────────────────────────────────────────

  /// Batch fetch multiple lists efficiently.
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

    await Future.wait(futures);
    return results;
  }

  // ── Lifecycle ──────────────────────────────────────────────────

  /// Clear all caches (list cache + nonce).
  void clearCache() {
    _listCache.clear();
    _nonce = null;
  }

  /// Dispose HTTP client and clear caches.
  void dispose() {
    _client.close();
    clearCache();
  }
}
