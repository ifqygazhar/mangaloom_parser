# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3] - 2025-11-28

### Fixed

- 🐛 **Chapter Title Formatting** - Chapters now include the manga title prefix across parsers:
  - Format: "Title - Chapter" (applied to Shinigami, ComicSans, MangaPark, Webtoon, Batoto)
- 🐛 **Komiklu Chapter Scraping** - Fixed chapter extraction for new structure where <a> wraps <li>
  - Correctly reads href from the <a> and extracts chapter name from inner elements
- 🐛 **Chapter Order Normalization** - Ensure newest chapters appear at the top (index 0) for all parsers
  - Adjusted per-source logic to avoid double-reversing when the site already provides newest-first
- 🐛 **Removed Debug Prints & Cleaned Comments** - Removed development print statements and unnecessary inline comments across parser files for a more professional codebase
- 🐛 **Komiklu Lazy Images** - Confirmed support for `data-src` (lazy loading) and `src` fallback (already addressed in 0.1.2, reiterated)
- 🐛 **Selector Compatibility** - Replaced jQuery-style selectors (e.g. `:contains`) with robust standard-CSS + text-matching fallbacks

### Changed

- ♻️ **Code Quality** - Cleaned up parser files by removing noisy comments and debug output
- 🔄 **Consistent Chapter UI** - Unified chapter title presentation in UI/readers across supported sources
- 📝 **Documentation/README** - Added banner and Google Play download button to README

### Notes

- Per-source behavior is preserved: when a site already provides newest-first ordering, no reversal is applied.
- Batoto flag code prefix remains in place (e.g., "ID - Title") as part of title enhancements.

## [0.1.2] - 2025-11-12

### Fixed

- 🐛 **KomikluParser Image Loading** - Fixed "No images found in chapter" error
  - Added support for lazy loading images using `data-src` attribute
  - Parser now checks `data-src` first, then falls back to `src` attribute
  - Resolves issue with Komiklu's IntersectionObserver-based lazy loading
  - Chapter images now load correctly from `div#viewer img.webtoon-img`

### Technical Details

- 🔧 Enhanced image selector to handle both lazy loading and direct loading scenarios
- 📸 Image extraction priority: `data-src` → `src` → skip if empty
- 🎯 Compatible with Komiklu's progressive image loading implementation

## [0.1.0] - 2025-11-03

### Added

- 🎨 **KomikluParser** - New parser for Komiklu (v2.komiklu.com) Indonesian comic source
- 🌐 Full support for Komiklu v2 with AJAX-based filtering
- 🔍 JSON API integration for search functionality
- 📊 Multiple sorting options (rating-desc, newest, year-desc)
- 🎯 Advanced genre filtering with 24 available genres
- 📄 Pagination support for browse all comics
- 🏷️ **Flag Code Display** - BatotoParser now shows language codes in titles (e.g., "ID - Title")
- ⚡ **Cache System** - Implemented 5-minute cache for all parsers:
  - ShinigamiParser with cache infrastructure
  - ComicSansParser with cache support
  - BatotoParser with cached genre and list operations
  - MangaParkParser with cache management
  - KomikluParser with comprehensive caching
- 🚀 **Batch Operations** - Efficient concurrent data fetching:
  - `fetchMultipleLists()` - Fetch multiple list types at once
  - `fetchMultipleGenres()` - Batch genre fetching with concurrency limits (max 3)
- 🎨 **MangaPlus Encrypted Images** - Support for rendering XOR-encrypted chapter images
  - Automatic detection of encrypted images (URL contains '#')
  - FutureBuilder integration for async decryption
  - XOR cipher decryption with hex keys

### Features

- 📱 **KomikluParser API**:
  - `fetchPopular()` - Most popular by rating
  - `fetchRecommended()` - Newest releases
  - `fetchNewest({page})` - Sorted by year (AJAX, no pagination)
  - `fetchAll({page})` - All comics with page.php pagination
  - `search(query)` - JSON API search with detailed results
  - `fetchByGenre(genre, {page})` - Filter by genre (AJAX)
  - `fetchFiltered({page, genre, order})` - Combined filtering
  - `fetchGenres()` - Hardcoded 24 genres list
  - `fetchDetail(href)` - Comic details with robust parsing
  - `fetchChapter(href)` - Chapter reader with navigation
  - `fetchMultipleLists()` - Batch fetch popular/recommended/newest
  - `fetchMultipleGenres()` - Concurrent genre fetching
- 🔧 **Cache Management**:
  - `clearCache()` - Clear all caches
  - `clearListCache()` - Clear only list caches
  - Automatic cache expiry (5 minutes)
  - Cache validation with timestamp checking
- 🎨 **Enhanced Parsers**:
  - Flag code detection in BatotoParser (from `data-lang` attribute)
  - MangaPlus encrypted image rendering in example app
  - Improved URL normalization across all parsers

### Fixed

- 🐛 **KomikluParser URL Handling**:
  - Fixed `fetchDetail` to handle hrefs with or without leading slash
  - Corrected relative URL normalization
  - Fixed href construction to match Golang service behavior
- 🔧 **CSS Selector Compatibility**:
  - Replaced jQuery-style `:contains()` with standard CSS + manual text matching
  - Fixed chapter navigation detection (Previous/Next buttons)
  - Enhanced link parsing with proper fallback logic
- ✅ **Path Normalization**:
  - Improved `_toAbsoluteUrl` to handle "comic_detail.php?title=X" format
  - Enhanced `_toRelativeUrl` to ensure leading slashes
  - Fixed query string preservation in URLs
- 🖼️ **Image Handling**:
  - Fixed MangaPlus encrypted image detection
  - Corrected Uint8List import for binary data
  - Enhanced error states in image loading

### Changed

- 🔄 Updated all parsers to use consistent cache infrastructure
- ⚡ Improved concurrent request handling with limits
- 🎨 Enhanced error messages with detailed context
- 🔧 Standardized URL handling across all parsers
- 📖 Better chapter navigation with multiple selector fallbacks
- 🎯 Optimized genre fetching with caching strategies

### Technical Details

- 📦 **Cache Implementation**: Map-based with timestamp validation
- 🔒 **Concurrency Control**: Max 3 concurrent requests for batch operations
- ⚡ **Performance**: 5-minute cache expiry balances freshness and efficiency
- 🎨 **Code Quality**: Consistent patterns across all parser implementations
- 🧪 **Compatibility**:
  - Standard CSS selectors (no jQuery extensions)
  - Proper handling of relative/absolute URLs
  - Query string preservation in href parsing
- 🔐 **Security**: XOR cipher for MangaPlus image decryption

### Notes

- KomikluParser uses dual parsing methods:
  - `_parseComicListFromArticles()` for AJAX responses
  - `_parseComicListFromPage()` for page.php with different structure
- Search API returns JSON with rich metadata (author, year, genres, status)
- Genre list is hardcoded (24 genres) as per site structure
- AJAX endpoints don't support pagination (always return full results)
- Flag codes displayed in uppercase (e.g., "ID", "EN", "JP")

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

[0.1.0]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.1.0
[0.0.5]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.5
[0.0.2]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.2
[0.0.1]: https://github.com/ifqygazhar/mangaloom_parser/releases/tag/v0.0.1
