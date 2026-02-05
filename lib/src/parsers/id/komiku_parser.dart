import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';
import 'package:mangaloom_parser/src/models/cached_result.dart';
import 'package:mangaloom_parser/src/utils/cache.dart';

class KomikuParser extends ComicParser {
  static const String _baseUrl = 'https://komiku.org';
  static const String _apiUrl = 'https://api.komiku.org'; // TargetURL3 in Go
  static const String _mainKomikuUrl =
      'https://komiku.org'; // TargetURL_3_MAINKOMIKU in Go

  final http.Client _client;

  // Cache for list results
  final Map<String, CachedResult> _listCache = {};

  KomikuParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'Komiku';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get language => 'ID';

  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': baseUrl,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

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

  String _trimKomikuHref(String href) {
    href = href.trim();
    // Normalize by Removing common domains if they exist in the link
    href = href.replaceAll(
      RegExp(r'https?://(www\.)?(api\.)?komiku\.(org|co\.id|id|com)'),
      '',
    );

    // Remove /manga/ prefix if present to normalize
    if (href.startsWith('/manga/')) {
      href = href.substring(7);
    }

    if (!href.startsWith('/')) {
      href = '/$href';
    }
    return href;
  }

  String _cleanThumbnailKomikuUrl(String thumb) {
    thumb = thumb.trim();
    if (thumb.contains('?resize')) {
      thumb = thumb.split('?')[0];
    }
    return thumb;
  }

  String _extractKomikuType(String type) {
    type = type.trim();
    if (type.toLowerCase().contains('manga')) return 'Manga';
    if (type.toLowerCase().contains('manhwa')) return 'Manhwa';
    if (type.toLowerCase().contains('manhua')) return 'Manhua';
    return type;
  }

  String _extractKomikuRating(String rating) {
    return rating.trim();
  }

  // Parsing logic for comic items list
  List<ComicItem> _parseComicList(Document doc) {
    final items = <ComicItem>[];

    // Check for "Not Found" indicators
    if (doc.querySelector(
          'svg.fa-korvue, svg[data-icon="korvue"], .fa-korvue',
        ) !=
        null) {
      debugPrint('KomikuParser: Page returned "Not Found" indicator.');
      return items;
    }

    final elements = doc.querySelectorAll('.bge');
    debugPrint('KomikuParser: Found ${elements.length} comic elements');

    for (final e in elements) {
      try {
        final title = e.querySelector('.kan h3')?.text.trim() ?? '';
        final hrefRaw = e.querySelector('.bgei a')?.attributes['href'] ?? '';
        final thumbnail = e.querySelector('.bgei img')?.attributes['src'] ?? '';
        final typeRaw = e.querySelector('.tpe1_inf')?.text.trim() ?? '';
        final ratingRaw = e.querySelector('.kan .judul2')?.text.trim() ?? '';

        // Latest chapter logic
        String latest = '';
        final newElements = e.querySelectorAll('.new1');
        if (newElements.isNotEmpty) {
          final lastNew = newElements.last;
          final spans = lastNew.querySelectorAll('a span');
          if (spans.length >= 2) {
            // Go Logic: .Eq(1) -> index 1
            latest = spans[1].text.trim();
          }
          if (latest.isEmpty) {
            latest = lastNew.querySelector('a')?.text.trim() ?? '';
          }
        }

        if (title.isNotEmpty) {
          items.add(
            ComicItem(
              title: title,
              href: _trimKomikuHref(hrefRaw),
              thumbnail: _cleanThumbnailKomikuUrl(thumbnail),
              type: _extractKomikuType(typeRaw),
              chapter: latest,
              rating: _extractKomikuRating(ratingRaw),
            ),
          );
        }
      } catch (e, stack) {
        debugPrint('KomikuParser: Error parsing item $e - $stack');
        continue;
      }
    }

    return items;
  }

  @override
  Future<List<ComicItem>> fetchRecommended() async {
    const cacheKey = 'recommended';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // Go: TargetURL3 (api.komiku.org)
    final url =
        '$_apiUrl/manga/page/1/?orderby=modified&tipe&genre&genre2&status';
    debugPrint('KomikuParser: Fetching Recommended $url');

    final response = await _client.get(Uri.parse(url), headers: _headers);
    debugPrint('KomikuParser: Status Code ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Failed to load recommended: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);

    if (results.isNotEmpty) {
      _saveToCache(cacheKey, results);
    }
    return results;
  }

  @override
  Future<List<ComicItem>> fetchPopular() async {
    const cacheKey = 'popular';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // Go: TargetURL3 (api.komiku.org)
    final url =
        '$_apiUrl/manga/page/1/?orderby=meta_value_num&tipe&genre&genre2&status';
    debugPrint('KomikuParser: Fetching Popular $url');

    final response = await _client.get(Uri.parse(url), headers: _headers);
    debugPrint('KomikuParser: Status Code ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Failed to load popular: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);

    if (results.isNotEmpty) {
      _saveToCache(cacheKey, results);
    }
    return results;
  }

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final cacheKey = 'newest-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // Go: TargetURL3 (api.komiku.org)
    final url =
        '$_apiUrl/manga/page/$page/?orderby=date&tipe&genre&genre2&status';
    debugPrint('KomikuParser: Fetching Newest $url');

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load newest: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);
    if (results.isEmpty) {
      throw Exception('Page not found or empty');
    }
    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final cacheKey = 'search-$encodedQuery';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // Go: TargetURL3 (api.komiku.org)
    final url = '$_apiUrl/?post_type=manga&s=$encodedQuery';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to search: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);
    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final cacheKey = 'genre-$genre-$page';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    // Go: TargetURL3 (api.komiku.org)
    final url =
        '$_apiUrl/manga/page/$page/?orderby=rand&tipe&genre=$genre&genre2&status';
    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw Exception('Failed to load genre: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);

    // Empty results are valid for genres
    _saveToCache(cacheKey, results);
    return results;
  }

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    String cleanHref = href;
    if (cleanHref.startsWith('/')) cleanHref = cleanHref.substring(1);

    // Go: TargetURL_3_MAINKOMIKU (komiku.org)
    final visitUrl = '$_mainKomikuUrl/manga/$cleanHref';
    debugPrint('KomikuParser: Fetching detail $visitUrl');

    final response = await _client.get(Uri.parse(visitUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load detail: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final mainPerapih = doc.querySelector('main.perapih');
    if (mainPerapih == null) {
      // Sometimes it's just 'main' without perapih class, or structure changed
      throw Exception('Failed to parse detail page structure');
    }

    // Title
    var title =
        mainPerapih.querySelector('#Judul header h1')?.text.trim() ?? '';
    if (title.isEmpty) {
      title = mainPerapih.querySelector('article header h1')?.text.trim() ?? '';
    }
    if (title.startsWith('Komik ')) {
      title = title.substring(6).trim();
    }

    // Alt Title
    var altTitle =
        mainPerapih.querySelector('#Judul header p.j2')?.text.trim() ?? '';
    if (altTitle.isEmpty) {
      altTitle =
          mainPerapih.querySelector('article header p.j2')?.text.trim() ?? '';
    }

    // Thumbnail
    var thumb =
        mainPerapih.querySelector('#Informasi .ims img')?.attributes['src'] ??
        '';
    if (thumb.isEmpty) {
      thumb =
          mainPerapih
              .querySelector('.mobile .btn-bookmark')
              ?.attributes['data-series-cover'] ??
          '';
    }
    if (thumb.isEmpty) {
      thumb = mainPerapih.querySelector('img.sd')?.attributes['src'] ?? '';
    }
    thumb = _cleanThumbnailKomikuUrl(thumb);

    // Description
    String desc = '';
    final judulP = mainPerapih.querySelectorAll('#Judul > p');
    for (var p in judulP) {
      if (!p.classes.contains('j2') && !p.classes.contains('new1')) {
        final text = p.text.trim();
        if (text.isNotEmpty && desc.isEmpty) {
          desc = text;
        }
      }
    }
    if (desc.isEmpty) {
      desc = mainPerapih.querySelector('#Sinopsis p.desc')?.text.trim() ?? '';
      if (desc.isEmpty) {
        desc = mainPerapih.querySelector('p.desc')?.text.trim() ?? '';
      }
    }

    // Meta fields
    String type = '';
    String author = '';
    String status = '';
    String released = '';

    final tableRows = mainPerapih.querySelectorAll(
      '#Informasi table.inftable tr',
    );
    for (var row in tableRows) {
      final tds = row.querySelectorAll('td');
      if (tds.length >= 2) {
        final k = tds[0].text.trim().toLowerCase();
        final v = tds[1].text.trim();

        switch (k) {
          case 'jenis komik':
            type = _extractKomikuType(v);
            break;
          case 'pengarang':
            author = v;
            break;
          case 'status':
            status = v;
            break;
          case 'judul indonesia':
            if (altTitle.isEmpty) altTitle = v;
            break;
          case 'released':
          case 'rilis':
          case 'tanggal':
            if (released.isEmpty) released = v;
            break;
        }
      }
    }

    // Latest Chapter
    String latestChapter = '';
    final new1Elements = mainPerapih.querySelectorAll('#Judul .new1');
    for (var el in new1Elements) {
      if (el.text.contains('Terbaru')) {
        final spans = el.querySelectorAll('a span');
        if (spans.length >= 2) {
          latestChapter = spans[1].text.trim();
        } else {
          final parts = el.text.split(':');
          if (parts.length > 1) {
            latestChapter = parts[1].trim();
          }
        }
      }
    }

    // Genres
    final genres = <Genre>[];
    final genreLinks = mainPerapih.querySelectorAll(
      '#Informasi ul.genre li.genre a',
    );
    for (var a in genreLinks) {
      final gTitle = a.querySelector('span')?.text.trim() ?? '';
      var gHref = a.attributes['href'] ?? '';

      // Clean genre href
      gHref = gHref.trim();
      gHref = gHref.replaceAll(
        RegExp(r'https?://(www\.)?(api\.)?komiku\.(org|co\.id)'),
        '',
      );
      gHref = gHref.replaceAll('/genre/', '');
      if (!gHref.startsWith('/')) gHref = '/$gHref';
      if (!gHref.endsWith('/')) gHref = '$gHref/';

      if (gTitle.isNotEmpty) {
        genres.add(Genre(title: gTitle, href: gHref));
      }
    }

    // Chapters
    final chapters = <Chapter>[];
    final chapterRows = mainPerapih.querySelectorAll(
      '#Daftar_Chapter tbody tr',
    );
    for (var row in chapterRows) {
      if (row.querySelector('th') != null) continue;

      final a = row.querySelector('td.judulseries a');
      if (a == null) continue;

      var cTitle = a.querySelector('span')?.text.trim() ?? '';
      if (cTitle.isEmpty) cTitle = a.text.trim();

      var chHref = a.attributes['href']?.trim() ?? '';
      if (chHref.isEmpty) continue;

      // Remove domain if present
      chHref = chHref.replaceAll(
        RegExp(r'https?://(www\.)?(api\.)?komiku\.(org|co\.id)'),
        '',
      );
      if (chHref.startsWith('/')) chHref = chHref.substring(1);

      final date = row.querySelector('td.tanggalseries')?.text.trim() ?? '';

      chapters.add(Chapter(title: cTitle, href: chHref, date: date));
    }

    // Rating
    String rating = '';
    var ratingText = doc.querySelector('.vw')?.text.trim() ?? '';
    if (ratingText.isEmpty) {
      ratingText = doc.querySelector('td.pembaca i')?.text.trim() ?? '';
    }
    if (ratingText.isNotEmpty) {
      rating = _extractKomikuRating(ratingText);
    }

    return ComicDetail(
      href: href,
      title: title,
      altTitle: altTitle,
      thumbnail: thumb,
      description: desc,
      status: status,
      type: type,
      released: released,
      author: author,
      updatedOn: '',
      rating: rating,
      latestChapter: latestChapter,
      genres: genres,
      chapters: chapters,
    );
  }

  @override
  Future<ReadChapter> fetchChapter(String href) async {
    if (href.isEmpty) throw Exception('href is required');

    String prevTemp;
    if (href.endsWith('chapter-1') ||
        href.endsWith('chapter-01') ||
        href.endsWith('chapter-01-1')) {
      prevTemp = '';
    } else {
      prevTemp = '/$href/';
    }

    String cleanHref = href;
    if (cleanHref.startsWith('/')) cleanHref = cleanHref.substring(1);

    // Go: TargetURL_3_MAINKOMIKU (komiku.org)
    final visitUrl = '$_mainKomikuUrl/$cleanHref';
    debugPrint('KomikuParser: Reading chapter $visitUrl');

    final response = await _client.get(Uri.parse(visitUrl), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load chapter: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);

    String title = doc.querySelector('#Judul header h1')?.text.trim() ?? '';

    // Images
    final panels = <String>[];
    final images = doc.querySelectorAll('#Baca_Komik img.ww');
    for (var img in images) {
      var src = img.attributes['data-src'] ?? '';
      if (src.isEmpty) src = img.attributes['src'] ?? '';

      if (src.isNotEmpty) {
        src = src.trim();
        src = src.replaceAll('cdn1.komiku.org', 'img.komiku.org');
        if (_isValidKomikuImageUrl(src)) {
          panels.add(src);
        }
      }
    }

    if (panels.isEmpty) {
      throw Exception('No images found in chapter');
    }

    var nextLink =
        doc.querySelector('.pagination a.next')?.attributes['href'] ?? '';
    if (nextLink.isEmpty) {
      nextLink = doc.querySelector('a.buttnext')?.attributes['href'] ?? '';
    }

    // Clean next link
    if (nextLink.isNotEmpty) {
      nextLink = nextLink.replaceAll(
        RegExp(r'https?://(www\.)?(api\.)?komiku\.(org|co\.id)'),
        '',
      );
      if (nextLink.startsWith('/')) nextLink = nextLink.substring(1);
    }

    var prevLink = _constructPrevLink(prevTemp);
    if (prevLink.isEmpty && href.contains('chapter-')) {
      prevLink =
          doc.querySelector('.pagination a.prev')?.attributes['href'] ?? '';
      if (prevLink.isEmpty) {
        prevLink = doc.querySelector('a.buttprev')?.attributes['href'] ?? '';
      }
      // Clean prev link if found in DOM
      if (prevLink.isNotEmpty) {
        prevLink = prevLink.replaceAll(
          RegExp(r'https?://(www\.)?(api\.)?komiku\.(org|co\.id)'),
          '',
        );
        if (prevLink.startsWith('/')) prevLink = prevLink.substring(1);
      }
    }

    if (title.isEmpty) {
      title = _generateTitleFromHref(href);
    }

    return ReadChapter(
      title: title,
      prev: prevLink,
      next: nextLink.trim(),
      panel: panels,
    );
  }

  String _constructPrevLink(String currentHref) {
    if (currentHref.isEmpty) return '';
    final re = RegExp(r'(chapte(?:r)?[-/])(\d+)(?:[-](\d+))?');
    final match = re.firstMatch(currentHref);

    if (match == null || match.groupCount < 2) {
      return '';
    }

    final prefix = match.group(1)!;
    final majorStr = match.group(2)!;
    final minorStr = match.group(3);

    String newChapterPart;

    if (minorStr != null && minorStr.isNotEmpty) {
      final minorNum = int.tryParse(minorStr) ?? 0;
      final prevMinorNum = minorNum - 1;

      if (prevMinorNum > 0) {
        final paddedPrevMinor = prevMinorNum.toString().padLeft(
          minorStr.length,
          '0',
        );
        newChapterPart = '$prefix$majorStr-$paddedPrevMinor';
      } else {
        newChapterPart = '$prefix$majorStr';
      }
    } else {
      final majorNum = int.tryParse(majorStr) ?? 0;
      final prevMajorNum = majorNum - 1;

      if (prevMajorNum <= 0) {
        return '';
      }

      final paddedPrevMajor = prevMajorNum.toString().padLeft(
        majorStr.length,
        '0',
      );
      newChapterPart = '$prefix$paddedPrevMajor';
    }

    var result = currentHref.replaceFirst(match.group(0)!, newChapterPart);
    if (result.startsWith('/')) result = result.substring(1);
    return result;
  }

  bool _isValidKomikuImageUrl(String url) {
    final validDomains = [
      'img.komiku.org',
      'gambar-id.komiku.org',
      'cdn.komiku.org',
      'cdn1.komiku.org',
    ];
    for (var domain in validDomains) {
      if (url.contains(domain)) return true;
    }
    return false;
  }

  String _generateTitleFromHref(String href) {
    var url = href;
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.startsWith('/')) url = url.substring(1);

    final parts = url.split('-');
    final titleParts = <String>[];

    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (part.toLowerCase() == 'chapter') {
        titleParts.add('Chapter');
        if (i + 1 < parts.length) {
          titleParts.add(parts[i + 1]);
        }
        break;
      }
      if (part.isNotEmpty) {
        titleParts.add(part[0].toUpperCase() + part.substring(1));
      }
    }
    return titleParts.join(' ');
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    // Go: TargetURL_3_MAINKOMIKU (komiku.org)
    final url = '$_mainKomikuUrl/pustaka/';
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to load genre list: ${response.statusCode}');
    }

    final doc = html_parser.parse(response.body);
    final validGenres = <Genre>[];

    final options = doc.querySelectorAll("select[name='genre'] option");
    for (var opt in options) {
      final val = opt.attributes['value']?.trim() ?? '';
      if (val.isEmpty) continue;

      var text = opt.text.trim();
      if (text.contains(' (')) {
        text = text.substring(0, text.indexOf(' (')).trim();
      }

      final href = '/$val/';
      validGenres.add(Genre(title: text, href: href));
    }

    return validGenres;
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    final safeGenre = genre ?? '';
    final safeStatus = status ?? '';
    final safeType = type ?? '';
    final safeOrder = order ?? '';

    // Go: TargetURL3 (api.komiku.org)
    final url =
        '$_apiUrl/manga/page/$page/?orderby=$safeOrder&tipe=$safeType&genre=$safeGenre&genre2&status=$safeStatus';

    debugPrint('KomikuParser: Filtered URL $url');
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200)
      throw Exception('Failed: ${response.statusCode}');

    final doc = html_parser.parse(response.body);
    final results = _parseComicList(doc);
    return results;
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    return fetchNewest(page: page);
  }

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
