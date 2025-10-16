# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.0.1]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.1
