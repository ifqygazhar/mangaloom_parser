# 📚 Mangaloom Parser - Documentation Summary

## 📁 Documentation Files

| File                | Description                                                    |
| ------------------- | -------------------------------------------------------------- |
| **README.md**       | Complete documentation with installation, usage, API reference |
| **QUICKSTART.md**   | Quick reference guide for common tasks                         |
| **CHANGELOG.md**    | Version history and changes                                    |
| **CONTRIBUTING.md** | Guidelines for contributors                                    |
| **LICENSE**         | MIT License                                                    |

## 🎯 Key Features

✅ Multiple parser support (Shinigami, Webtoon, MangaPlus, Komiku, Ikiru, Kiryuu, BacaKomik, Komikindo, Bbato, AsuraScans, FlameComics)
✅ Fetch popular, recommended, newest comics
✅ Search functionality
✅ Genre browsing and filtering
✅ Advanced filtering (status, type, order)
✅ Comic details with chapters
✅ Chapter reading with image URLs
✅ `imageHeaders` for referer-protected image loading (hotlink protection)
✅ Pagination support
✅ Indonesian language support

## 📦 Installation

### From pub.dev (when published)

```bash
flutter pub add mangaloom_parser
```

### From source

```yaml
dependencies:
  mangaloom_parser:
    git:
      url: https://github.com/ifqygazhar/mangaloom_parser.git
```

## 🚀 Quick Example

```dart
import 'package:mangaloom_parser/mangaloom_parser.dart';

void main() async {
  final parser = ShinigamiParser();

  try {
    // Fetch popular comics
    final comics = await parser.fetchPopular();
    print('Found ${comics.length} comics');

    // Get detail of first comic
    if (comics.isNotEmpty) {
      final detail = await parser.fetchDetail(comics.first.href);
      print('Title: ${detail.title}');
      print('Chapters: ${detail.chapters.length}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    parser.dispose();
  }
}
```

## 🏗️ Project Structure

```
mangaloom_parser/
├── lib/
│   ├── mangaloom_parser.dart          # Main export file
│   └── src/
│       ├── models/                     # Data models
│       │   ├── comic_item.dart
│       │   ├── comic_detail.dart
│       │   ├── chapter.dart
│       │   ├── read_chapter.dart
│       │   └── genre.dart
│       ├── parsers/                    # Parser implementations
│       │   ├── parser_base.dart        # Base class (ComicParser)
│       │   ├── id/                     # Indonesian parsers
│       │   │   ├── shinigami_parser.dart
│       │   │   ├── mangaplus_parser.dart
│       │   │   ├── webtoon_parser.dart
│       │   │   ├── komiku_parser.dart
│       │   │   └── ikiru_parser.dart
│       │   ├── en/                     # English parsers
│       │   │   └── bbato_parser.dart
│       │   └── lib/                    # Shared base parsers
│       │       └── natsu_parser.dart   # Base for NatsuId theme sites
│       └── utils/                      # Utilities
│           └── make_request_helper.dart
├── example/                            # Example Flutter app
├── test/                              # Unit tests
├── README.md                          # Main documentation
├── QUICKSTART.md                      # Quick reference
├── CHANGELOG.md                       # Version history
├── CONTRIBUTING.md                    # Contribution guide
├── LICENSE                            # MIT License
└── pubspec.yaml                       # Package configuration
```

## 🔧 API Overview

### Parsers

- `ShinigamiParser()` - Shinigami source (ID)
- `WebtoonParser()` - Webtoon source (ID)
- `MangaPlusParser()` - MangaPlus source (ID)
- `KomikuParser()` - Komiku source (ID)
- `IkiruParser()` - Ikiru source (ID)
- `KiryuuParser()` - Kiryuu source (ID)
- `BacaKomikParser()` - BacaKomik source (ID)
- `KomikindoParser()` - Komikindo source (ID)
- `BbatoParser()` - Bbato source (EN)
- `AsuraScansParser()` - AsuraScans source (EN)
- `FlameComicsParser()` - FlameComics source (EN)

Removed (source dead / not scrapable): `MangaParkParser`, `ComicSansParser`, `BatotoParser`, `KomikluParser`, `KiryuuParser`.

### Image Headers

```dart
// Some sources (e.g. Komiku) block hotlinked images with 403.
// Always pass the parser's headers when rendering images:
Image.network(url, headers: parser.imageHeaders)
```

### Models

- `ComicItem` - Comic list item
- `ComicDetail` - Detailed comic information
- `Chapter` - Chapter information
- `ReadChapter` - Chapter reading data
- `Genre` - Genre information

### Methods (all parsers)

```dart
// List fetching
Future<List<ComicItem>> fetchPopular()
Future<List<ComicItem>> fetchRecommended()
Future<List<ComicItem>> fetchNewest({int page = 1})
Future<List<ComicItem>> fetchAll({int page = 1})
Future<List<ComicItem>> search(String query)
Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1})
Future<List<ComicItem>> fetchFiltered({...})

// Browse & Read
Future<List<Genre>> fetchGenres()
Future<ComicDetail> fetchDetail(String href)
Future<ReadChapter> fetchChapter(String href)

// Cleanup
void dispose()
```

## 🎨 Example App Features

The example app includes:

- ✅ Parser switcher (Drawer)
- ✅ Function selector (8 test functions)
- ✅ Search dialog
- ✅ Filter bottom sheet
- ✅ Pagination controls
- ✅ Comic grid view
- ✅ Genre list
- ✅ Comic detail page
- ✅ Chapter reader

Run example:

```bash
cd example && flutter run
```

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

## 📤 Publishing (for maintainers)

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md`
3. Run checks:
   ```bash
   flutter pub publish --dry-run
   ```
4. Publish:
   ```bash
   flutter pub publish
   ```

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Quick steps:

1. Fork the repo
2. Create feature branch
3. Make changes
4. Run tests
5. Submit PR

## 📝 License

MIT License - see [LICENSE](LICENSE) file.

## 🔗 Links

- **Repository**: https://github.com/ifqygazhar/mangaloom_parser
- **Issues**: https://github.com/ifqygazhar/mangaloom_parser/issues
- **Example**: [example/](example/)

## 💡 Support

- 📖 Read the [README.md](README.md)
- 🚀 Check [QUICKSTART.md](QUICKSTART.md)
- 💬 Open an issue
- 🤝 Contribute via PR

---

**Made with ❤️ by [ifqygazhar](https://github.com/ifqygazhar)**
