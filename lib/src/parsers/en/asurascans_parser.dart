import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

/// Parser for AsuraScans (https://asurascans.com) — English comic source.
///
/// Ported from the Tachiyomi extension `asurascans/AsuraScans.kt`.
/// Uses the JSON API for lists and Astro-serialized props in the page HTML for
/// details & chapter pages. Some chapters store scrambled image tiles in the
/// image URL fragment (a JSON `PageData`); these are re-arranged using
/// `package:image` (decode → copyCrop → compositeImage → encode).
class AsuraScansParser extends ComicParser {
  static const String _baseUrl = 'https://asurascans.com';
  static const String _apiUrl = 'https://api.asurascans.com/api';
  static const int _pageLimit = 20;

  final http.Client _client;
  final Map<String, CachedResult> _listCache = {};

  AsuraScansParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'AsuraScans';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'EN';

  /// Images are served from cdn.asurascans.com behind a referer check.
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
    if (_isCacheValid(key)) return _listCache[key]?.items;
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

  Future<http.Response> _get(String url, {Map<String, String>? headers}) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: headers ?? _headers,
    );
    return response;
  }

  Future<List<dynamic>> _getList(String url) async {
    final res = await _get(url);
    if (res.statusCode != 200) {
      throw Exception('Failed to load: ${res.statusCode}');
    }
    // Force UTF-8 decoding: the API body is UTF-8 but may be mis-declared,
    // which otherwise turns apostrophes/quotes into mojibake.
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map && decoded['data'] is List) {
      return decoded['data'] as List;
    }
    return [];
  }

  String _toRelative(String url) {
    var href = url.trim();
    href = href.replaceAll(RegExp(r'^https?://[^/]+'), '');
    if (!href.startsWith('/')) href = '/$href';
    return href;
  }

  String _trimSlug(String url) {
    // series slug may carry a random suffix: "foo-bar-b60d532c" -> "foo-bar"
    return url.replaceAll(RegExp(r'-[a-z0-9]{8}$'), '');
  }

  // ── List fetch ─────────────────────────────────────────────────

  Future<List<ComicItem>> _fetchList({
    required String sort,
    required int page,
    String? query,
  }) async {
    final cacheKey = 'as-' + (query ?? sort) + '-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final qp = <String, String>{
      'offset': ((page - 1) * _pageLimit).toString(),
      'limit': _pageLimit.toString(),
      if (query != null && query.isNotEmpty) 'search': query,
      if (query == null) 'sort': sort,
    };
    final uri = Uri.parse('$_apiUrl/series').replace(queryParameters: qp);
    final data = await _getList(uri.toString());

    final items = <ComicItem>[];
    for (final raw in data) {
      final m = raw as Map<String, dynamic>;
      final title = (m['title'] ?? '').toString();
      if (title.isEmpty) continue;

      // Use the public_url (with random suffix) as the href — the bare
      // /series/{slug} path 404s on the live site.
      final publicUrl = (m['public_url'] ?? '').toString();
      final href = publicUrl.isNotEmpty
          ? _toRelative(publicUrl)
          : '/series/${m['slug']}';

      items.add(
        ComicItem(
          title: title,
          href: href,
          thumbnail: _cleanCover(m['cover'] ?? m['cover_url'] ?? ''),
          type: _capitalize(m['type']?.toString() ?? ''),
          chapter: _cleanNumber(m['chapter_count']),
          rating: _cleanRating(m['rating']),
        ),
      );
    }

    _saveToCache(cacheKey, items);
    return items;
  }

  String _cleanCover(Object? c) {
    final s = c?.toString() ?? '';
    return s.split('?').first;
  }

  String _cleanNumber(Object? n) {
    final s = n?.toString() ?? '';
    return s.isEmpty ? '' : 'Chapter $s';
  }

  String _cleanRating(Object? r) {
    final s = r?.toString() ?? '';
    if (s.isEmpty) return '';
    final v = double.tryParse(s);
    return v == null ? '' : v.toStringAsFixed(1);
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Future<List<ComicItem>> fetchPopular({int page = 1}) =>
      _fetchList(sort: 'popular', page: page);

  @override
  Future<List<ComicItem>> fetchRecommended() =>
      _fetchList(sort: 'popular', page: 1);

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) =>
      _fetchList(sort: 'latest', page: page);

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) =>
      _fetchList(sort: 'latest', page: page);

  @override
  Future<List<ComicItem>> search(String query) async {
    final cacheKey = 'as-search-$query';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;
    final items = await _fetchList(sort: 'latest', page: 1, query: query);
    _saveToCache(cacheKey, items);
    return items;
  }

  // ── Astro props decode ─────────────────────────────────────────

  /// Decode HTML-encoded Astro-island `props` attribute JSON.
  Object? _decodeAstroProps(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  /// Unwrap Astro's serialized value format.
  /// `[0, value]` → value; `[1, [...]]` → array; objects recurse; string refs
  /// (`S0`, `S1`) resolve from [refs].
  Object? _unwrap(Object? val, List<String> refs) {
    if (val is List) {
      if (val.isEmpty) return null;
      if (val.length == 1) return null;
      if (val.length == 2 && val[0] is num) {
        // [0, value] -> value
        if (val[0] == 0) {
          return _unwrap(val[1], refs);
        }
        // [1, ...] -> array of wrapped items
        final inner = val[1];
        if (inner is List) {
          return inner.map((e) => _unwrap(e, refs)).toList();
        }
        return _unwrap(inner, refs);
      }
      // Generic array
      return val.map((e) => _unwrap(e, refs)).toList();
    }
    if (val is Map) {
      final out = <String, Object?>{};
      val.forEach((k, v) => out[k.toString()] = _unwrap(v, refs));
      return out;
    }
    if (val is String && val.startsWith('S') && val.length > 1) {
      final idx = int.tryParse(val.substring(1));
      if (idx != null && idx < refs.length) return refs[idx];
    }
    return val;
  }

  /// Extract a decoded object from the first island whose props contain all
  /// [keys]. Returns the unwrapped props map.
  Map<String, Object?>? _extractProps(
    Document root,
    List<String> keys,
  ) {
    for (final island in root.querySelectorAll('astro-island')) {
      final propsRaw = island.attributes['props'] ?? '';
      if (propsRaw.isEmpty) continue;
      final decoded = _decodeAstroProps(_htmlDecode(propsRaw));
      if (decoded is! Map) continue;
      if (keys.every((k) => decoded.containsKey(k))) {
        final refs = _collectRefs(root);
        final unwrapped = _unwrap(decoded, refs);
        return unwrapped is Map ? unwrapped.cast<String, Object?>() : null;
      }
    }
    return null;
  }

  /// Collect Astro string references (`S0`, `S1`, ...) from the island's
  /// sibling script payload.
  List<String> _collectRefs(Document root) {
    final refs = <String>[];
    for (final script in root.querySelectorAll('script[data-astro-component]')) {
      final raw = script.text;
      final m = RegExp(r'"S\d+"\s*:\s*"([^"]+)"')
          .allMatches(raw)
          .toList();
      for (final x in m) refs.add(x.group(1) ?? '');
    }
    return refs;
  }

  String _htmlDecode(String s) {
    final el = html_parser.parseFragment(s);
    return el.text ?? '';
  }

  // ── Details ────────────────────────────────────────────────────

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    // The /comics/ path works with or without the random suffix (redirects).
    // Strip the suffix for a stable URL.
    var requestPath = cleanHref;
    if (requestPath.startsWith('comics/')) {
      final segs = requestPath.split('/');
      if (segs.length >= 2) segs[1] = _trimSlug(segs[1]);
      requestPath = segs.join('/');
    } else {
      requestPath = cleanHref.replaceFirst(RegExp(r'^series/'), 'comics/');
    }

    final res = await _get('$_baseUrl/$requestPath');
    if (res.statusCode != 200 && res.statusCode != 302) {
      throw Exception('Failed to load detail: ${res.statusCode}');
    }
    // Force UTF-8: site serves no charset, so res.body defaults to Latin-1.
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));

    // Series detail from the `[props*=title],[props*=description]` island.
    final props = _extractProps(doc, ['title', 'description']);
    final slug = _trimSlug(cleanHref.split('/').last);

    final titleObj = props?['title'];
    var title = '';
    if (titleObj is Map && titleObj['en'] != null) {
      title = titleObj['en'].toString();
    } else if (titleObj != null) {
      title = titleObj.toString();
    } else if (props?['seriesTitle'] != null) {
      title = props!['seriesTitle'].toString();
    }
    if (title.isEmpty) throw Exception('Missing title');

    String author = '';
    String rating = '';
    String status = '';
    String type = '';
    final genres = <Genre>[];

    // Try /api/series/{slug} for extra fields, fall back to empty.
    try {
      final detailRes = await _get('$_apiUrl/series/$slug');
      if (detailRes.statusCode == 200) {
        final d = jsonDecode(detailRes.body);
        if (d is Map) {
          author = (d['author']?.toString() ?? '');
          rating = _cleanRating(d['rating']);
          status = _statusText(d['status']?.toString() ?? '');
          type = _capitalize(d['type']?.toString() ?? '');
          final g = d['genres'];
          if (g is List) {
            for (final item in g) {
              final name = item is Map ? (item['name']?.toString() ?? '') : item.toString();
              if (name.isNotEmpty) genres.add(Genre(title: name, href: ''));
            }
          }
          if (type.isNotEmpty && genres.every((x) => x.title != type)) {
            genres.add(Genre(title: type, href: ''));
          }
        }
      }
    } catch (_) {}

    // Chapters from the `[props*=chapters]` island.
    final chapters = <Chapter>[];
    final chProps = _extractProps(doc, ['chapters']);
    final rawChapters = chProps?['chapters'];
    if (rawChapters is List) {
      for (final c in rawChapters) {
        if (c is! Map) continue;
        final numObj = c['number'] ?? c['chapter'];
        final cTitle = c['title']?.toString() ?? '';
        final seriesSlug = c['series_slug']?.toString() ?? slug;
        final isLocked = c['is_locked'] == true;
        final number = numObj.toString().replaceAll(RegExp(r'\.0$'), '');
        if (number.isEmpty) continue;

        final name = (isLocked ? '🔒 ' : '') +
            'Chapter $number' +
            (cTitle.isNotEmpty ? ' - $cTitle' : '');
        chapters.add(
          Chapter(
            title: name,
            href: '/comics/$slug/chapter/$number',
            date: c['created_at']?.toString() ?? '',
          ),
        );
      }
    }

    String description = '';
    final desc = props?['description'];
    if (desc is String && desc.isNotEmpty) {
      description = (html_parser.parseFragment(desc).text ?? '').trim();
    }

    String thumbnail = '';
    final cover = props?['coverUrl'] ?? props?['cover'];
    if (cover != null) thumbnail = _cleanCover(cover.toString());

    return ComicDetail(
      href: _toRelative('/series/$slug'),
      title: title,
      altTitle: '',
      thumbnail: thumbnail,
      description: description,
      status: status,
      type: type,
      released: '',
      author: author,
      updatedOn: '',
      rating: rating,
      latestChapter: chapters.isNotEmpty ? chapters.first.title : null,
      genres: genres,
      chapters: chapters,
    );
  }

  String _statusText(String raw) {
    switch (raw.toLowerCase()) {
      case 'ongoing':
        return 'Ongoing';
      case 'completed':
        return 'Completed';
      case 'hiatus':
        return 'Hiatus';
      case 'dropped':
      case 'axed':
        return 'Dropped';
      default:
        return raw.isEmpty ? 'Unknown' : raw;
    }
  }

  // ── Genres / filters ───────────────────────────────────────────

  @override
  Future<List<Genre>> fetchGenres() async {
    const genres = <String, String>{
      'Action': 'action',
      'Adventure': 'adventure',
      'Comedy': 'comedy',
      'Drama': 'drama',
      'Fantasy': 'fantasy',
      'Harem': 'harem',
      'Horror': 'horror',
      'Isekai': 'isekai',
      'Manhwa': 'manhwa',
      'Manhua': 'manhua',
      'Martial Arts': 'martial-arts',
      'Mystery': 'mystery',
      'Romance': 'romance',
      'School Life': 'school-life',
      'Shounen': 'shounen',
      'Slice of Life': 'slice-of-life',
      'Sports': 'sports',
      'Supernatural': 'supernatural',
    };
    return genres.entries
        .map((e) => Genre(title: e.key, href: '/${e.value}/'))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    // API supports genre filtering via `genre` param (best-effort). Fall back
    // to popular list when the API ignores it.
    try {
      final slug = _extractSlug(genre);
      final uri = Uri.parse('$_apiUrl/series').replace(queryParameters: {
        'offset': ((page - 1) * _pageLimit).toString(),
        'limit': _pageLimit.toString(),
        'genre': slug,
        'sort': 'popular',
      });
      final data = await _getList(uri.toString());
      final items = <ComicItem>[];
      for (final raw in data) {
        final m = raw as Map<String, dynamic>;
        final title = (m['title'] ?? '').toString();
        final s = (m['slug'] ?? '').toString();
        if (title.isEmpty || s.isEmpty) continue;
        items.add(ComicItem(
          title: title,
          href: '/series/$s',
          thumbnail: _cleanCover(m['cover'] ?? m['cover_url'] ?? ''),
          rating: _cleanRating(m['rating']),
        ));
      }
      if (items.isNotEmpty) return items;
    } catch (_) {}
    return fetchPopular(page: page);
  }

  String _extractSlug(String value) => value
      .trim()
      .replaceAll(RegExp(r'^.*/(genre|genres)?/'), '')
      .replaceAll(RegExp(r'^/'), '')
      .replaceAll(RegExp(r'/$'), '');

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    return _fetchList(
      sort: order ?? 'popular',
      page: page,
      query: null,
    );
  }

  // ── Chapter reading ────────────────────────────────────────────

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final cleanHref = href.startsWith('/') ? href.substring(1) : href;
    final res = await _get('$_baseUrl/$cleanHref');
    if (res.statusCode != 200) {
      throw Exception('Failed to load chapter: ${res.statusCode}');
    }
    // Force UTF-8: site serves no charset, so res.body defaults to Latin-1.
    final doc = html_parser.parse(utf8.decode(res.bodyBytes));

    // Chapter title.
    String title = '';
    final props = _extractProps(doc, ['chapterName']);
    final chName = props?['chapterName']?.toString() ?? '';
    final chTitle = props?['chapterTitle']?.toString() ?? '';
    final seriesName = props?['seriesName']?.toString() ?? '';
    if (seriesName.isNotEmpty || chName.isNotEmpty) {
      title = '$seriesName Chapter $chName'
          .trim();
    }
    if (title.isEmpty) title = doc.querySelector('title')?.text.trim() ?? '';
    if (title.isEmpty) {
      final seg = cleanHref.split('/').last;
      title = 'Chapter $seg';
    }

    // Pages from `[props*=pages]`.
    final pageProps = _extractProps(doc, ['pages']);
    final rawPages = pageProps?['pages'];
    final panels = <String>[];

    if (rawPages is List) {
      for (final p in rawPages) {
        if (p is! Map) continue;
        final url = p['url']?.toString() ?? '';
        if (url.isEmpty) continue;
        Object? tiles = p['tiles'];
        final tileCols = (p['tile_cols'] ?? p['tileCols']);
        final tileRows = (p['tile_rows'] ?? p['tileRows']);

        if (tiles is List && tiles.isNotEmpty && tileCols is num && tileRows is num) {
          final panel = await _unscramble(
            url,
            tiles.cast<int>(),
            tileCols.toInt(),
            tileRows.toInt(),
          );
          if (panel != null) panels.add(panel);
        } else {
          panels.add(url);
        }
      }
    }

    if (panels.isEmpty) {
      // Fallback: direct `.special-once img` / `.reader-main img` images.
      for (final img in doc.querySelectorAll('img')) {
        final src = img.attributes['data-src'] ?? img.attributes['src'] ?? '';
        if (src.isNotEmpty &&
            (src.contains('chapters/') || src.contains('pages/')) &&
            !panels.contains(src)) {
          panels.add(src);
        }
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    return ReadChapter(title: title.trim(), prev: '', next: '', panel: panels);
  }

  /// Download a scrambled image and re-arrange its tiles into the correct
  /// order. Returns a `data:` URI (PNG) so it can be rendered directly.
  Future<String?> _unscramble(
    String url,
    List<int> tiles,
    int tileCols,
    int tileRows,
  ) async {
    try {
      final res = await _get(url);
      if (res.statusCode != 200) return null;

      final source = img.decodeImage(res.bodyBytes);
      if (source == null || tiles.isEmpty || tileCols == 0 || tileRows == 0) {
        return url; // not scrambled after all / unable to decode
      }

      final tileW = (source.width / tileCols).floor();
      final tileH = (source.height / tileRows).floor();
      final output = img.Image(
        width: source.width,
        height: source.height,
        numChannels: 4,
      );

      for (var w = 0; w < tiles.length; w++) {
        final j = tiles[w] % (tileCols * tileRows);
        final srcCol = w % tileCols;
        final srcRow = w ~/ tileCols;
        final dstCol = j % tileCols;
        final dstRow = j ~/ tileCols;

        final tile = img.copyCrop(
          source,
          x: srcCol * tileW,
          y: srcRow * tileH,
          width: tileW,
          height: tileH,
        );
        img.compositeImage(
          output,
          tile,
          dstX: dstCol * tileW,
          dstY: dstRow * tileH,
        );
      }

      final png = img.encodePng(output);
      return 'data:image/png;base64,${base64Encode(png)}';
    } catch (_) {
      return url;
    }
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