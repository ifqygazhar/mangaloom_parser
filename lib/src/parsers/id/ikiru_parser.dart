import 'package:mangaloom_parser/src/parsers/lib/natsu_parser.dart';

/// Parser for Ikiru (02.ikiru.wtf)
/// Extends [NatsuParser] with no additional overrides — inherits
/// all default behaviour from the base class.
class IkiruParser extends NatsuParser {
  IkiruParser({super.client});

  @override
  String get sourceName => 'Ikiru';

  @override
  String get domain => '07.ikiru.wtf';

  @override
  String get language => 'ID';

  /// Gambar di-host di CDN (cdn.itachi.my.id) yang melakukan hotlink
  /// protection (referer check). Tanpa header `Referer` yang benar, request
  /// gambar di-redirect (302) dan chapter tidak bisa dirender.
  ///
  /// Referer `ikiru.id` digunakan karena CDN memvalidasi domain ini.
  /// Gunakan header ini saat memuat thumbnail/panel di widget gambar.
  @override
  Map<String, String> get imageHeaders => const {
    'Referer': 'https://ikiru.id/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };
}
