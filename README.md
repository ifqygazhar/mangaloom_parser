# 📚 Mangaloom Parser

A powerful and flexible Flutter package for parsing comic/manga websites. Easily fetch popular comics, search, filter by genre, and read chapters with a simple and intuitive API.

[![Pub Version](https://img.shields.io/pub/v/mangaloom_parser.svg)](https://pub.dev/packages/mangaloom_parser)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## ✨ Features

- 🔥 **Multiple Parser Support** - Built-in support for multiple comic sources
- 📖 **Fetch Popular Comics** - Get trending and popular titles
- 🆕 **Latest Releases** - Stay updated with newest chapters
- 🔍 **Search Functionality** - Find specific comics easily
- 🎨 **Genre Filtering** - Browse by your favorite genres
- 🎯 **Advanced Filtering** - Filter by status, type, and sort order
- 📄 **Pagination Support** - Efficient browsing with page navigation
- 📚 **Chapter Reading** - Fetch chapter images for reading
- 🌐 **Indonesian Language** - Native support for Indonesian comic sites

## 🚀 Supported Parsers

| Parser              | Source      | Language | Status    |
| ------------------- | ----------- | -------- | --------- |
| **ShinigamiParser** | Shinigami   | ID       | ✅ Active |
| **ComicSansParser** | CosmicScans | ID       | ✅ Active |

## 📦 Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  mangaloom_parser: ^0.0.1
```

Then run:

```bash
flutter pub get
```

Or install it from the command line:

```bash
flutter pub add mangaloom_parser
```

## 🎯 Quick Start

### Import the package

```dart
import 'package:mangaloom_parser/mangaloom_parser.dart';
```

### Initialize a parser

```dart
// Using Shinigami Parser
final parser = ShinigamiParser();

// Or using ComicSans Parser
final parser = ComicSansParser();
```

### Fetch popular comics

```dart
try {
  final comics = await parser.fetchPopular();

  for (var comic in comics) {
    print('Title: ${comic.title}');
    print('Type: ${comic.type}');
    print('Rating: ${comic.rating}');
    print('Thumbnail: ${comic.thumbnail}');
  }
} catch (e) {
  print('Error: $e');
}
```

### Search for comics

```dart
try {
  final results = await parser.search('one piece');

  for (var comic in results) {
    print('${comic.title} - ${comic.href}');
  }
} catch (e) {
  print('Error: $e');
}
```

### Get comic details

```dart
try {
  final detail = await parser.fetchDetail('/comic-id/');

  print('Title: ${detail.title}');
  print('Alternative Title: ${detail.altTitle}');
  print('Description: ${detail.description}');
  print('Status: ${detail.status}');
  print('Type: ${detail.type}');
  print('Rating: ${detail.rating}');
  print('Author: ${detail.author}');

  // Genres
  for (var genre in detail.genres) {
    print('Genre: ${genre.title}');
  }

  // Chapters
  for (var chapter in detail.chapters) {
    print('${chapter.title} - ${chapter.date}');
  }
} catch (e) {
  print('Error: $e');
}
```

### Read a chapter

```dart
try {
  final chapter = await parser.fetchChapter('/chapter-id/');

  print('Title: ${chapter.title}');
  print('Images: ${chapter.panel.length}');

  // Display images
  for (var imageUrl in chapter.panel) {
    print('Image: $imageUrl');
  }

  // Navigation
  if (chapter.prev.isNotEmpty) {
    print('Previous chapter: ${chapter.prev}');
  }
  if (chapter.next.isNotEmpty) {
    print('Next chapter: ${chapter.next}');
  }
} catch (e) {
  print('Error: $e');
}
```

## 📚 Usage Examples

### Fetch with Pagination

```dart
// Fetch newest comics (page 1)
final page1 = await parser.fetchNewest(page: 1);

// Fetch page 2
final page2 = await parser.fetchNewest(page: 2);
```

### Browse by Genre

```dart
// Get all available genres
final genres = await parser.fetchGenres();

for (var genre in genres) {
  print('${genre.title} - ${genre.href}');
}

// Fetch comics by specific genre
final actionComics = await parser.fetchByGenre('action', page: 1);
```

### Advanced Filtering

```dart
// Filter comics with multiple criteria
final filtered = await parser.fetchFiltered(
  page: 1,
  genre: 'action',
  status: 'ongoing',
  type: 'manga',
  order: 'popular',
);
```

### Complete Example with Flutter

```dart
import 'package:flutter/material.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

class ComicListPage extends StatefulWidget {
  @override
  _ComicListPageState createState() => _ComicListPageState();
}

class _ComicListPageState extends State<ComicListPage> {
  final parser = ShinigamiParser();
  List<ComicItem> comics = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    loadComics();
  }

  @override
  void dispose() {
    parser.dispose(); // Don't forget to dispose!
    super.dispose();
  }

  Future<void> loadComics() async {
    setState(() => isLoading = true);

    try {
      final result = await parser.fetchPopular();
      setState(() {
        comics = result;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Popular Comics')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: comics.length,
              itemBuilder: (context, index) {
                final comic = comics[index];
                return ListTile(
                  leading: Image.network(comic.thumbnail),
                  title: Text(comic.title),
                  subtitle: Text('${comic.type} • ${comic.rating}⭐'),
                  onTap: () {
                    // Navigate to detail page
                  },
                );
              },
            ),
    );
  }
}
```

## 📖 API Reference

### ComicParser (Base Class)

All parsers implement these methods:

#### Properties

- `String sourceName` - Name of the comic source
- `String baseUrl` - Base URL of the source
- `String language` - Language code (e.g., "ID")

#### Methods

##### `Future<List<ComicItem>> fetchPopular()`

Fetch most popular comics.

##### `Future<List<ComicItem>> fetchRecommended()`

Fetch recommended comics.

##### `Future<List<ComicItem>> fetchNewest({int page = 1})`

Fetch newest comics with pagination.

##### `Future<List<ComicItem>> fetchAll({int page = 1})`

Fetch all comics with pagination.

##### `Future<List<ComicItem>> search(String query)`

Search comics by query string.

##### `Future<List<ComicItem>> fetchByGenre(String genre, {int page = 1})`

Fetch comics filtered by specific genre.

##### `Future<List<ComicItem>> fetchFiltered({int page, String? genre, String? status, String? type, String? order})`

Fetch comics with advanced filtering options.

##### `Future<List<Genre>> fetchGenres()`

Fetch list of available genres.

##### `Future<ComicDetail> fetchDetail(String href)`

Fetch detailed information about a comic.

##### `Future<ReadChapter> fetchChapter(String href)`

Fetch chapter images and navigation.

### Models

#### ComicItem

```dart
class ComicItem {
  final String title;
  final String href;
  final String thumbnail;
  final String? type;
  final String? chapter;
  final String? rating;
}
```

#### ComicDetail

```dart
class ComicDetail {
  final String href;
  final String title;
  final String altTitle;
  final String thumbnail;
  final String description;
  final String status;
  final String type;
  final String released;
  final String author;
  final String updatedOn;
  final String rating;
  final String? latestChapter;
  final List<Genre> genres;
  final List<Chapter> chapters;
}
```

#### Chapter

```dart
class Chapter {
  final String title;
  final String href;
  final String date;
}
```

#### ReadChapter

```dart
class ReadChapter {
  final String title;
  final String prev;
  final String next;
  final List<String> panel;
}
```

#### Genre

```dart
class Genre {
  final String title;
  final String href;
}
```

## ⚠️ Important Notes

### Memory Management

Always dispose the parser when you're done using it:

```dart
@override
void dispose() {
  parser.dispose();
  super.dispose();
}
```

### Error Handling

Always wrap API calls in try-catch blocks:

```dart
try {
  final comics = await parser.fetchPopular();
  // Handle success
} catch (e) {
  // Handle error
  print('Error: $e');
}
```

### Network Requirements

This package requires internet connection and uses HTTP requests. Make sure to add internet permission:

**Android** (`android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS** - No additional configuration needed.

## 🎨 Example App

Check out the [example](example/) directory for a complete Flutter app demonstrating all features:

- ✅ Multiple parser support with switcher
- ✅ All parser functions demonstration
- ✅ Search functionality
- ✅ Genre browsing
- ✅ Advanced filtering
- ✅ Comic detail view
- ✅ Chapter reader
- ✅ Pagination

Run the example:

```bash
cd example
flutter run
```

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Adding New Parsers

To add support for a new comic source:

1. Create a new parser class extending `ComicParser`
2. Implement all required methods
3. Add it to the exports in `lib/mangaloom_parser.dart`
4. Update the README with the new parser

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Thanks to all comic sources for providing content
- Inspired by the need for a unified comic parsing library
- Built with ❤️ using Flutter

## 📧 Contact

If you have any questions or suggestions, feel free to open an issue on GitHub.

---

Made with ❤️ by [ifqygazhar](https://github.com/ifqygazhar)
