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

  /// Gambar chapter di-host di CDN (cdn.itachi.my.id) yang melakukan hotlink
  /// protection (referer check). Tanpa header `Referer` yang benar, request
  /// gambar di-redirect (302) dan chapter tidak bisa dirender.
  ///
  /// Referer `ikiru.id` **hanya** dibutuhkan/valid untuk gambar chapter.
  /// Untuk thumbnail & daftar, header ini justru memblokir gambar, jadi
  /// [imageHeaders] sengaja dikosongkan dan Referer dipindah ke
  /// [chapterImageHeaders].
  @override
  Map<String, String> get imageHeaders => const {};

  /// Panel gambar chapter membutuhkan `Referer: https://ikiru.id/`.
  @override
  Map<String, String> get chapterImageHeaders => const {
    'Referer': 'https://ikiru.id/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };
}
