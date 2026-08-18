import 'package:mangaloom_parser/src/parsers/lib/natsu_parser.dart';

/// Parser for Kiryuu (https://v7.kiryuu.to)
/// Extends [NatsuParser] (NatsuId WordPress theme) — inherits all default
/// behaviour. Previously removed when the old domain (kiryuu03.com) died;
/// re-added with the current v7 domain.
class KiryuuParser extends NatsuParser {
  KiryuuParser({super.client});

  @override
  String get sourceName => 'Kiryuu';

  @override
  String get domain => 'v7.kiryuu.to';

  @override
  String get language => 'ID';

  /// Kiryuu serves images from its own domain and does not (currently) require
  /// a special referer for images, but sending a root Referer keeps it safe.
  @override
  Map<String, String> get imageHeaders => const {
    'Referer': 'https://v7.kiryuu.to/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };
}