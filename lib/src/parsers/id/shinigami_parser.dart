import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mangaloom_parser/mangaloom_parser.dart';

class ShinigamiParser extends ComicParser {
  static const String _baseApiUrl = 'https://api.shngm.io/v1';
  static const String _storageUrl = 'https://storage.shngm.id';

  final http.Client _client;

  ShinigamiParser({http.Client? client}) : _client = client ?? http.Client();

  @override
  String get sourceName => 'Shinigami';

  @override
  String get baseUrl => 'https://08.shinigami.asia/';

  @override
  String get language => 'ID';

  /// Helper method untuk membuat HTTP request dengan headers yang sesuai
  Future<Map<String, dynamic>> _makeRequest(String url) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        'Accept': 'application/json',
        'Referer': baseUrl,
        'sec-fetch-dest': 'empty',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('API returned status code: ${response.statusCode}');
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Convert country ID to comic type
  String _convertCountryId(String country) {
    switch (country) {
      case 'CN':
        return 'Manhua';
      case 'JP':
        return 'Manga';
      case 'KR':
        return 'Manhwa';
      default:
        return 'Other';
    }
  }

  /// Convert API manga item to ComicItem
  ComicItem _convertToComicItem(Map<String, dynamic> item) {
    return ComicItem(
      title: item['title'] as String,
      href: '/${item['manga_id']}/',
      thumbnail: item['cover_image_url'] as String,
      type: _convertCountryId(item['country_id'] as String),
      chapter: (item['latest_chapter_number'] as num?)?.toStringAsFixed(1),
      rating: (item['user_rate'] as num?)?.toStringAsFixed(1),
    );
  }

  @override
  Future<List<ComicItem>> fetchPopular() async {
    final url =
        '$_baseApiUrl/manga/list?page=1&page_size=24&sort=popularity&sort_order=desc';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchRecommended() async {
    final url =
        '$_baseApiUrl/manga/list?page=1&page_size=24&sort=rating&sort_order=desc';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchNewest({int page = 1}) async {
    final url =
        '$_baseApiUrl/manga/list?page=$page&page_size=24&sort=latest&sort_order=desc';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchAll({int page = 1}) async {
    final url = '$_baseApiUrl/manga/list?page=$page&page_size=24';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ComicItem>> search(String query) async {
    final encodedQuery = Uri.encodeComponent(query);
    final url = '$_baseApiUrl/manga/list?q=$encodedQuery&page=1&page_size=24';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    if (items.isEmpty) {
      throw Exception('No results found');
    }

    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1}) async {
    final encodedGenre = Uri.encodeComponent(genre);
    final url =
        '$_baseApiUrl/manga/list?page=$page&page_size=24&genre_include=$encodedGenre&genre_include_mode=and&sort=popularity&sort_order=desc';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  }) async {
    var url = '$_baseApiUrl/manga/list?page=$page&page_size=24';

    // Add sorting
    if (order != null && order.isNotEmpty) {
      switch (order) {
        case 'popular':
          url += '&sort=popularity&sort_order=desc';
          break;
        case 'latest':
          url += '&sort=latest&sort_order=desc';
          break;
        case 'rating':
          url += '&sort=rating&sort_order=desc';
          break;
        default:
          url += '&sort=latest&sort_order=desc';
      }
    }

    // Add status filter
    if (status != null && status.isNotEmpty) {
      switch (status) {
        case 'ongoing':
          url += '&status=ongoing';
          break;
        case 'completed':
          url += '&status=completed';
          break;
        case 'hiatus':
          url += '&status=hiatus';
          break;
      }
    }

    // Add type filter
    if (type != null && type.isNotEmpty) {
      final encodedType = Uri.encodeComponent(type);
      url += '&format=$encodedType';
    }

    // Add genre filter
    if (genre != null && genre.isNotEmpty) {
      final encodedGenre = Uri.encodeComponent(genre);
      url += '&genre_include=$encodedGenre&genre_include_mode=and';
    }

    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    if (items.isEmpty) {
      throw Exception('Page not found');
    }

    return items
        .map((item) => _convertToComicItem(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Genre>> fetchGenres() async {
    final url = '$_baseApiUrl/genre/list';
    final data = await _makeRequest(url);

    final List items = data['data'] as List;
    return items.map((item) {
      return Genre(title: item['name'] as String, href: '/${item['slug']}/');
    }).toList();
  }

  @override
  Future<ComicDetail> fetchDetail(String href) async {
    if (href.isEmpty) {
      throw Exception('href is required');
    }

    // Clean manga ID from href
    final mangaId = href.replaceAll('/', '');

    // Get manga details
    final url = '$_baseApiUrl/manga/detail/$mangaId';
    final data = await _makeRequest(url);

    final item = data['data'] as Map<String, dynamic>;

    // Parse genres
    final taxonomy = item['taxonomy'] as Map<String, dynamic>? ?? {};
    final genreList = taxonomy['Genre'] as List? ?? [];
    final genres = genreList.map((g) {
      return Genre(title: g['name'] as String, href: '/${g['slug']}/');
    }).toList();

    // Parse authors
    final authorList = taxonomy['Author'] as List? ?? [];
    final authors = authorList.map((a) => a['name'] as String).join(', ');

    // Parse status
    String status;
    switch (item['status'] as int) {
      case 1:
        status = 'Ongoing';
        break;
      case 2:
        status = 'Completed';
        break;
      case 3:
        status = 'Paused';
        break;
      default:
        status = 'Unknown';
    }

    // Get chapters
    final chaptersUrl =
        '$_baseApiUrl/chapter/$mangaId/list?page=1&page_size=9999&sort_by=chapter_number&sort_order=asc';
    final chaptersData = await _makeRequest(chaptersUrl);

    final List chaptersList = chaptersData['data'] as List;
    final chapters = chaptersList.map((ch) {
      final chapterTitle = (ch['chapter_title'] as String).isEmpty
          ? 'Chapter ${(ch['chapter_number'] as num).toStringAsFixed(1)}'
          : ch['chapter_title'] as String;

      return Chapter(
        title: chapterTitle,
        href: '/${ch['chapter_id']}/',
        date: ch['release_date'] as String,
      );
    }).toList();

    return ComicDetail(
      href: href,
      title: item['title'] as String,
      altTitle: item['alternative_title'] as String? ?? '',
      thumbnail: item['cover_image_url'] as String,
      description: item['description'] as String? ?? '',
      status: status,
      type: _convertCountryId(item['country_id'] as String),
      released: item['release_year'] as String? ?? '',
      author: authors,
      updatedOn: item['updated_at'] as String? ?? '',
      rating: (item['user_rate'] as num?)?.toStringAsFixed(1) ?? '0.0',
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

    // Clean chapter ID from href
    final chapterId = href.replaceAll('/', '');

    // Get chapter details
    final url = '$_baseApiUrl/chapter/detail/$chapterId';
    final data = await _makeRequest(url);

    final responseData = data['data'] as Map<String, dynamic>;
    final chapter = responseData['chapter'] as Map<String, dynamic>;
    final basePath = chapter['path'] as String;
    final imagesList = chapter['data'] as List;

    // Build image URLs
    final panels = imagesList.map((imgName) {
      return '$_storageUrl$basePath$imgName';
    }).toList();

    // Build title
    final title = (responseData['chapter_title'] as String).isEmpty
        ? 'Chapter ${(responseData['chapter_number'] as num).toStringAsFixed(1)}'
        : responseData['chapter_title'] as String;

    // Handle navigation
    final prevChapter = responseData['prev_chapter_id'] as String?;
    final nextChapter = responseData['next_chapter_id'] as String?;

    return ReadChapter(
      title: title,
      prev: prevChapter != null ? '/$prevChapter/' : '',
      next: nextChapter != null ? '/$nextChapter/' : '',
      panel: panels.cast<String>(),
    );
  }

  /// Dispose HTTP client
  void dispose() {
    _client.close();
  }
}
