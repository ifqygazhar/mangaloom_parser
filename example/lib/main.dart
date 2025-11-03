import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mangaloom_parser/mangaloom_parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mangaloom Parser Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum ParserType { shinigami, comicsans, mangapark, webtoon, batoto, mangaplus }

enum TestFunction {
  popular,
  recommended,
  newest,
  all,
  search,
  genres,
  byGenre,
  filtered,
}

class _HomePageState extends State<HomePage> {
  late ComicParser parser;
  ParserType selectedParser = ParserType.shinigami;
  TestFunction selectedFunction = TestFunction.popular;

  List<ComicItem> comics = [];
  List<Genre> genres = [];
  bool isLoading = false;
  String errorMessage = '';
  int currentPage = 1;

  // Filter parameters
  String searchQuery = '';
  String? selectedGenre;
  String? selectedStatus;
  String? selectedType;
  String? selectedOrder;

  final subtitleParserSelection = {
    ParserType.shinigami: 'Shinigami - ID',
    ParserType.comicsans: 'ComicSans - ID',
    ParserType.mangapark: 'MangaPark - EN',
    ParserType.webtoon: 'Webtoon - ID',
    ParserType.batoto: 'Batoto - EN',
    ParserType.mangaplus: 'MangaPlus - ID',
  };

  @override
  void initState() {
    super.initState();
    _initializeParser();
    _loadData();
  }

  void _initializeParser() {
    if (selectedParser == ParserType.shinigami) {
      parser = ShinigamiParser();
    } else if (selectedParser == ParserType.comicsans) {
      parser = ComicSansParser();
    } else if (selectedParser == ParserType.mangapark) {
      parser = MangaParkParser();
    } else if (selectedParser == ParserType.batoto) {
      parser = BatotoParser();
    } else if (selectedParser == ParserType.mangaplus) {
      parser = MangaPlusParser();
    } else {
      parser = WebtoonParser();
    }
  }

  @override
  void dispose() {
    if (parser is ShinigamiParser) {
      (parser as ShinigamiParser).dispose();
    } else if (parser is ComicSansParser) {
      (parser as ComicSansParser).dispose();
    } else if (parser is MangaParkParser) {
      (parser as MangaParkParser).dispose();
    } else if (parser is WebtoonParser) {
      (parser as WebtoonParser).dispose();
    } else if (parser is BatotoParser) {
      (parser as BatotoParser).dispose();
    } else if (parser is MangaPlusParser) {
      (parser as MangaPlusParser).dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      comics = [];
      genres = [];
    });

    try {
      switch (selectedFunction) {
        case TestFunction.popular:
          final result = await parser.fetchPopular();
          setState(() => comics = result);
          break;

        case TestFunction.recommended:
          final result = await parser.fetchRecommended();
          setState(() => comics = result);
          break;

        case TestFunction.newest:
          final result = await parser.fetchNewest(page: currentPage);
          setState(() => comics = result);
          break;

        case TestFunction.all:
          final result = await parser.fetchAll(page: currentPage);
          setState(() => comics = result);
          break;

        case TestFunction.search:
          if (searchQuery.isEmpty) {
            setState(() => errorMessage = 'Please enter search query');
            return;
          }
          final result = await parser.search(searchQuery);
          setState(() => comics = result);
          break;

        case TestFunction.genres:
          final result = await parser.fetchGenres();

          setState(() => genres = result);
          break;

        case TestFunction.byGenre:
          if (selectedGenre == null) {
            setState(() => errorMessage = 'Please select a genre first');
            return;
          }
          final result = await parser.fetchByGenre(
            selectedGenre!,
            page: currentPage,
          );
          debugPrint(
            "Fetched ${result.length} comics for genre $selectedGenre",
          );
          setState(() => comics = result);
          break;

        case TestFunction.filtered:
          final result = await parser.fetchFiltered(
            page: currentPage,
            genre: selectedGenre,
            status: selectedStatus,
            type: selectedType,
            order: selectedOrder,
          );
          setState(() => comics = result);
          break;
      }

      setState(() => isLoading = false);
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  void _changeParser(ParserType newParser) {
    if (selectedParser == newParser) return;

    // Dispose old parser
    if (parser is ShinigamiParser) {
      (parser as ShinigamiParser).dispose();
    } else if (parser is ComicSansParser) {
      (parser as ComicSansParser).dispose();
    } else if (parser is MangaParkParser) {
      (parser as MangaParkParser).dispose();
    } else if (parser is WebtoonParser) {
      (parser as WebtoonParser).dispose();
    } else if (parser is BatotoParser) {
      (parser as BatotoParser).dispose();
    } else if (parser is MangaPlusParser) {
      (parser as MangaPlusParser).dispose();
    }

    setState(() {
      selectedParser = newParser;
      currentPage = 1;
      selectedGenre = null;
      selectedStatus = null;
      selectedType = null;
      selectedOrder = null;
    });

    _initializeParser();
    _loadData();
  }

  void _changeFunction(TestFunction newFunction) {
    setState(() {
      selectedFunction = newFunction;
      currentPage = 1;
    });
    _loadData();
  }

  void _navigateToDetail(ComicItem comic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailPage(parser: parser, comicHref: comic.href),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: $errorMessage', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (selectedFunction == TestFunction.genres) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: genres.length,
        itemBuilder: (context, index) {
          final genre = genres[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(genre.title[0].toUpperCase())),
              title: Text(genre.title),
              subtitle: Text(genre.href),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                setState(() {
                  selectedGenre = genre.href.replaceAll('/', '');
                  selectedFunction = TestFunction.byGenre;
                  currentPage = 1;
                });
                _loadData();
              },
            ),
          );
        },
      );
    }

    if (comics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No comics found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: comics.length,
      itemBuilder: (context, index) {
        final comic = comics[index];
        return ComicCard(comic: comic, onTap: () => _navigateToDetail(comic));
      },
    );
  }

  void _showFiltersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              // Genre selector
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: selectedGenre,
                      decoration: const InputDecoration(
                        labelText: 'Genre',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                      onChanged: (value) =>
                          selectedGenre = value.isEmpty ? null : value,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.list),
                    onPressed: () async {
                      final genresList = await parser.fetchGenres();
                      if (!mounted) return;
                      final selected = await showDialog<String>(
                        context: context,
                        builder: (context) =>
                            GenreListDialog(genres: genresList),
                      );
                      if (selected != null) {
                        setState(() => selectedGenre = selected);
                        Navigator.pop(context);
                      }
                    },
                    tooltip: 'Select from list',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.info_outline),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Status')),
                  DropdownMenuItem(value: 'ongoing', child: Text('Ongoing')),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(value: 'hiatus', child: Text('Hiatus')),
                ],
                onChanged: (value) => setState(() => selectedStatus = value),
              ),
              const SizedBox(height: 16),

              // Type
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.book),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Types')),
                  DropdownMenuItem(value: 'manga', child: Text('Manga')),
                  DropdownMenuItem(value: 'manhwa', child: Text('Manhwa')),
                  DropdownMenuItem(value: 'manhua', child: Text('Manhua')),
                ],
                onChanged: (value) => setState(() => selectedType = value),
              ),
              const SizedBox(height: 16),

              // Order
              DropdownButtonFormField<String>(
                initialValue: selectedOrder,
                decoration: const InputDecoration(
                  labelText: 'Sort Order',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.sort),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Default')),
                  DropdownMenuItem(value: 'popular', child: Text('Popular')),
                  DropdownMenuItem(value: 'latest', child: Text('Latest')),
                  DropdownMenuItem(value: 'rating', child: Text('Rating')),
                ],
                onChanged: (value) => setState(() => selectedOrder = value),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          selectedGenre = null;
                          selectedStatus = null;
                          selectedType = null;
                          selectedOrder = null;
                        });
                      },
                      child: const Text('Clear All'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _loadData();
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mangaloom Parser'),
            Text(
              '${parser.sourceName} - ${selectedFunction.name}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (selectedFunction == TestFunction.search)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Search'),
                    content: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Enter search query...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        searchQuery = value;
                        Navigator.pop(context);
                        _loadData();
                      },
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Search',
            ),
          if (selectedFunction == TestFunction.filtered ||
              selectedFunction == TestFunction.byGenre)
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showFiltersBottomSheet,
              tooltip: 'Filters',
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'refresh') {
                _loadData();
              } else if (value == 'reset') {
                setState(() {
                  currentPage = 1;
                  selectedGenre = null;
                  selectedStatus = null;
                  selectedType = null;
                  selectedOrder = null;
                  searchQuery = '';
                });
                _loadData();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              const PopupMenuItem(value: 'reset', child: Text('Reset Filters')),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inversePrimary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Mangaloom Parser',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Test all parser functions',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),

            // Parser Selection
            ExpansionTile(
              leading: const Icon(Icons.cloud),
              title: const Text('Parser'),
              subtitle: Text(parser.sourceName),
              children: ParserType.values.map((type) {
                return RadioListTile<ParserType>(
                  title: Text(type.name.toUpperCase()),
                  subtitle: Text(subtitleParserSelection[type] ?? ''),
                  value: type,
                  groupValue: selectedParser,
                  onChanged: (value) {
                    if (value != null) {
                      _changeParser(value);
                      Navigator.pop(context);
                    }
                  },
                );
              }).toList(),
            ),

            const Divider(),

            // Function Selection
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'FUNCTIONS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ),

            _buildDrawerItem(
              icon: Icons.trending_up,
              title: 'Popular',
              subtitle: 'Most popular comics',
              function: TestFunction.popular,
            ),
            _buildDrawerItem(
              icon: Icons.recommend,
              title: 'Recommended',
              subtitle: 'Recommended for you',
              function: TestFunction.recommended,
            ),
            _buildDrawerItem(
              icon: Icons.fiber_new,
              title: 'Newest',
              subtitle: 'Latest releases',
              function: TestFunction.newest,
            ),
            _buildDrawerItem(
              icon: Icons.apps,
              title: 'All Comics',
              subtitle: 'Browse all',
              function: TestFunction.all,
            ),
            _buildDrawerItem(
              icon: Icons.search,
              title: 'Search',
              subtitle: 'Find specific comics',
              function: TestFunction.search,
            ),
            _buildDrawerItem(
              icon: Icons.category,
              title: 'Genres',
              subtitle: 'View all genres',
              function: TestFunction.genres,
            ),
            _buildDrawerItem(
              icon: Icons.label,
              title: 'By Genre',
              subtitle: 'Filter by genre',
              function: TestFunction.byGenre,
            ),
            _buildDrawerItem(
              icon: Icons.filter_alt,
              title: 'Advanced Filter',
              subtitle: 'Custom filters',
              function: TestFunction.filtered,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Status bar with quick info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedFunction.name.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _getFunctionDescription(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                if (_showPaginationControls())
                  Chip(
                    avatar: const Icon(Icons.pages, size: 16),
                    label: Text('Page $currentPage'),
                    backgroundColor: Colors.blue[50],
                  ),
              ],
            ),
          ),

          Expanded(child: _buildContent()),

          // Bottom navigation for pagination
          if (_showPaginationControls())
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.3),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: currentPage > 1
                          ? () {
                              setState(() => currentPage--);
                              _loadData();
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Previous'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      '$currentPage',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => currentPage++);
                        _loadData();
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required TestFunction function,
  }) {
    final isSelected = selectedFunction == function;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.blue : null,
        ),
      ),
      subtitle: Text(subtitle),
      selected: isSelected,
      onTap: () {
        _changeFunction(function);
        Navigator.pop(context);
      },
    );
  }

  String _getFunctionDescription() {
    switch (selectedFunction) {
      case TestFunction.popular:
        return 'Showing most popular comics';
      case TestFunction.recommended:
        return 'Showing recommended comics';
      case TestFunction.newest:
        return 'Showing newest releases';
      case TestFunction.all:
        return 'Showing all comics';
      case TestFunction.search:
        return 'Search for specific comics';
      case TestFunction.genres:
        return 'Browse by genre';
      case TestFunction.byGenre:
        return selectedGenre != null
            ? 'Filtered by: $selectedGenre'
            : 'Select a genre';
      case TestFunction.filtered:
        return 'Custom filtered results';
    }
  }

  bool _showPaginationControls() {
    return selectedFunction == TestFunction.newest ||
        selectedFunction == TestFunction.all ||
        selectedFunction == TestFunction.byGenre ||
        selectedFunction == TestFunction.filtered;
  }

  Widget? _buildFloatingActionButton() {
    if (selectedFunction == TestFunction.search) {
      return FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Search Comics'),
              content: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Enter search query...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (value) {
                  searchQuery = value;
                  Navigator.pop(context);
                  _loadData();
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.search),
        label: const Text('Search'),
      );
    }

    if (selectedFunction == TestFunction.filtered ||
        selectedFunction == TestFunction.byGenre) {
      return FloatingActionButton.extended(
        onPressed: _showFiltersBottomSheet,
        icon: const Icon(Icons.filter_list),
        label: const Text('Filters'),
      );
    }

    return null;
  }
}

class ComicCard extends StatelessWidget {
  final ComicItem comic;
  final VoidCallback onTap;

  const ComicCard({super.key, required this.comic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    debugPrint("ComicImage URL: ${comic.thumbnail}");
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Image.network(
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
                  'Referer': "https://www.webtoons.com/id/",
                },
                comic.thumbnail,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comic.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (comic.type != null)
                    Text(
                      comic.type!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  if (comic.rating != null)
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          comic.rating!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GenreListDialog extends StatelessWidget {
  final List<Genre> genres;

  const GenreListDialog({super.key, required this.genres});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Genre'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: genres.length,
          itemBuilder: (context, index) {
            final genre = genres[index];
            return ListTile(
              title: Text(genre.title),
              onTap: () {
                Navigator.pop(context, genre.href.replaceAll('/', ''));
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class DetailPage extends StatelessWidget {
  final ComicParser parser;
  final String comicHref;

  const DetailPage({super.key, required this.parser, required this.comicHref});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comic Detail')),
      body: FutureBuilder<ComicDetail>(
        future: parser.fetchDetail(comicHref),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('Error fetching detail: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                ],
              ),
            );
          }

          final detail = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Thumbnail
              if (detail.thumbnail.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      detail.thumbnail,
                      height: 300,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 300,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image, size: 48),
                        );
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Title
              Text(
                detail.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Alt Title
              if (detail.altTitle.isNotEmpty)
                Text(
                  detail.altTitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 16),

              // Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Type', detail.type),
                      _buildInfoRow('Status', detail.status),
                      _buildInfoRow('Rating', '${detail.rating} ⭐'),
                      if (detail.author.isNotEmpty)
                        _buildInfoRow('Author', detail.author),
                      if (detail.released.isNotEmpty)
                        _buildInfoRow('Released', detail.released),
                      if (detail.updatedOn.isNotEmpty)
                        _buildInfoRow('Updated', detail.updatedOn),
                      if (detail.latestChapter != null)
                        _buildInfoRow('Latest', detail.latestChapter!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Genres
              if (detail.genres.isNotEmpty) ...[
                const Text(
                  'Genres:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detail.genres.map((genre) {
                    return Chip(
                      label: Text(genre.title),
                      backgroundColor: Colors.blue[100],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Description
              if (detail.description.isNotEmpty) ...[
                const Text(
                  'Description:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(detail.description),
                const SizedBox(height: 16),
              ],

              // Chapters
              const Text(
                'Chapters:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '${detail.chapters.length} chapters available',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              ...detail.chapters.map((chapter) {
                return Card(
                  child: ListTile(
                    title: Text(chapter.title),
                    subtitle: chapter.date.isNotEmpty
                        ? Text(chapter.date)
                        : null,
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChapterReaderPage(
                            parser: parser,
                            chapterHref: chapter.href,
                            chapterTitle: chapter.title,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class ChapterReaderPage extends StatefulWidget {
  final ComicParser parser;
  final String chapterHref;
  final String chapterTitle;

  const ChapterReaderPage({
    super.key,
    required this.parser,
    required this.chapterHref,
    required this.chapterTitle,
  });

  @override
  State<ChapterReaderPage> createState() => _ChapterReaderPageState();
}

class _ChapterReaderPageState extends State<ChapterReaderPage> {
  late Future<ReadChapter> _chapterFuture;
  ReadChapter? _currentChapter;

  @override
  void initState() {
    super.initState();
    _loadChapter(widget.chapterHref);
  }

  void _loadChapter(String href) {
    setState(() {
      _chapterFuture = widget.parser.fetchChapter(href);
    });
  }

  void _navigateToChapter(String href) {
    if (href.isEmpty) return;
    _loadChapter(href);
  }

  /// Build MangaPlus encrypted image widget
  Widget _buildMangaPlusImage(
    String imageUrlWithKey,
    MangaPlusParser parser,
    int index,
  ) {
    return FutureBuilder<Uint8List>(
      future: parser.fetchImage(imageUrlWithKey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(32.0),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Decoding image...'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint('MangaPlus image error: ${snapshot.error}');
          return Container(
            height: 200,
            color: Colors.grey[300],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Text('Failed to load image ${index + 1}'),
                const SizedBox(height: 4),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return Container(
            height: 200,
            color: Colors.grey[300],
            child: const Center(
              child: Icon(Icons.image_not_supported, size: 48),
            ),
          );
        }

        // Display decoded image
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Image.memory error: $error');
              return Container(
                height: 200,
                color: Colors.grey[300],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image, size: 48),
                    const SizedBox(height: 8),
                    Text('Failed to render image ${index + 1}'),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chapterTitle)),
      body: FutureBuilder<ReadChapter>(
        future: _chapterFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                ],
              ),
            );
          }

          _currentChapter = snapshot.data!;
          final chapter = _currentChapter!;

          return Column(
            children: [
              // Navigation Bar
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: chapter.prev.isNotEmpty
                          ? () => _navigateToChapter(chapter.prev)
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Previous'),
                    ),
                    Text(
                      '${chapter.panel.length} images',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: chapter.next.isNotEmpty
                          ? () => _navigateToChapter(chapter.next)
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              ),

              // Images List
              Expanded(
                child: ListView.builder(
                  itemCount: chapter.panel.length,
                  itemBuilder: (context, index) {
                    final imageUrl = chapter.panel[index];
                    debugPrint("chapter image URL: $imageUrl");

                    // Check if this is MangaPlus encrypted image
                    if (widget.parser is MangaPlusParser &&
                        imageUrl.contains('#')) {
                      return _buildMangaPlusImage(
                        imageUrl,
                        widget.parser as MangaPlusParser,
                        index,
                      );
                    }

                    // Regular image loading for other parsers
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Image.network(
                        headers: {
                          'User-Agent':
                              'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
                          'Referer': "https://www.webtoons.com/id/",
                        },
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.grey[300],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.broken_image, size: 48),
                                const SizedBox(height: 8),
                                Text('Failed to load image ${index + 1}'),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),

              // Bottom Navigation
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: chapter.prev.isNotEmpty
                          ? () => _navigateToChapter(chapter.prev)
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Previous'),
                    ),
                    ElevatedButton.icon(
                      onPressed: chapter.next.isNotEmpty
                          ? () => _navigateToChapter(chapter.next)
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
