class ComicItem {
  final String title;
  final String href;
  final String thumbnail;
  final String? type;
  final String? chapter;
  final String? rating;

  ComicItem({
    required this.title,
    required this.href,
    required this.thumbnail,
    this.type,
    this.chapter,
    this.rating,
  });

  factory ComicItem.fromJson(Map<String, dynamic> json) {
    return ComicItem(
      title: json['title'] as String,
      href: json['href'] as String,
      thumbnail: json['thumbnail'] as String,
      type: json['type'] as String?,
      chapter: json['chapter'] as String?,
      rating: json['rating'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'href': href,
      'thumbnail': thumbnail,
      if (type != null) 'type': type,
      if (chapter != null) 'chapter': chapter,
      if (rating != null) 'rating': rating,
    };
  }

  @override
  String toString() {
    return 'ComicItem(title: $title, href: $href, type: $type)';
  }
}
