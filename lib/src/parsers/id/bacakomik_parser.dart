import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

/// Parser for BacaKomik (https://bacakomik.my) — Indonesian comic source.
///
/// Ported from the Tachiyomi extension `bacakomik/BacaKomik.kt`.
class BacaKomikParser extends ComicParser {
  static const String _baseUrl = 'https://bacakomik.my';

  final http.Client _client;

  /// Cache for list results.
  final Map<String, CachedResult> _listCache = {};

  BacaKomikParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'BacaKomik';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'ID';

  /// Chapter images are hosted on a CDN (imageainewgeneration.lol) that
  /// requires a `Referer`. Root referer keeps image loads working.
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

  Future<String> _fetchRaw(String url) async {
    // bacakomik.my intermittently drops connections; retry transient errors.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _client.get(Uri.parse(url), headers: _headers);
        if (response.statusCode != 200) {
          throw Exception('Failed to load page: ${response.statusCode}');
        }
        return response.body;
      } catch (e) {
        if (e is http.ClientException && attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Failed to load $url');
  }

  Future<Document> _fetchHtml(String url) async {
    return html_parser.parse(await _fetchRaw(url));
  }

  /// Normalize an href to a relative path (without scheme+host).
  String _toRelative(String url) {
    var href = url.trim();
    href = href.replaceAll(RegExp(r'^https?://[^/]+'), '');
    if (!href.startsWith('/')) href = '/$href';
    return href;
  }

  /// Extract image url preferring `data-lazy-src`, then `data-src`, then `src`.
  String _imgAttr(Element el) {
    if (el.attributes['data-lazy-src']?.isNotEmpty == true) {
      return _toAbsolute(el.attributes['data-lazy-src']!);
    }
    if (el.attributes['data-src']?.isNotEmpty == true) {
      return _toAbsolute(el.attributes['data-src']!);
    }
    return _toAbsolute(el.attributes['src'] ?? '');
  }

  String _toAbsolute(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('data:')) return url;
    return '$_baseUrl$url';
  }

  String _pagePath(int page) => page > 1 ? 'page/$page/' : '';

  // ── List parsing ───────────────────────────────────────────────

  List<ComicItem> _parseList(Document doc) {
    final items = <ComicItem>[];
    for (final el in doc.querySelectorAll('div.animepost')) {
      final a = el.querySelector('div.animposx > a');
      final href = _toRelative(a?.attributes['href'] ?? '');
      if (href.isEmpty || href == '/') continue;

      final title = el.querySelector('.tt h4')?.text.trim() ?? '';
      final thumb = _imgAttr(el.querySelector('div.limit img') ?? el);

      // Type from `typeflag` class (e.g. "Manhwa", "Manhua").
      String type = '';
      final flagEl = el.querySelector('span.typeflag');
      if (flagEl != null) {
        for (final cls in flagEl.classes) {
          if (cls != 'typeflag') {
            type = _capitalize(cls);
            break;
          }
        }
      }

      // Rating from `.adds .rating i`.
      String rating = '';
      final ratingEl = el.querySelector('.adds .rating i');
      final ratingText = ratingEl?.text.trim() ?? '';
      final m = RegExp(r'[\d.]+').firstMatch(ratingText);
      if (m != null) rating = m.group(0) ?? '';

      if (title.isNotEmpty) {
        items.add(
          ComicItem(
            title: title,
            href: href,
            thumbnail: thumb,
            type: type.isEmpty ? null : type,
            rating: rating.isEmpty ? null : rating,
          ),
        );
      }
    }
    return items;
  }

  // ── Popular / Newest / All ─────────────────────────────────────

  Future<List<ComicItem>> _fetchList({required String order, required int page}) async {
    final cacheKey = 'bk-$order-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final url = '$_baseUrl/daftar-komik/${_pagePath(page)}?order=$order';
    final doc = await _fetchHtml(url);
    final items = _parseList(doc);

    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchPopular({int page = 1}) =>
      _fetchList(order: 'popular', page: page);

  @override
  Future<List<ComicItem>> fetchRecommended() =>
      _fetchList(order: 'popular', page: 1);

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) =>
      _fetchList(order: 'update', page: page);

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) =>
      _fetchList(order: 'update', page: page);

  // ── Search ─────────────────────────────────────────────────────

  @override
  Future<List<ComicItem>> search(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final cacheKey = 'bk-search-$encoded';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final url = '$_baseUrl/daftar-komik/?title=$encoded';
    final doc = await _fetchHtml(url);
    final items = _parseList(doc);

    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final slug = _extractSlug(genre);
    final cacheKey = 'bk-genre-$slug-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // https://bacakomik.my/genres/{slug}/page/{page}/
    final url = '$_baseUrl/genres/$slug/${_pagePath(page)}';
    final doc = await _fetchHtml(url);
    final items = _parseList(doc);

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
    final cacheKey = 'bk-filtered-$page-$genre-$status-$type-$order';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final params = <String, String>{
      if (genre != null && genre.isNotEmpty) 'genre[]': _extractSlug(genre),
      if (status != null && status.isNotEmpty) 'status': _mapStatus(status),
      if (type != null && type.isNotEmpty) 'type': _capitalize(type),
      if (order != null && order.isNotEmpty) 'order': order,
    };

    final uri = Uri.parse(
      '$_baseUrl/daftar-komik/${_pagePath(page)}',
    ).replace(queryParameters: params);
    final doc = await _fetchHtml(uri.toString());
    final items = _parseList(doc);

    _saveToCache(cacheKey, items);
    return items;
  }

  String _extractSlug(String value) => value
      .trim()
      .replaceAll(RegExp(r'^.*/(genre|type|status)/'), '')
      .replaceAll(RegExp(r'^/'), '')
      .replaceAll(RegExp(r'/$'), '');

  String _mapStatus(String status) {
    switch (status.toLowerCase()) {
      case 'ongoing':
        return 'ongoing';
      case 'completed':
        return 'completed';
      default:
        return status;
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  // ── Genres ─────────────────────────────────────────────────────

  @override
  Future<List<Genre>> fetchGenres() async {
    // BacaKomik genre archive is uncovered here; fall back to a curated list
    // derived from the site (genres are shown as /genre/{slug}/ pages).
    const genres = <String, String>{
      'Action': 'action',
      'Adventure': 'adventure',
      'Comedy': 'comedy',
      'Drama': 'drama',
      'Fantasy': 'fantasy',
      'Harem': 'harem',
      'Horror': 'horror',
      'Isekai': 'isekai',
      'Manga': 'manga',
      'Manhwa': 'manhwa',
      'Manhua': 'manhua',
      'Mystery': 'mystery',
      'Romance': 'romance',
      'School Life': 'school-life',
      'Sci-fi': 'sci-fi',
      'Seinen': 'seinen',
      'Slice of Life': 'slice-of-life',
      'Shounen': 'shounen',
      'Tragedy': 'tragedy',
      'War': 'war',
    };
    return genres.entries
        .map((e) => Genre(title: e.key, href: '/${e.value}/'))
        .toList();
  }

  // ── Details ────────────────────────────────────────────────────

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final url = '$_baseUrl/$cleanHref';
    final rawBody = await _fetchRaw(url);
    final doc = html_parser.parse(rawBody);

    // Title from JSON-LD breadcrumb (last non-generic "name"), e.g.
    // {"@type":"ListItem","position":3,"name":"Solo Leveling"}.
    // Parsed from the raw body because the html package re-serializes
    // `<script>` JSON-LD such that the regex no longer matches.
    String title = _extractTitleFromJsonLd(rawBody);
    if (title.isEmpty) {
      title =
          doc.querySelector('h1.entry-title')?.text.trim() ?? '';
    }
    if (title.isEmpty) throw Exception('Missing title');

    // Description: `div.desc > .entry-content.entry-content-single p`,
    // text after "bercerita tentang ".
    String description = '';
    final descP = doc.querySelector(
      'div.desc > .entry-content.entry-content-single p',
    );
    if (descP != null) {
      final raw = descP.text.trim();
      final idx = raw.indexOf('bercerita tentang ');
      description = idx >= 0
          ? raw.substring(idx + 'bercerita tentang '.length).trim()
          : raw;
    }

    // Author / status / type from the `.spe` rows. Each row is a `<span>`
    // whose `<b>` holds the label (Status:, Jenis Komik:, Author:, ...).
    String author = '';
    String status = '';
    String type = '';
    final genres = <Genre>[];

    for (final span in doc.querySelectorAll('.infox .spe span')) {
      final label = span.querySelector('b')?.text.trim().toLowerCase() ?? '';
      if (label.startsWith('author') || label.startsWith('pengarang')) {
        final parts = span
            .querySelectorAll('a')
            .map((a) => a.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        author = parts.join(', ');
      } else if (label.startsWith('status')) {
        final b = span.querySelector('b');
        final raw = b == null ? span.text : span.text.replaceFirst(b.text, '');
        status = _parseStatusText(raw.trim());
      } else if (label.contains('jenis komik') || label.contains('tipe')) {
        final a = span.querySelector('a');
        if (a != null) type = a.text.trim();
      }
    }

    // Genres via `.genre-info a` (title attribute holds clean genre name).
    for (final a in doc.querySelectorAll('.infox > .genre-info > a')) {
      final gTitle = (a.attributes['title'] ?? a.text).trim();
      if (gTitle.isEmpty) continue;
      genres.add(Genre(title: gTitle, href: _toRelative(a.attributes['href'] ?? '')));
    }

    // Thumbnail.
    String thumb = '';
    final thumbImg = doc.querySelector('.thumb > img:nth-child(1)');
    if (thumbImg != null) thumb = _imgAttr(thumbImg);

    // Chapters: `#chapter_list li`, title from .lchx a, date from .dt a.
    final chapters = <Chapter>[];
    for (final li in doc.querySelectorAll('#chapter_list li')) {
      final a = li.querySelector('.lchx a');
      if (a == null) continue;
      final chTitle = a.text.trim();
      final chHref = _toRelative(a.attributes['href'] ?? '');
      if (chTitle.isEmpty || chHref.isEmpty) continue;

      final date = li.querySelector('.dt a')?.text.trim() ?? '';
      chapters.add(Chapter(title: chTitle, href: chHref, date: date));
    }

    if (type.isNotEmpty && genres.every((g) => g.title != type)) {
      genres.add(Genre(title: type, href: ''));
    }

    return ComicDetail(
      href: _toRelative(cleanHref),
      title: title,
      altTitle: '',
      thumbnail: thumb,
      description: description,
      status: status,
      type: type,
      released: '',
      author: author,
      updatedOn: '',
      rating: '',
      latestChapter: chapters.isNotEmpty ? chapters.first.title : null,
      genres: genres,
      chapters: chapters,
    );
  }

  String _parseStatusText(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('tamat') || lower.contains('completed')) {
      return 'Completed';
    }
    if (lower.contains('berjalan') || lower.contains('ongoing') || lower.contains('releasing')) {
      return 'Ongoing';
    }
    if (lower.contains('hiatus')) return 'Hiatus';
    if (lower.contains('dropped') || lower.contains('batal')) return 'Dropped';
    return raw.isEmpty ? 'Unknown' : raw;
  }

  /// Extract the manga title from the JSON-LD breadcrumb's itemListElement.
  String _extractTitleFromJsonLd(String html) {
    // Regex-scope to the itemListElement array so we only capture breadcrumb
    // names (Beranda, Manga, <Title>) in order — not unrelated JSON-LD names.
    final m = RegExp(r'"itemListElement":\[.{0,2000}?\]\}').firstMatch(html);
    if (m == null) return '';

    final names = RegExp(r'"name"\s*:\s*"([^"]+)"')
        .allMatches(m.group(0)!)
        .map((e) => e.group(1)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '';

    const skip = {'Beranda', 'Home', 'Manga', 'Manhwa', 'Manhua', 'Komik'};
    // Return the last name that isn't a breadcrumb label.
    for (var i = names.length - 1; i >= 0; i--) {
      if (!skip.contains(names[i])) return names[i];
    }
    return names.last;
  }

  // ── Chapter reading ────────────────────────────────────────────

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final url = '$_baseUrl/$cleanHref';
    final doc = await _fetchHtml(url);

    // Title from the `<title>` tag (clean), else the chapter heading.
    String title = '';
    final titleTag = doc.querySelector('title')?.text.trim() ?? '';
    if (titleTag.isNotEmpty) {
      // e.g. "Komik Solo Leveling Chapter 179 End - BacaKomik"
      title = titleTag
          .replaceFirst(RegExp(r'\s*-\s*BacaKomik\s*$'), '')
          .replaceFirst(RegExp(r'^(Komik|Manhwa|Manhua|Manga)\s+', caseSensitive: false), '')
          .trim();
    }
    if (title.isEmpty) {
      title = doc.querySelector('h1.entry-title')?.text.replaceAll('\n', ' ').trim() ?? '';
    }
    if (title.isEmpty) {
      title = doc.querySelector('h1')?.text.replaceAll('\n', ' ').trim() ?? '';
    }
    if (title.isEmpty) {
      final seg = cleanHref.split('/').last;
      title = seg
          .split('-')
          .map((w) => w.isEmpty
              ? w
              : w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }

    // Reader images: filter images whose alt contains "Chapter", then prefer
    // the URL inside `onError="...this.src='URL';"` (Kotlin reference).
    // Fall back to data-lazy-src / src.
    final panels = <String>[];
    final seen = <String>{};
    for (final img in doc.querySelectorAll('img')) {
      final alt = img.attributes['alt'] ?? '';
      if (!alt.toLowerCase().contains('chapter')) {
        if (img.parent?.localName == 'noscript') continue;
        continue;
      }

      var src = _urlFromOnError(img.attributes['onError'] ?? '');
      if (src.isEmpty) src = _imgAttr(img);
      src = _toAbsolute(src);
      if (src.isNotEmpty && !seen.contains(src) && !src.startsWith('data:')) {
        seen.add(src);
        panels.add(src);
      }
    }

    if (panels.isEmpty) {
      // Fallback: all images in the reader area (alt may differ).
      for (final img in doc.querySelectorAll(
        'div:has(> img[alt*="Chapter"]) img',
      )) {
        final src = _toAbsolute(_imgAttr(img));
        if (src.isNotEmpty && !seen.contains(src) && !src.startsWith('data:')) {
          seen.add(src);
          panels.add(src);
        }
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    return ReadChapter(title: title, prev: '', next: '', panel: panels);
  }

  String _urlFromOnError(String onError) {
    final m = RegExp(r"src='([^']+)'").firstMatch(onError);
    return m?.group(1) ?? '';
  }

  // ── Cleanup ────────────────────────────────────────────────────

  void clearCache() {
    _listCache.clear();
  }

  void clearListCache() {
    _listCache.clear();
  }

  void dispose() {
    _client.close();
    clearCache();
  }
}