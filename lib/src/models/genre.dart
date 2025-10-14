class Genre {
  final String title;
  final String href;

  Genre({required this.title, required this.href});

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(title: json['title'] as String, href: json['href'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'href': href};
  }
}
