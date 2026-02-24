import 'package:mangaloom_parser/src/parsers/lib/natsu_parser.dart';

/// Parser for Ikiru (02.ikiru.wtf)
/// Extends [NatsuParser] with no additional overrides — inherits
/// all default behaviour from the base class.
class IkiruParser extends NatsuParser {
  IkiruParser({super.client});

  @override
  String get sourceName => 'Ikiru';

  @override
  String get domain => '02.ikiru.wtf';

  @override
  String get language => 'ID';
}
