class Chapter {
  final String title;
  final String href;
  final String date;
  final String? downloadUrl;

  Chapter({
    required this.title,
    required this.href,
    required this.date,
    this.downloadUrl,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      title: json['title'] as String,
      href: json['href'] as String,
      date: json['date'] as String,
      downloadUrl: json['downloadUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'href': href,
      'date': date,
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
    };
  }
}
