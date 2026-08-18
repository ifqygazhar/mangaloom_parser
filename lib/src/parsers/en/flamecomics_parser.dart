import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

/// Parser for FlameComics (https://flamecomics.xyz) — English comic source.
///
/// Ported from the Tachiyomi extension `flamecomics/FlameComics.kt`.
/// Uses the Next.js `/_next/data/{buildId}/` JSON API for lists, details,
/// chapters and page images.
///
/// Some images are delivered as composed strips (a URL ending in `?comp` that
/// embeds several image paths joined with `|`). Those are stitched into a
/// single image using `package:image` (decode → composite → encode).
class FlameComicsParser extends ComicParser {
  static const String _baseUrl = 'https://flamecomics.xyz';
  static const String _cdn = 'https://cdn.flamecomics.xyz';

  final http.Client _client;
  final Map<String, CachedResult> _listCache = {};

  String _buildId = '';

  FlameComicsParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'FlameComics';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'EN';

  /// Images are served from cdn.flamecomics.xyz behind a referer check.
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
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Referer': '$_baseUrl/',
  };

  Future<http.Response> _request(
    String url, {
    bool jsonData = false,
  }) async {
    final headers = {..._headers};
    if (jsonData) {
      headers['Accept'] = 'application/json, text/javascript, */*; q=0.01';
      headers['X-Requested-With'] = 'XMLHttpRequest';
    }
    final response = await _client.get(Uri.parse(url), headers: headers);
    return response;
  }

  /// Fetch the current buildId (cached) for the Next.js data API.
  Future<String> _getBuildId() async {
    if (_buildId.isNotEmpty) return _buildId;
    final res = await _request(_baseUrl);
    final body = utf8.decode(res.bodyBytes);
    final m = RegExp(r'"buildId":"([^"]+)"').firstMatch(body);
    if (m == null) throw Exception('Failed to find buildId');
    _buildId = m.group(1)!;
    return _buildId;
  }

  String get _imageApiBase => '$_cdn/uploads/images/series';

  /// Build the thumbnail URL for a series.
  String _thumbnailUrl(Map<String, dynamic> s) {
    final id = s['series_id'];
    final cover = (s['cover'] ?? '').toString();
    final lastEdit = s['last_edit']?.toString() ?? '';
    if (id == null || cover.isEmpty) return '';
    return '$_imageApiBase/$id/$cover?$lastEdit';
  }

  String _toRelative(String url) {
    var href = url.trim();
    href = href.replaceAll(RegExp(r'^https?://[^/]+'), '');
    if (!href.startsWith('/')) href = '/$href';
    return href;
  }

  // ── List parsing ───────────────────────────────────────────────

  Future<List<ComicItem>> _parseBrowseJson(String url) async {
    final res = await _request(url, jsonData: true);
    if (res.statusCode != 200) {
      throw Exception('Failed to load: ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) return [];
    final pageProps = decoded['pageProps'];
    if (pageProps is! Map || pageProps['series'] is! List) return [];

    final items = <ComicItem>[];
    for (final raw in pageProps['series'] as List) {
      if (raw is! Map) continue;
      final s = raw.cast<String, dynamic>();
      final title = (s['title'] ?? '').toString();
      final id = s['series_id'];
      if (title.isEmpty || id == null) continue;
      items.add(ComicItem(
        title: title,
        href: '/series/$id',
        thumbnail: _thumbnailUrl(s),
        type: (s['type'] ?? '').toString(),
        rating: _cleanNumber(s['likes']),
      ));
    }
    return items;
  }

  String _cleanNumber(Object? n) {
    final s = n?.toString() ?? '';
    if (s.isEmpty) return '';
    final v = double.tryParse(s);
    return v == null ? '' : v.toStringAsFixed(0);
  }

  // ── Public: replace the fragment-style pagination. ─────────────
  // The site's browse.json uses a fragment (`#page` / `#page&query`), which
  // the Dart http client drops. We re-encode those as query parameters after
  // the first page (the Next.js data API accepts `?page=`).

  Future<List<ComicItem>> _browse({required int page, String? query}) async {
    final cacheKey = 'fc-browse-$page-${query ?? ''}';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final buildId = await _getBuildId();
    final path = page == 1 && (query == null || query.isEmpty)
        ? 'browse.json'
        : 'browse.json';
    final qp = <String, String>{};
    if (page > 1) qp['page'] = page.toString();
    if (query != null && query.isNotEmpty) qp['query'] = query;
    final sep = qp.isEmpty ? '' : '?';
    final url =
        '$_baseUrl/_next/data/$buildId/$path$sep${Uri(queryParameters: qp).query}';

    final items = await _parseBrowseJson(url);
    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchPopular({int page = 1}) => _browse(page: page);

  @override
  Future<List<ComicItem>> fetchRecommended() => _browse(page: 1);

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    // index.json = latest; only first page is meaningful.
    if (page > 1) return [];
    final cacheKey = 'fc-newest';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final buildId = await _getBuildId();
    final url = '$_baseUrl/_next/data/$buildId/index.json';
    final res = await _request(url, jsonData: true);
    if (res.statusCode != 200) {
      throw Exception('Failed to load newest: ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final items = <ComicItem>[];
    try {
      final entries =
          decoded['pageProps']['latestEntries']['blocks'][0]['series'] as List;
      for (final raw in entries) {
        if (raw is! Map) continue;
        final s = raw.cast<String, dynamic>();
        final title = (s['title'] ?? '').toString();
        final id = s['series_id'];
        if (title.isEmpty || id == null) continue;
        items.add(ComicItem(
          title: title,
          href: '/series/$id',
          thumbnail: _thumbnailUrl(s),
        ));
      }
    } catch (_) {}
    _saveToCache(cacheKey, items);
    return items;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) => _browse(page: page);

  @override
  Future<List<ComicItem>> search(String query) async {
    // Filter the full browse list client-side (matches Kotlin behaviour).
    final q = _normalize(query);
    final all = await _browse(page: 1);
    final filtered = all.where((c) {
      return c.title.toLowerCase().contains(q);
    }).toList();
    return filtered;
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');

  // ── Genres ─────────────────────────────────────────────────────

  @override
  Future<List<Genre>> fetchGenres() async {
    const genres = {
      'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Harem',
      'Horror', 'Isekai', 'Martial Arts', 'Mystery', 'Psychological',
      'Romance', 'School Life', 'Sci-fi', 'Seinen', 'Slice of Life',
      'Sports', 'Supernatural', 'Thriller',
    };
    return genres
        .map((g) => Genre(title: g, href: '/$g'.toLowerCase()))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    return _browse(page: page);
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    return _browse(page: page);
  }

  // ── Details ────────────────────────────────────────────────────

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    final seriesId = href.split('/').last;
    final buildId = await _getBuildId();
    final url = '$_baseUrl/_next/data/$buildId/series/$seriesId.json?id=$seriesId';
    final res = await _request(url, jsonData: true);
    if (res.statusCode != 200) {
      throw Exception('Failed to load detail: ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final pageProps = decoded['pageProps'];
    if (pageProps is! Map) throw Exception('Failed to parse detail');

    final s = (pageProps['series'] ?? <String, dynamic>{}).cast<String, dynamic>();
    final title = (s['title'] ?? '').toString();
    if (title.isEmpty) throw Exception('Missing title');

    // Alternate titles + description.
    String altTitle = '';
    final altTitles = s['altTitles'];
    if (altTitles is List && altTitles.isNotEmpty) {
      altTitle = altTitles.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(', ');
    }

    String description = (s['description'] ?? '').toString();
    if (description.isNotEmpty) {
      description = _stripHtml(description).trim();
      if (altTitle.isNotEmpty) description = '$description\n\nAlternative Names:\n- $altTitle';
    }

    String author = '';
    final auth = s['author'];
    if (auth is List) author = auth.join(', ');
    String artist = '';
    final art = s['artist'];
    if (art is List) artist = art.join(', ');
    if (author.isEmpty) author = artist;

    // Genres: type + tags.
    final genres = <Genre>[];
    final type = (s['type'] ?? '').toString();
    if (type.isNotEmpty) genres.add(Genre(title: type, href: ''));
    final tags = s['tags'];
    if (tags is List) {
      for (final t in tags) {
        final name = t.toString();
        if (name.isNotEmpty) genres.add(Genre(title: name, href: ''));
      }
    }

    // Status.
    final status = _statusText((s['status'] ?? '').toString());

    // Chapters.
    final chapters = <Chapter>[];
    final rawChapters = pageProps['chapters'];
    if (rawChapters is List) {
      for (final raw in rawChapters) {
        if (raw is! Map) continue;
        final ch = raw.cast<String, dynamic>();
        final chapterNum = ch['chapter'];
        final token = (ch['token'] ?? '').toString();
        final chId = ch['series_id'];
        if (chapterNum == null || token.isEmpty || chId == null) continue;

        final numStr = chapterNum.toString().replaceAll(RegExp(r'\.0$'), '');
        final chTitle = (ch['title'] ?? '').toString();
        final name = 'Chapter $numStr'
            '${chTitle.isNotEmpty ? ' - $chTitle' : ''}';
        final release = ch['release_date']?.toString() ?? '';
        final date = _tsToDate(release);

        chapters.add(
          Chapter(
            title: name,
            href: '/raw/$chId/$token',
            date: date,
          ),
        );
      }
    }

    return ComicDetail(
      href: _toRelative('/series/$seriesId'),
      title: title,
      altTitle: altTitle,
      thumbnail: _thumbnailUrl(s),
      description: description,
      status: status,
      type: type,
      released: (s['year'] ?? '').toString(),
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
    if (lower.contains('ongoing')) return 'Ongoing';
    if (lower.contains('completed')) return 'Completed';
    if (lower.contains('hiatus')) return 'Hiatus';
    if (lower.contains('dropped')) return 'Dropped';
    return raw.isEmpty ? 'Unknown' : raw;
  }

  String _tsToDate(String ts) {
    final secs = int.tryParse(ts);
    if (secs == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _stripHtml(String html) {
    final re = RegExp(r'<[^>]+>');
    return html.replaceAll(re, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── Chapter reading ────────────────────────────────────────────

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    // href format: /raw/{seriesId}/{token}
    final parts = href.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.length < 3) throw Exception('Invalid chapter href');
    final seriesId = parts[1];
    final token = parts[2];

    final buildId = await _getBuildId();
    final url =
        '$_baseUrl/_next/data/$buildId/series/$seriesId/$token.json?id=$seriesId&token=$token';
    final res = await _request(url, jsonData: true);
    if (res.statusCode != 200) {
      throw Exception('Failed to load chapter: ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final ch = (decoded['pageProps']?['chapter'] ?? <String, dynamic>{})
        .cast<String, dynamic>();

    final title = (ch['title'] ?? '').toString();
    final release = ch['release_date']?.toString() ?? '';

    // Build the panel list from the images map.
    final panels = <String>[];
    final images = ch['images'];
    if (images is Map) {
      final keys = images.keys.toList()..sort((a, b) {
        final ai = int.tryParse(a.toString()) ?? 0;
        final bi = int.tryParse(b.toString()) ?? 0;
        return ai.compareTo(bi);
      });
      for (final k in keys) {
        final meta = images[k];
        if (meta is! Map) continue;
        final name = (meta['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final realUrl = '$_imageApiBase/$seriesId/$token/${Uri.encodeComponent(name)}';
        panels.add(_normalizePageUrl(realUrl, release));
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    return ReadChapter(title: title, prev: '', next: '', panel: panels);
  }

  /// Some instances deliver composed URLs with `?comp` — handled at render;
  /// here we keep the raw URL (with cache-buster query) and detect composed
  /// ones for [stitchImages].
  String _normalizePageUrl(String url, String cacheBuster) {
    var u = url;
    if (cacheBuster.isNotEmpty) u = '$u?$cacheBuster';
    return u;
  }

  // ── Image stitching (FlameComics "?comp") ──────────────────────

  /// Download several images and stitch them horizontally into one PNG
  /// (used when a `?comp` URL is encountered). Returns a `data:` URI.
  Future<String?> stitchImages(List<String> urls) async {
    if (urls.isEmpty) return null;
    try {
      final decoded = <img.Image>[];
      var totalW = 0;
      var maxH = 0;
      for (final u in urls) {
        final res = await _request(u);
        if (res.statusCode != 200) continue;
        final im = img.decodeImage(res.bodyBytes);
        if (im == null) continue;
        decoded.add(im);
        totalW += im.width;
        if (im.height > maxH) maxH = im.height;
      }
      if (decoded.isEmpty) return null;

      final output = img.Image(width: totalW, height: maxH, numChannels: 4);
      var left = 0;
      for (final im in decoded) {
        img.compositeImage(output, im, dstX: left, dstY: 0);
        left += im.width;
      }
      final png = img.encodePng(output);
      return 'data:image/png;base64,${base64Encode(png)}';
    } catch (_) {
      return null;
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