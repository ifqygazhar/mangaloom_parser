# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.5] - 2025-10-20

### Added

- 🎨 BatotoParser - New parser for Batoto (ato.to) English comic source
- 🌐 Support for English language manga from Batoto
- 🔐 AES encryption support for chapter image decryption
- 📜 JavaScript runtime integration using flutter_js for dynamic content
- 🎯 Advanced genre filtering and browsing
- 📊 Multiple sorting options (popular, newest, updated, alphabetical)
- 🔍 Full-text search functionality
- 📄 Pagination support for all list views
- 🎨 Genre caching for improved performance

### Features

- 🔓 **AES Decryption**: Custom implementation for decrypting encrypted image URLs
  - MD5-based key and IV generation
  - OpenSSL-compatible decryption using EVP_BytesToKey
  - Support for Salted\_\_ prefix format
- 🚀 **JavaScript Evaluation**: Runtime JS execution for dynamic password generation
- 📱 **Comprehensive API**:
  - `fetchPopular()` - Get most popular manga (all-time views)
  - `fetchRecommended()` - Get weekly popular manga
  - `fetchNewest({page})` - Get newest releases with pagination
  - `fetchAll({page})` - Get all manga sorted by latest updates
  - `search(query)` - Full-text search
  - `fetchByGenre(genre, {page})` - Browse by genre with pagination
  - `fetchFiltered({page, genre, status, order})` - Advanced filtering
  - `fetchGenres()` - Get all available genres with caching
  - `fetchDetail(href)` - Get detailed manga information
  - `fetchChapter(href)` - Get chapter images with navigation
- 🧭 **Chapter Navigation**: Proper prev/next chapter detection from HTML structure
- 📋 **Rich Metadata**: Extract authors, status, genres, descriptions, and chapters

### Fixed

- 🐛 Fixed pagination validation for first page with "1 ..." format
- ✅ Corrected genre parsing from JavaScript object structure
- 🔧 Fixed chapter navigation to exclude "Detail" links
- 🎯 Improved page results detection for edge cases
- 📖 Fixed chapter date parsing for various time formats (seconds, minutes, hours, days, weeks, months, years)
- 🖼️ Enhanced image URL extraction with proper query parameter handling

### Technical Details

- 📦 Dependencies: `crypto`, `encrypt`, `flutter_js` for advanced features
- 🔒 Security: Implements OpenSSL-compatible AES-256-CBC decryption
- ⚡ Performance: Genre caching to minimize network requests
- 🎨 Code Quality: Comprehensive error handling with descriptive messages
- 🧪 Compatibility: Works with Batoto's dynamic JavaScript-based content delivery

### Changed

- 🔄 Updated fetchNewest and fetchAll to handle pagination correctly
- ⚡ Improved genre fetching with JSON parsing from embedded scripts
- 🎨 Better error messages for debugging pagination issues
- 🔧 Enhanced chapter navigation with multiple fallback selectors

## [0.0.2] - 2025-10-16

### Added

- 🎨 WebtoonParser - New parser for Webtoons Indonesia comic source
- 🌐 Support for Webtoons.com Indonesian language content
- 📱 Mobile API integration for episode data
- 🔗 Viewer link caching for improved performance

### Fixed

- 🐛 Fixed 500 error when fetching chapter images in WebtoonParser
- ✅ Corrected viewer URL construction using API episode data
- 🔧 Fixed image extraction with proper data-url priority
- 🎯 Improved headers for viewer page requests with proper Referer
- 📖 Fixed chapter navigation using episode sequence data
- 🖼️ Enhanced image filtering to only include static domain resources

### Changed

- 🔄 Updated WebtoonParser to use viewerLink from episode API
- ⚡ Improved chapter fetching with enhanced headers
- 🎨 Better error messages with URL information for debugging

## [0.0.1] - 2025-10-16

### Added

- 🎉 Initial release of Mangaloom Parser
- ✨ Support for multiple comic parsers
- 📚 ShinigamiParser - Parse Shinigami comic source
- 🎨 ComicSansParser - Parse CosmicScans comic source
- 🔥 Fetch popular comics
- 🆕 Fetch newest releases with pagination
- 💡 Fetch recommended comics
- 🔍 Search functionality
- 🎯 Genre browsing and filtering
- 🎛️ Advanced filtering (status, type, order)
- 📖 Fetch comic details (title, description, genres, chapters)
- 📚 Fetch chapter images for reading
- ⏭️ Chapter navigation (previous/next)
- 📄 Pagination support for list views
- 🌐 Indonesian language support
- 📱 Complete example Flutter app
- 📖 Comprehensive documentation

### Features

- Base `ComicParser` class for easy extension
- Clean and intuitive API design
- Error handling with descriptive exceptions
- Memory management with dispose methods
- Type-safe models (ComicItem, ComicDetail, Chapter, ReadChapter, Genre)
- HTTP client management
- HTML parsing support

### Example App Features

- 🎨 Modern Material 3 UI design
- 📱 Drawer navigation
- 🔄 Parser switcher (Shinigami/ComicSans)
- 🎛️ Bottom sheet filters
- 🔍 Search dialog
- 📄 Pagination controls
- 📖 Comic detail viewer
- 📚 Chapter reader with image loading
- ⚡ Quick actions with FAB
- 🎯 Status bar with function info

### Documentation

- ✅ Complete README with installation guide
- ✅ Quick start examples
- ✅ API reference
- ✅ Usage examples for all features
- ✅ Flutter integration examples
- ✅ Error handling guidelines
- ✅ Contributing guidelines

[0.0.5]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.5
[0.0.2]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.2
[0.0.1]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.1
