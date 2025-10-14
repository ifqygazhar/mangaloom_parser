import '../models/comic_item.dart';
import '../models/comic_detail.dart';
import '../models/read_chapter.dart';
import '../models/genre.dart';

/// Abstract base class untuk semua comic parsers
abstract class ComicParser {
  /// Nama source (contoh: "Shinigami", "KomikStation", dll)
  String get sourceName;

  /// Base URL untuk source ini
  String get baseUrl;

  /// Bahasa yang didukung (ID, EN, dll)
  String get language;

  /// Fetch popular comics
  Future<List<ComicItem>> fetchPopular();

  /// Fetch recommended comics
  Future<List<ComicItem>> fetchRecommended();

  /// Fetch newest comics dengan pagination
  Future<List<ComicItem>> fetchNewest({int page = 1});

  /// Fetch all comics dengan pagination
  Future<List<ComicItem>> fetchAll({int page = 1});

  /// Search comics by query
  Future<List<ComicItem>> search(String query);

  /// Fetch comics by genre dengan pagination
  Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1});

  /// Fetch filtered comics
  Future<List<ComicItem>> fetchFiltered({
    int page = 1,
    String? genre,
    String? status,
    String? type,
    String? order,
  });

  /// Fetch list of available genres
  Future<List<Genre>> fetchGenres();

  /// Fetch comic detail by href/id
  Future<ComicDetail> fetchDetail(String href);

  /// Fetch chapter images for reading
  Future<ReadChapter> fetchChapter(String href);
}
