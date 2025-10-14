import 'genre.dart';
import 'chapter.dart';

class ComicDetail {
  final String href;
  final String title;
  final String altTitle;
  final String thumbnail;
  final String description;
  final String status;
  final String type;
  final String released;
  final String author;
  final String updatedOn;
  final String rating;
  final String? latestChapter;
  final List<Genre> genres;
  final List<Chapter> chapters;

  ComicDetail({
    required this.href,
    required this.title,
    required this.altTitle,
    required this.thumbnail,
    required this.description,
    required this.status,
    required this.type,
    required this.released,
    required this.author,
    required this.updatedOn,
    required this.rating,
    this.latestChapter,
    required this.genres,
    required this.chapters,
  });

  factory ComicDetail.fromJson(Map<String, dynamic> json) {
    return ComicDetail(
      href: json['href'] as String,
      title: json['title'] as String,
      altTitle: json['altTitle'] as String,
      thumbnail: json['thumbnail'] as String,
      description: json['description'] as String,
      status: json['status'] as String,
      type: json['type'] as String,
      released: json['released'] as String,
      author: json['author'] as String,
      updatedOn: json['updatedOn'] as String,
      rating: json['rating'] as String,
      latestChapter: json['latest_chapter'] as String?,
      genres:
          (json['genre'] as List?)
              ?.map((e) => Genre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      chapters:
          (json['chapter'] as List?)
              ?.map((e) => Chapter.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'href': href,
      'title': title,
      'altTitle': altTitle,
      'thumbnail': thumbnail,
      'description': description,
      'status': status,
      'type': type,
      'released': released,
      'author': author,
      'updatedOn': updatedOn,
      'rating': rating,
      if (latestChapter != null) 'latest_chapter': latestChapter,
      'genre': genres.map((e) => e.toJson()).toList(),
      'chapter': chapters.map((e) => e.toJson()).toList(),
    };
  }
}
