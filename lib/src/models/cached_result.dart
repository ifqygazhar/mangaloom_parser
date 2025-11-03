import 'package:mangaloom_parser/mangaloom_parser.dart';

/// Cache result model
class CachedResult {
  final List<ComicItem> items;
  final DateTime timestamp;

  CachedResult({required this.items, required this.timestamp});
}
