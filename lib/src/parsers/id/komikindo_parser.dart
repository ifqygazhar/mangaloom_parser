import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

/// Parser for Komikindo (https://komikindo.fit) — Indonesian comic source.
///
/// Ported from the Tachiyomi extension `komikindo/Komikindo.kt`, which uses
/// the shared **MangaThemesia** theme. This implementation adapts the
/// MangaThemesia selectors to the `ComicParser` contract.
class KomikindoParser extends ComicParser {
  static const String _baseUrl = 'https://komikindo.fit';

  static const String _mangaDirectory = '/manga';

  final http.Client _client;

  /// Cache for list results.
  final Map<String, CachedResult> _listCache = {};

  KomikindoParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'Komikindo';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'ID';

  /// Images are hosted on a CDN (linksaya.com) behind a referer check.
  @override
  Map<String, String> get imageHeaders => const {
    'Referer': '$_baseUrl/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  // ── Cache ──────────────────────────────────────────────────────

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

  // ── HTTP ───────────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Referer': '$_baseUrl/',
  };

  Future<Document> _fetchHtml(String url) async {
    return html_parser.parse(await _fetchRaw(url));
  }

  Future<String> _fetchRaw(String url) async {
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

  String _toRelative(String url) {
    var href = url.trim();
    href = href.replaceAll(RegExp(r'^https?://[^/]+'), '');
    if (!href.startsWith('/')) href = '/$href';
    return href;
  }

  /// img attribute: prefer data-lazy-src / data-src / src (MangaThemesia imgAttr).
  String _imgAttr(Element el) {
    for (final attr in ['data-lazy-src', 'data-src', 'data-cfsrc', 'src']) {
      final v = el.attributes[attr] ?? '';
      if (v.isNotEmpty) {
        return _toAbsolute(v);
      }
    }
    return '';
  }

  /// Element's own text without descendants.
  String _ownText(Element el) => el.text.trim();

  String _toAbsolute(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('data:')) return url;
    return '$_baseUrl$url';
  }

  // ── List parsing ───────────────────────────────────────────────

  /// MangaThemesia search list item selector.
  List<ComicItem> _parseList(Document doc) {
    final items = <ComicItem>[];
    for (final bsx in doc.querySelectorAll('.listupd .bs .bsx')) {
      final a = bsx.querySelector('a');
      if (a == null) continue;
      final href = _toRelative(a.attributes['href'] ?? '');
      if (href.isEmpty || href == _mangaDirectory) continue;

      // Title: prefer a title attribute, else the .tt text.
      String title = a.attributes['title'] ?? '';
      if (title.isEmpty) title = bsx.querySelector('.tt')?.text.trim() ?? '';
      title = title.trim();

      final thumb = _imgAttr(bsx.querySelector('.limit img') ?? bsx);

      // Type from `span.typename` class (e.g. "Manhwa").
      String type = '';
      final typeEl = bsx.querySelector('span.typename');
      if (typeEl != null) {
        for (final cls in typeEl.classes) {
          if (cls != 'typename') {
            type = _capitalize(cls);
            break;
          }
        }
      }

      // Latest chapter from `.epxs`.
      String chapter = bsx.querySelector('.epxs')?.text.trim() ?? '';

      // Rating from `.rt` / `i.score`. The adds .rating uses a bar; grab `.rt i`.
      String rating = '';
      final rtText =
          bsx.querySelector('div.adds .rating i, .rating i, .rt i')?.text.trim() ?? '';
      final m = RegExp(r'[\d.]+').firstMatch(rtText);
      if (m != null) rating = m.group(0) ?? '';

      if (title.isNotEmpty && href.startsWith(_mangaDirectory)) {
        items.add(
          ComicItem(
            title: title,
            href: href,
            thumbnail: thumb,
            type: type.isEmpty ? null : type,
            chapter: chapter.isEmpty ? null : chapter,
            rating: rating.isEmpty ? null : rating,
          ),
        );
      }
    }
    return items;
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  // ── List fetchers ──────────────────────────────────────────────

  /// Build a search-style request with the given order & filters.
  Future<List<ComicItem>> _fetchSearch({
    required String query,
    required String order,
    required int page,
  }) async {
    final cacheKey = 'ki-$order-$query-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final qp = <String, String>{'title': query, 'page': page.toString()};
    if (order.isNotEmpty && query.isEmpty) qp['order'] = order;

    final uri = Uri.parse('$_baseUrl$_mangaDirectory').replace(
      queryParameters: qp,
    );
    final doc = await _fetchHtml(uri.toString());
    final items = _parseList(doc);

    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchPopular({int page = 1}) =>
      _fetchSearch(query: '', order: 'popular', page: page);

  @override
  Future<List<ComicItem>> fetchRecommended() =>
      _fetchSearch(query: '', order: 'popular', page: 1);

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) =>
      _fetchSearch(query: '', order: 'update', page: page);

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) =>
      _fetchSearch(query: '', order: 'update', page: page);

  @override
  Future<List<ComicItem>> search(String query) async {
    final cacheKey = 'ki-search-$query';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final doc = await _fetchHtml(
      Uri.parse('$_baseUrl$_mangaDirectory').replace(
        queryParameters: {'title': query},
      ).toString(),
    );
    final items = _parseList(doc);
    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final slug = _extractSlug(genre);
    final cacheKey = 'ki-genre-$slug-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

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
    final cacheKey = 'ki-filtered-$page-$genre-$status-$type-$order';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final qp = <String, String>{
      'page': page.toString(),
      if (genre != null && genre.isNotEmpty)
        'genre[]': _extractSlug(genre),
      if (status != null && status.isNotEmpty) 'status': status,
      if (type != null && type.isNotEmpty) 'type': _capitalize(type),
      if (order != null && order.isNotEmpty) 'order': order,
    };
    final doc = await _fetchHtml(
      Uri.parse('$_baseUrl$_mangaDirectory').replace(queryParameters: qp).toString(),
    );
    final items = _parseList(doc);
    _saveToCache(cacheKey, items);
    return items;
  }

  String _extractSlug(String value) => value
      .trim()
      .replaceAll(RegExp(r'^.*/genres?/'), '')
      .replaceAll(RegExp(r'^/'), '')
      .replaceAll(RegExp(r'/$'), '');

  String _pagePath(int page) => page > 1 ? 'page/$page/' : '';

  @override
  Future<List<Genre>> fetchGenres() async {
    // Parse genres from a /manga/ page (`ul.genrez`), fall back to a curated set.
    try {
      final doc = await _fetchHtml('$_baseUrl$_mangaDirectory');
      final parsed = <Genre>[];
      final seen = <String>{};
      for (final li in doc.querySelectorAll('ul.genrez li')) {
        final label = li.querySelector('label')?.text.trim() ?? '';
        final input = li.querySelector('input[type=checkbox]');
        final value = input?.attributes['value'] ?? '';
        if (label.isEmpty || value.isEmpty) continue;
        if (seen.contains(value)) continue;
        seen.add(value);
        parsed.add(Genre(title: label, href: '/genres/$value/'));
      }
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {
      // fall through to curated list
    }

    const curated = <String>{
      'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Harem', 'Horror',
      'Isekai', 'Manga', 'Manhwa', 'Manhua', 'Martial Arts', 'Mature',
      'Mystery', 'Romance', 'School Life', 'Sci-fi', 'Seinen', 'Shounen',
      'Slice of Life', 'Sports', 'Supernatural', 'Tragedy',
    };
    return curated.map((g) => Genre(title: g, href: '/genres/${_slugify(g)}/')).toList();
  }

  String _slugify(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  // ── Details ────────────────────────────────────────────────────

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final url = '$_baseUrl/$cleanHref';
    final doc = await _fetchHtml(url);

    // MangaThemesia selects inside the big info container.
    Element? detailsSel;
    for (final sel in [
      'div.bigcontent',
      'div.animefull',
      'div.main-info',
      'div.postbody',
      'div.seriestucon',
    ]) {
      detailsSel = doc.querySelector(sel);
      if (detailsSel != null) break;
    }
    Element details = (detailsSel ?? doc) as Element;

    final title = doc.querySelector('h1.entry-title')?.text.trim() ?? '';
    if (title.isEmpty) throw Exception('Missing title');

    // Alt title.
    String altTitle = '';
    final altEl = details.querySelector('.alternative, .seriestualt');
    if (altEl != null) altTitle = _ownText(altEl);

    // Thumbnail.
    final thumbSel = details.querySelector(
      '.infomanga > div[itemprop=image] img, .thumb img',
    );
    final thumb = thumbSel != null
        ? _imgAttr(thumbSel)
        : _imgAttr(details);

    // Description.
    final descEl = details.querySelector(
      '.desc, .entry-content[itemprop=description], .seriestucontentr > div',
    );
    final description = (descEl?.text ?? '').trim();

    // Meta from `.infotable` rows (Status / Type / Released / Author / Artist).
    String status = '';
    String type = '';
    String released = '';
    String author = '';
    for (final row in details.querySelectorAll('table.infotable tr')) {
      final tds = row.querySelectorAll('td');
      if (tds.length < 2) continue;
      final key = tds[0].text.trim().toLowerCase();
      final val = tds[1].text.trim();
      switch (key) {
        case 'status':
          status = _statusText(val);
          break;
        case 'type':
          type = val;
          break;
        case 'released':
          released = val;
          break;
        case 'author':
          author = val;
          break;
      }
    }

    // Genres from `.seriestugenre a`.
    final genres = <Genre>[];
    for (final a in details.querySelectorAll('.seriestugenre a, .genres a, .gnr a')) {
      final gTitle = a.text.trim();
      if (gTitle.isEmpty) continue;
      genres.add(Genre(title: gTitle, href: _toRelative(a.attributes['href'] ?? '')));
    }
    if (type.isNotEmpty && genres.every((g) => g.title != type)) {
      genres.add(Genre(title: type, href: ''));
    }

    // Chapters: `#chapterlist .clstyle li`.
    final chapters = <Chapter>[];
    for (final li in doc.querySelectorAll('#chapterlist .clstyle > li, #chapterlist li')) {
      final a = li.querySelector('a');
      if (a == null) continue;
      final chHref = _toRelative(a.attributes['href'] ?? '');
      if (chHref.isEmpty) continue;

      final chTitle =
          li.querySelector('.chapternum')?.text.trim() ?? a.text.trim();
      final date = li.querySelector('.chapterdate')?.text.trim() ?? '';
      chapters.add(Chapter(title: chTitle, href: chHref, date: date));
    }

    return ComicDetail(
      href: _toRelative(cleanHref),
      title: title,
      altTitle: altTitle,
      thumbnail: thumb,
      description: description,
      status: status,
      type: type,
      released: released,
      author: author,
      updatedOn: '',
      rating: '',
      latestChapter: chapters.isNotEmpty ? chapters.first.title : null,
      genres: genres,
      chapters: chapters,
    );
  }

  String _statusText(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('ongoing') || lower.contains('berjalan')) return 'Ongoing';
    if (lower.contains('tamat') || lower.contains('completed')) return 'Completed';
    if (lower.contains('hiatus')) return 'Hiatus';
    if (lower.contains('dropped') || lower.contains('batal')) return 'Dropped';
    return raw.isEmpty ? 'Unknown' : raw;
  }

  // ── Chapter reading ────────────────────────────────────────────

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final url = '$_baseUrl/$cleanHref';
    final rawBody = await _fetchRaw(url);
    final doc = html_parser.parse(rawBody);

    String title = doc.querySelector('h1.entry-title')?.text.replaceAll(' ', ' ').trim() ?? '';
    if (title.isEmpty) {
      title = doc.querySelector('title')?.text.trim() ?? '';
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

    // Pages: `#readerarea img`. The html package skips <noscript> content,
    // so also regex the reader area's raw HTML (chapter images often live in
    // <noscript> alongside the JS loader).
    final panels = <String>[];
    final seen = <String>{};
    final reader = doc.querySelector('#readerarea') ?? doc;
    for (final img in reader.querySelectorAll('img')) {
      final src = _imgAttr(img);
      if (src.isNotEmpty && !src.startsWith('data:') && !seen.contains(src)) {
        seen.add(src);
        panels.add(src);
      }
    }

    // Regex over the reader area raw HTML (captures <noscript> pages and
    // JS-injected URLs) so chapter images are found even when the html package
    // drops <noscript> from the DOM.
    if (panels.isEmpty) {
      final srcs = RegExp(
        r'https?://[^"\s>]+?\.(?:jpg|jpeg|png|webp)(?:[^"\s>]*)?',
        caseSensitive: false,
      ).allMatches(rawBody).map((m) => m.group(0)!).toList();
      for (final src in srcs) {
        if (src.startsWith('data:') || seen.contains(src)) continue;
        // Skip obvious non-chapter assets (favicons, logos).
        final lower = src.toLowerCase();
        if (lower.contains('favicon') || (lower.contains('/wp-content/uploads/1') && lower.contains('cropped-'))) {
          continue;
        }
        seen.add(src);
        panels.add(src);
      }
    }

    if (panels.isEmpty) {
      // Fallback: JS-loaded image list (`"images":[...]` inside a script).
      final m = RegExp(r'"images"\s*:\s*(\[.*?])').firstMatch(doc.toString());
      if (m != null) {
        try {
          final list = jsonDecode(m.group(1)!) as List;
          for (final url in list) {
            final src = _toAbsolute(url.toString());
            if (src.isNotEmpty && !seen.contains(src)) {
              seen.add(src);
              panels.add(src);
            }
          }
        } catch (_) {}
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
    _client.close();
    clearCache();
  }
}