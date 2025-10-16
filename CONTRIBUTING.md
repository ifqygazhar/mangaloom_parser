# Contributing to Mangaloom Parser

First off, thank you for considering contributing to Mangaloom Parser! 🎉

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (code snippets, screenshots)
- **Describe the behavior you observed** and what you expected
- **Include your environment details** (Flutter version, Dart version, OS)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion:

- **Use a clear and descriptive title**
- **Provide a detailed description** of the suggested enhancement
- **Explain why this enhancement would be useful**
- **List any alternative solutions** you've considered

### Pull Requests

1. Fork the repo and create your branch from `main`
2. If you've added code that should be tested, add tests
3. Ensure the test suite passes
4. Make sure your code follows the existing style
5. Write a clear commit message

## Development Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/ifqygazhar/mangaloom_parser.git
   cd mangaloom_parser
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Run the example app**

   ```bash
   cd example
   flutter run
   ```

4. **Run tests**
   ```bash
   flutter test
   ```

## Adding a New Parser

To add support for a new comic source:

1. **Create a new parser file** in `lib/src/parsers/[language]/`

   ```dart
   // Example: lib/src/parsers/id/newsite_parser.dart

   import 'package:http/http.dart' as http;
   import 'package:mangaloom_parser/mangaloom_parser.dart';

   class NewSiteParser extends ComicParser {
     static const String _baseUrl = 'https://example.com';

     final http.Client _client;

     NewSiteParser({http.Client? client})
         : _client = client ?? http.Client();

     @override
     String get sourceName => 'NewSite';

     @override
     String get baseUrl => _baseUrl;

     @override
     String get language => 'ID';

     // Implement all required methods...

     void dispose() {
       _client.close();
     }
   }
   ```

2. **Implement all required methods**

   - `fetchPopular()`
   - `fetchRecommended()`
   - `fetchNewest({int page})`
   - `fetchAll({int page})`
   - `search(String query)`
   - `fetchByGenre(String genre, {int page})`
   - `fetchFiltered({...})`
   - `fetchGenres()`
   - `fetchDetail(String href)`
   - `fetchChapter(String href)`

3. **Export the parser** in `lib/mangaloom_parser.dart`

   ```dart
   export 'src/parsers/id/newsite_parser.dart';
   ```

4. **Update the README** with the new parser in the supported parsers table

5. **Add the parser to the example app** in `example/lib/main.dart`

## Code Style

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions small and focused
- Use proper error handling with try-catch

## Testing Guidelines

- Write tests for new features
- Ensure all tests pass before submitting PR
- Test on multiple devices/platforms if possible
- Include edge cases in your tests

## Commit Message Guidelines

Use clear and meaningful commit messages:

- `feat: Add support for NewSite parser`
- `fix: Fix chapter navigation in ComicSans parser`
- `docs: Update README with new examples`
- `style: Format code according to style guide`
- `refactor: Simplify fetchDetail method`
- `test: Add tests for search functionality`

## Documentation

- Update README.md for new features
- Add inline documentation for public APIs
- Include examples for new functionality
- Keep the changelog up to date

## Questions?

Feel free to open an issue with the `question` label if you have any questions about contributing.

## Code of Conduct

Be respectful and inclusive. We're all here to build something great together! 🚀

---

Thank you for contributing to Mangaloom Parser! ❤️
