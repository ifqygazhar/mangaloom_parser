# Quick Start Guide - Mangaloom Parser

## 🚀 Installation

```yaml
dependencies:
  mangaloom_parser: ^0.0.1
```

```bash
flutter pub get
```

## 📝 Basic Usage

### 1. Import

```dart
import 'package:mangaloom_parser/mangaloom_parser.dart';
```

### 2. Initialize

```dart
final parser = ShinigamiParser();
// or
final parser = ComicSansParser();
```

### 3. Fetch Data

```dart
// Popular comics
final comics = await parser.fetchPopular();

// Search
final results = await parser.search('naruto');

// Detail
final detail = await parser.fetchDetail('/comic-id/');

// Chapter
final chapter = await parser.fetchChapter('/chapter-id/');
```

### 4. Dispose

```dart
@override
void dispose() {
  parser.dispose();
  super.dispose();
}
```

## 🎯 Common Tasks

### Display Comic List

```dart
ListView.builder(
  itemCount: comics.length,
  itemBuilder: (context, index) {
    final comic = comics[index];
    return ListTile(
      leading: Image.network(comic.thumbnail),
      title: Text(comic.title),
      subtitle: Text(comic.type ?? ''),
      onTap: () {
        // Navigate to detail
      },
    );
  },
);
```

### Show Comic Detail

```dart
final detail = await parser.fetchDetail(comic.href);

// Access properties
detail.title
detail.description
detail.genres
detail.chapters
```

### Read Chapter

```dart
final chapter = await parser.fetchChapter(chapterHref);

// Display images
ListView.builder(
  itemCount: chapter.panel.length,
  itemBuilder: (context, index) {
    return Image.network(chapter.panel[index]);
  },
);
```

## 🔍 All Available Methods

```dart
// Fetch methods
parser.fetchPopular()
parser.fetchRecommended()
parser.fetchNewest(page: 1)
parser.fetchAll(page: 1)
parser.search('query')
parser.fetchByGenre('action', page: 1)
parser.fetchFiltered(
  page: 1,
  genre: 'action',
  status: 'ongoing',
  type: 'manga',
  order: 'popular',
)

// Browse methods
parser.fetchGenres()
parser.fetchDetail('/comic-href/')
parser.fetchChapter('/chapter-href/')
```

## ⚠️ Important

1. **Always dispose:** Call `parser.dispose()` when done
2. **Error handling:** Wrap calls in try-catch
3. **Network:** Add internet permission

## 📚 Full Documentation

See [README.md](README.md) for complete documentation.
