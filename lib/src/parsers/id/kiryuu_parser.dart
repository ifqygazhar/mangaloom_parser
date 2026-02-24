import 'package:html/dom.dart';
import 'package:mangaloom_parser/src/parsers/lib/natsu_parser.dart';

/// Parser for Kiryuu (kiryuu03.com)
/// Extends [NatsuParser] with a custom chapter image selector.
class KiryuuParser extends NatsuParser {
  KiryuuParser({super.client});

  @override
  String get sourceName => 'Kiryuu';

  @override
  String get domain => 'kiryuu03.com';

  @override
  String get language => 'ID';

  /// Kiryuu uses `section[data-image-data] img` instead of the default
  /// `main section section > img` selector for chapter images.
  @override
  List<String> parseChapterImages(Document doc) {
    final imgs = doc.querySelectorAll('section[data-image-data] img');
    final panels = <String>[];

    for (final img in imgs) {
      final src =
          img.attributes['src'] ??
          img.attributes['data-src'] ??
          img.attributes['data-lazy-src'] ??
          '';
      if (src.isNotEmpty && !src.contains('data:image')) {
        panels.add(toAbsoluteUrl(src));
      }
    }

    return panels;
  }
}
