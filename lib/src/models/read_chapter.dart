class ReadChapter {
  final String title;
  final String prev;
  final String next;
  final List<String> panel;

  ReadChapter({
    required this.title,
    required this.prev,
    required this.next,
    required this.panel,
  });

  factory ReadChapter.fromJson(Map<String, dynamic> json) {
    return ReadChapter(
      title: json['title'] as String,
      prev: json['prev'] as String,
      next: json['next'] as String,
      panel: (json['panel'] as List).map((e) => e as String).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'prev': prev, 'next': next, 'panel': panel};
  }
}
