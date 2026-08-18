import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

/// Parser for Bbato (https://bbato.com) — English comic source.
///
/// Ported from the Tachiyomi extension `bbato/Bbato.kt`.
/// Source structure:
/// - Popular  : GET `/` → `#most-viewed .tab-content .swiper-slide.unit`
/// - Latest   : GET `/updated` → `.original.card-lg .unit`
/// - Detail   : GET `/manga/{slug}` → `h1[itemprop=name]`, `.meta`, `.description`
/// - Chapters : GET `/get-chapter-list?slug={slug}` → JSON
/// - Pages    : GET `/read/{slug}/{chapterSlug}` → `.pages .page img`
///
/// All images (thumbs + chapter pages) are served from a CDN that enforces a
/// referer check, so the `imageHeaders` below are mandatory or images return 403.
class BbatoParser extends ComicParser {
  static const String _baseUrl = 'https://bbato.com';

  /// Optional injected client. When null, a fresh client is created per
  /// request to avoid bbato.com's aggressive keep-alive connection closing.
  final http.Client? _client;

  /// Cache for list results (popular/recommended/search, keyed by page/query).
  final Map<String, CachedResult> _listCache = {};

  BbatoParser({http.Client? client}) : _client = client;

  @override
  String get sourceName => 'Bbato';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'EN';

  /// Bbato uses a CDN (cdn2.merrypsycho.xyz) that returns 403 for image
  /// requests without a valid `Referer`. Root referer bypasses the block.
  /// @override
  @override
  Map<String, String> get imageHeaders => const {
    'Referer': '$_baseUrl/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  // ── Cache helpers ──────────────────────────────────────────────

  bool _isCacheValid(String key) {
    final cached = _listCache[key];
    if (cached == null) return false;
    return DateTime.now().difference(cached.timestamp) < cacheExpiry;
  }

  List<ComicItem>? _getFromCache(String key) {
    if (_isCacheValid(key)) {
      return _listCache[key]?.items;
    }
    _listCache.remove(key);
    return null;
  }

  void _saveToCache(String key, List<ComicItem> items) {
    _listCache[key] = CachedResult(items: items, timestamp: DateTime.now());
  }

  // ── HTTP helpers ───────────────────────────────────────────────

  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Referer': '$_baseUrl/',
  };

  /// bbato.com aggressively closes keep-alive/pooled connections, making a
  /// shared `http.Client` throw intermittent "Connection closed" errors.
  /// Unless a client was injected for tests, use a fresh client per request
  /// so there is no stale pooled connection to trip on. bbato.com also drops
  /// connections intermittently, so transient network errors are retried.
  Future<http.Response> _fetch(
    String url, {
    Map<String, String>? headers,
  }) async {
    const maxAttempts = 4;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final client = _client ?? http.Client();
      try {
        final response = await client.get(
          Uri.parse(url),
          headers: headers ?? _headers,
        );
        if (response.statusCode != 200) {
          throw Exception('Status ${response.statusCode} loading $url');
        }
        return response;
      } catch (e) {
        lastError = e;
        // Retry only transient failures (connection dropped / socket errors).
        if (e is http.ClientException ||
            e is Exception && e.toString().contains('Connection closed')) {
          if (attempt < maxAttempts) {
            await Future<void>.delayed(
              Duration(milliseconds: 700 * attempt),
            );
            continue;
          }
        }
        rethrow;
      } finally {
        // Only close clients we created here (never an injected mock).
        if (_client == null) client.close();
      }
    }
    throw lastError is Exception
        ? lastError
        : Exception('Failed to load $url');
  }

  Future<Document> _fetchHtml(String url, {Map<String, String>? headers}) async {
    final response = await _fetch(url, headers: headers);
    return html_parser.parse(response.body);
  }

  /// Extract image URL preferring `data-src`, falling back to `src`.
  String _imageUrl(Element? el) {
    if (el == null) return '';
    var url = el.attributes['data-src'] ?? '';
    if (url.isEmpty) url = el.attributes['src'] ?? '';
    url = _toAbsoluteUrl(url.trim());
    return url;
  }

  String _toAbsoluteUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$_baseUrl$url';
  }

  /// Strip the leading domain + scheme, returning a normalized relative href.
  String _toRelativeHref(String url) {
    var href = url.trim();
    href = href.replaceAll(RegExp(r'^https?://[^/]+'), '');
    if (!href.startsWith('/')) href = '/$href';
    return href;
  }

  // ── Popular ────────────────────────────────────────────────────

  @override
  Future<List<ComicItem>> fetchPopular() async {
    const cacheKey = 'popular';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final doc = await _fetchHtml('$_baseUrl/');

    // Site splits popular into tabs (day/week/month). Merge + dedupe.
    final seen = <String>{};
    final items = <ComicItem>[];
    for (final element in doc.querySelectorAll(
      '#most-viewed .tab-content .swiper-slide.unit',
    )) {
      final a = element.querySelector('a');
      final href = _toRelativeHref(a?.attributes['href'] ?? '');
      if (href.isEmpty || href == '/') continue;
      if (seen.contains(href)) continue;
      seen.add(href);

      final title = element.querySelector('span')?.text.trim() ?? '';
      final thumb = _imageUrl(element.querySelector('img'));
      if (title.isEmpty) continue;

      items.add(
        ComicItem(
          title: title,
          href: href,
          thumbnail: thumb,
          type: 'Manga',
        ),
      );
    }

    _saveToCache(cacheKey, items);
    return items;
  }

  /// Home page section doesn't natively paginate; recommended = popular.
  @override
  Future<List<ComicItem>> fetchRecommended() => fetchPopular();

  // ── Latest ─────────────────────────────────────────────────────

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final cacheKey = 'newest-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final path = page == 1 ? '/updated' : '/updated/page/$page';
    final doc = await _fetchHtml('$_baseUrl$path');

    final items = <ComicItem>[];
    for (final element in doc.querySelectorAll('.original.card-lg .unit')) {
      final posterA = element.querySelector('a.poster');
      final href = _toRelativeHref(posterA?.attributes['href'] ?? '');
      if (href.isEmpty || href == '/') continue;

      final title = element.querySelector('.info > a')?.text.trim() ?? '';
      final thumb = _imageUrl(posterA?.querySelector('img'));
      if (title.isEmpty) continue;

      items.add(
        ComicItem(
          title: title,
          href: href,
          thumbnail: thumb,
          type: 'Manga',
        ),
      );
    }

    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) =>
      fetchNewest(page: page);

  // ── Search ─────────────────────────────────────────────────────

  @override
  Future<List<ComicItem>> search(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final cacheKey = 'search-$encoded';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final url = '$_baseUrl/filter?keyword=$encoded';
    final doc = await _fetchHtml(url);
    final items = _parseFilteredItems(doc);

    _saveToCache(cacheKey, items);
    return items;
  }

  /// Shared parsing for search & fetchFiltered (both hit /filter).
  List<ComicItem> _parseFilteredItems(Document doc) {
    final items = <ComicItem>[];
    for (final element in doc.querySelectorAll('.original.card-lg .unit')) {
      final posterA = element.querySelector('a.poster');
      final href = _toRelativeHref(posterA?.attributes['href'] ?? '');
      if (href.isEmpty || href == '/') continue;

      final title = element.querySelector('.info > a')?.text.trim() ?? '';
      final thumb = _imageUrl(posterA?.querySelector('img'));
      if (title.isEmpty) continue;

      items.add(
        ComicItem(
          title: title,
          href: href,
          thumbnail: thumb,
          type: 'Manga',
        ),
      );
    }
    return items;
  }

  // ── Genres ─────────────────────────────────────────────────────

  @override
  Future<List<Genre>> fetchGenres() async {
    const genres = <String, String>{
      'Action': 'action',
      'Adventure': 'adventure',
      'Avant Garde': 'avant-garde',
      'Boys Love': 'boys-love',
      'Comedy': 'comedy',
      'Demons': 'demons',
      'Drama': 'drama',
      'Ecchi': 'ecchi',
      'Fantasy': 'fantasy',
      'Girls Love': 'girls-love',
      'Gourmet': 'gourmet',
      'Harem': 'harem',
      'Horror': 'horror',
      'Isekai': 'isekai',
      'Iyashikei': 'iyashikei',
      'Josei': 'josei',
      'Kids': 'kids',
      'Magic': 'magic',
      'Mahou Shoujo': 'mahou-shoujo',
      'Martial Arts': 'martial-arts',
      'Mecha': 'mecha',
      'Military': 'military',
      'Music': 'music',
      'Mystery': 'mystery',
      'Parody': 'parody',
      'Psychological': 'psychological',
      'Reverse Harem': 'reverse-harem',
      'Romance': 'romance',
      'School': 'school',
      'Sci-Fi': 'sci-fi',
      'Seinen': 'seinen',
      'Shoujo': 'shoujo',
      'Shounen': 'shounen',
      'Slice of Life': 'slice-of-life',
      'Space': 'space',
      'Sports': 'sports',
      'Super Power': 'super-power',
      'Supernatural': 'supernatural',
      'Suspense': 'suspense',
      'Thriller': 'thriller',
      'Vampire': 'vampire',
    };

    return genres.entries
        .map((e) => Genre(title: e.key, href: '/${e.value}/'))
        .toList();
  }

  // ── Filtered ───────────────────────────────────────────────────

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final slug = _extractSlug(genre);
    final cacheKey = 'genre-$slug-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final url = '$_baseUrl/filter?genre[]=$slug&page=$page';
    final doc = await _fetchHtml(url);
    final items = _parseFilteredItems(doc);

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
    if (cached != null) return cached;

    final params = <String, String>{
      if (genre != null && genre.isNotEmpty) 'genre[]': _extractSlug(genre),
      if (status != null && status.isNotEmpty) 'status[]': _extractSlug(status),
      if (type != null && type.isNotEmpty) 'type[]': _extractSlug(type),
      if (order != null && order.isNotEmpty) 'sort': _mapSort(order),
      'page': page.toString(),
    };

    final uri = Uri.parse('$_baseUrl/filter').replace(
      queryParameters: params,
    );
    final doc = await _fetchHtml(uri.toString());
    final items = _parseFilteredItems(doc);

    _saveToCache(cacheKey, items);
    return items;
  }

  /// Normalize any genre/href value into a bare slug.
  String _extractSlug(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'^.*/(genre|type|status)/'), '')
        .replaceAll(RegExp(r'^/'), '')
        .replaceAll(RegExp(r'/$'), '');
  }

  /// Map a friendly sort order to Bbato's `sort` values.
  String _mapSort(String order) {
    switch (order.toLowerCase()) {
      case 'recently_updated':
      case 'latest':
      case 'update':
        return 'recently_updated';
      case 'recently_added':
      case 'newest':
        return 'recently_added';
      case 'release_date':
        return 'release_date';
      case 'title_az':
      case 'name':
        return 'title_az';
      default:
        return order;
    }
  }

  // ── Details ────────────────────────────────────────────────────

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final url = '$_baseUrl/$cleanHref';
    final doc = await _fetchHtml(url);

    final title =
        doc.querySelector('h1[itemprop="name"]')?.text.trim() ?? '';
    if (title.isEmpty) throw Exception('Missing title');

    // Description
    final description = doc.querySelector('.description')?.text.trim() ?? '';

    // Author / genres / type — iterate the .meta rows (each row is a div whose
    // first span holds a label like "Author:" or "Genres:").
    final authorParts = <String>[];
    final genres = <Genre>[];
    var type = '';
    for (final row in doc.querySelectorAll('.meta > div')) {
      final spans = row.querySelectorAll('span');
      if (spans.isEmpty) continue;
      final label = spans.first.text.trim().toLowerCase();

      if (label == 'author:') {
        for (final a in row.querySelectorAll('a')) {
          final t = a.text.trim();
          if (t.isNotEmpty) authorParts.add(t);
        }
      } else if (label.startsWith('genre')) {
        for (final a in row.querySelectorAll('a')) {
          final gTitle = a.text.trim();
          if (gTitle.isEmpty) continue;
          genres.add(
            Genre(title: gTitle, href: _toRelativeHref(a.attributes['href'] ?? '')),
          );
          if (type.isEmpty) type = gTitle;
        }
      }
    }
    final authors = authorParts.join(', ');

    // Status
    String status = '';
    final statusEl = doc.querySelector('.info > p');
    status = (statusEl?.text.trim() ?? '').toLowerCase();

    // Thumbnail
    final thumb = _imageUrl(doc.querySelector('.poster img'));

    // Chapters via JSON API
    final slug = cleanHref.split('/').last;
    final chapters = await _fetchChapters(slug);

    return ComicDetail(
      href: _toRelativeHref(cleanHref),
      title: title,
      altTitle: '',
      thumbnail: thumb,
      description: description,
      status: _statusText(status),
      type: type,
      released: '',
      author: authors,
      updatedOn: '',
      rating: '',
      latestChapter: chapters.isNotEmpty ? chapters.first.title : null,
      genres: genres,
      chapters: chapters,
    );
  }

  String _statusText(String raw) {
    switch (raw) {
      case 'ongoing':
      case 'releasing':
        return 'Ongoing';
      case 'completed':
        return 'Completed';
      case 'on hiatus':
        return 'On Hiatus';
      case 'discontinued':
      case 'cancelled':
        return 'Discontinued';
      default:
        return raw.isEmpty ? 'Unknown' : raw[0].toUpperCase() + raw.substring(1);
    }
  }

  Future<List<Chapter>> _fetchChapters(String slug) async {
    final chapterHeaders = {
      ..._headers,
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': '$_baseUrl/manga/$slug',
    };
    final response = await _fetch(
      '$_baseUrl/get-chapter-list?slug=$slug',
      headers: chapterHeaders,
    );

    final chapters = <Chapter>[];
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['data'] is List) {
      for (final item in decoded['data'] as List) {
        final entry = item as Map<String, dynamic>;
        final name = entry['chapter_name']?.toString() ?? '';
        final chapterSlug = entry['chapter_slug']?.toString() ?? '';
        final updatedAt = entry['updated_at']?.toString() ?? '';
        if (name.isEmpty || chapterSlug.isEmpty) continue;

        chapters.add(
          Chapter(
            title: name,
            href: '/read/$slug/$chapterSlug',
            date: _formatDate(updatedAt),
          ),
        );
      }
    }
    return chapters;
  }

  /// Convert "yyyy-MM-dd HH:mm:ss" into a friendlier display date.
  String _formatDate(String raw) {
    try {
      final p = raw.trim().split(RegExp(r'[- :]'));
      if (p.length < 3) return raw;
      final year = int.parse(p[0]);
      final month = int.parse(p[1]);
      final day = int.parse(p[2]);
      return '$day-${month.toString().padLeft(2, '0')}-$year';
    } catch (_) {
      return raw;
    }
  }

  // ── Chapter reading ────────────────────────────────────────────

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final url = '$_baseUrl/$cleanHref';
    final doc = await _fetchHtml(url);

    // Title: prefer the h1 if present, else derive from last slug segment.
    String title = doc.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) {
      final seg = cleanHref.split('/').last;
      title = seg
          .split('-')
          .map((w) => w.isEmpty
              ? w
              : w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }

    // Pages: `.pages .page:not(.notice-page) img` with data-src fallback src.
    final panels = <String>[];
    final seen = <String>{};
    for (final page in doc.querySelectorAll('.pages .page')) {
      if (page.classes.contains('notice-page')) continue;
      final img = page.querySelector('img');
      if (img == null) continue;
      final src = _imageUrl(img);
      if (src.isNotEmpty && !seen.contains(src)) {
        seen.add(src);
        panels.add(src);
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    return ReadChapter(title: title, prev: '', next: '', panel: panels);
  }

  // ── Cleanup ────────────────────────────────────────────────────

  void clearCache() {
    _listCache.clear();
  }

  void clearListCache() {
    _listCache.clear();
  }

  void dispose() {
    // If an external client was injected, close it.
    _client?.close();
    clearCache();
  }
}
