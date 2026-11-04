import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/widgets/cached_remote_image.dart';

import 'package:yoaron_app/widgets/safe_bottom_sheet.dart';
import '../services/inventory_search.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  File? _searchImage;
  final ImagePicker _picker = ImagePicker();
  bool _isSearching = false;
  bool _usedFallback = false;
  bool _filtersExpanded = true;
  List<dynamic> _searchResults = [];
  Map<String, dynamic>? _aiCriteria; // Stores what the AI was looking for
  String _selectedCategory = 'Minden';
  String _selectedGender = 'Minden';
  String _selectedLocation = 'All locations';
  String _selectedSize = '';
  String _selectedColor = '';
  String _selectedPattern = '';
  String _selectedName = '';
  String _selectedBrand = '';
  String _selectedCondition = '';
  bool _categoryManuallyChanged = false;
  bool _genderManuallyChanged = false;
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _patternController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();
  static const _locations = ['All locations', 'Csengery', 'Astoria'];

  @override
  void dispose() {
    _colorController.dispose();
    _patternController.dispose();
    _sizeController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  Future<String?> _chooseCategory() async {
    var matchingCategories = filterCategories;

    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Search category'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Type a category, e.g. hoo',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      matchingCategories = filterCategories
                          .where(
                            (category) => category.toLowerCase().contains(
                              value.trim().toLowerCase(),
                            ),
                          )
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: matchingCategories.isEmpty
                      ? const Center(child: Text('No matching categories'))
                      : ListView.builder(
                          itemCount: matchingCategories.length,
                          itemBuilder: (context, index) {
                            final category = matchingCategories[index];
                            return ListTile(
                              title: Text(category),
                              selected: category == _selectedCategory,
                              onTap: () =>
                                  Navigator.pop(dialogContext, category),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return selection;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (pickedFile != null) {
        setState(() {
          _searchImage = File(pickedFile.path);
          _searchResults = []; // Clear old results
          _aiCriteria = null;
          _usedFallback = false;
          _selectedCategory = 'Minden';
          _selectedGender = 'Minden';
          _selectedColor = '';
          _selectedPattern = '';
          _selectedName = '';
          _selectedBrand = '';
          _selectedCondition = '';
          _categoryManuallyChanged = false;
          _genderManuallyChanged = false;
          _colorController.clear();
          _patternController.clear();
          _nameController.clear();
          _brandController.clear();
          _conditionController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _executeSearch() async {
    if (_isSearching) return;
    if (_searchImage == null) {
      await _searchInventory();
      return;
    }
    if (_aiCriteria != null) {
      await _searchInventory();
      return;
    }

    setState(() => _isSearching = true);
    try {
      final imageBytes = await _searchImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final response = await Supabase.instance.client.functions.invoke(
        'gemini-vision',
        body: {
          'task': 'search',
          'imageBase64': base64Image,
          'mimeType': 'image/jpeg',
        },
      );

      if (response.status != 200) {
        throw Exception('Image analysis failed: ${response.data}');
      }
      final aiResult = Map<String, dynamic>.from(response.data as Map);
      final category = _normalizeOption(
        aiResult['category'],
        clothingCategories,
      );
      final aiGender = _normalizeGender(aiResult['gender']);
      final gender = aiGender.isNotEmpty
          ? aiGender
          : _normalizeGender(aiResult['category']);
      final color = aiResult['color']?.toString() ?? '';
      final pattern = aiResult['pattern']?.toString() ?? '';
      final brand = aiResult['brand']?.toString() ?? '';

      if (!mounted) return;
      setState(() {
        _aiCriteria = aiResult;
        if (!_categoryManuallyChanged) {
          _selectedCategory = category.isEmpty ? 'Minden' : category;
        }
        if (!_genderManuallyChanged) {
          _selectedGender = genderOptions.contains(gender) ? gender : 'Minden';
        }
        _selectedColor = color;
        _selectedPattern = pattern;
        _selectedBrand = brand;
        _colorController.text = color;
        _patternController.text = pattern;
        _brandController.text = brand;
        // Let the database search start after analysis has completed.
        _isSearching = false;
      });
      await _searchInventory();
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Keresési hiba: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _normalizeOption(dynamic value, Iterable<String> options) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return '';
    for (final option in options) {
      if (option.toLowerCase() == normalized) return option;
    }
    return '';
  }

  String _normalizeGender(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return '';
    final matchingOption = _normalizeOption(normalized, genderOptions);
    if (matchingOption.isNotEmpty) return matchingOption;
    if (const {'female', 'woman', 'women'}.contains(normalized)) return 'női';
    if (const {'male', 'man', 'men'}.contains(normalized)) return 'férfi';
    return '';
  }

  Future<void> _searchInventory() async {
    if (_isSearching) return;
    setState(() {
      _isSearching = true;
      _usedFallback = false;
    });
    try {
      var results = await _runInventoryQuery();
      var usedFallback = false;
      if (results.isEmpty) {
        // Retry broadly, retaining only the main category, location, and a
        // known or manually entered brand.
        if (!mounted) return;
        setState(() {
          _selectedGender = 'Minden';
          _selectedSize = '';
          _selectedColor = '';
          _selectedPattern = '';
          _selectedName = '';
          _selectedCondition = '';
          _sizeController.clear();
          _colorController.clear();
          _patternController.clear();
          _nameController.clear();
          _conditionController.clear();
        });
        results = await _runInventoryQuery(fallback: true);
        usedFallback = true;
      }
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _usedFallback = usedFallback;
        _isSearching = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Keresési hiba: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<dynamic>> _runInventoryQuery({bool fallback = false}) async {
    return InventorySearch.search(
      InventorySearchCriteria(
        category: _selectedCategory,
        gender: _selectedGender,
        location: _selectedLocation,
        size: _selectedSize,
        brand: _selectedBrand,
        color: _selectedColor,
        pattern: _selectedPattern,
        name: _selectedName,
        condition: _selectedCondition,
        onlyUnsold: true,
        fallback: fallback,
      ),
    );
  }

  void _showItemDetails(Map<String, dynamic> item) {
    showSafeBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['name'] ?? 'Ismeretlen Termék',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            item['brand'] ?? 'Ismeretlen Márka',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const Divider(height: 30),

          _buildDetailRow(
            'Ár (Price):',
            '${item['price_est']} Ft',
            isHighlight: true,
          ),
          _buildDetailRow('Kategória:', item['category'] ?? '-'),
          _buildDetailRow('Nem / Gender:', item['gender'] ?? '-'),
          _buildDetailRow('Location:', item['location'] ?? 'Csengery'),
          _buildDetailRow('Méret (Size):', item['size'] ?? '-'),
          _buildDetailRow('Szín (Color):', item['color'] ?? '-'),
          _buildDetailRow('Minta (Pattern):', item['pattern'] ?? '-'),
          _buildDetailRow('Állapot (Condition):', item['condition'] ?? '-'),

          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text('Rendben (Got it)'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              fontSize: isHighlight ? 20 : 16,
              color: isHighlight ? Colors.green[700] : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsivePair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 8), second],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 8),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keresés'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      backgroundColor: Colors.grey[100],
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- TOP SECTION: CAMERA & AI STATUS ---
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.52,
              ),
              child: SingleChildScrollView(
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Search filters',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _filtersExpanded = !_filtersExpanded,
                              ),
                              icon: Icon(
                                _filtersExpanded
                                    ? Icons.expand_less
                                    : Icons.tune,
                              ),
                              label: Text(_filtersExpanded ? 'Hide' : 'Edit'),
                            ),
                          ],
                        ),
                        if (_filtersExpanded) ...[
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () async {
                              final value = await _chooseCategory();
                              if (value == null || !mounted) return;
                              setState(() {
                                _selectedCategory = value;
                                _categoryManuallyChanged = true;
                                _searchResults = [];
                              });
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Search category',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.category),
                                suffixIcon: Icon(Icons.arrow_drop_down),
                                isDense: true,
                              ),
                              child: Text(_selectedCategory),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey(_selectedGender),
                            initialValue: _selectedGender,
                            decoration: const InputDecoration(
                              labelText: 'Search gender',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.people),
                              isDense: true,
                            ),
                            items: ['Minden', ...genderOptions]
                                .map(
                                  (gender) => DropdownMenuItem(
                                    value: gender,
                                    child: Text(gender),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedGender = value;
                                  _genderManuallyChanged = true;
                                  _searchResults = [];
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedLocation,
                            decoration: const InputDecoration(
                              labelText: 'Search location',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.store),
                              isDense: true,
                            ),
                            items: _locations
                                .map(
                                  (location) => DropdownMenuItem(
                                    value: location,
                                    child: Text(location),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedLocation = value;
                                  _searchResults = [];
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _sizeController,
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              setState(() {
                                _selectedSize = value;
                                _searchResults = [];
                              });
                            },
                            onSubmitted: (_) {
                              _searchInventory();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Search size',
                              hintText: 'e.g. M, 32, 42',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.straighten),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _responsivePair(
                            TextField(
                              controller: _colorController,
                              textInputAction: TextInputAction.next,
                              onChanged: (value) {
                                setState(() {
                                  _selectedColor = value;
                                  _searchResults = [];
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'Search color',
                                prefixIcon: Icon(Icons.palette_outlined),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            TextField(
                              controller: _patternController,
                              textInputAction: TextInputAction.search,
                              onChanged: (value) {
                                setState(() {
                                  _selectedPattern = value;
                                  _searchResults = [];
                                });
                              },
                              onSubmitted: (_) {
                                _searchInventory();
                              },
                              decoration: const InputDecoration(
                                labelText: 'Pattern',
                                prefixIcon: Icon(Icons.texture),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text(
                              'More filters: name, brand, condition',
                            ),
                            children: [
                              TextField(
                                controller: _nameController,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedName = value;
                                    _searchResults = [];
                                  });
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _brandController,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedBrand = value;
                                    _searchResults = [];
                                  });
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Brand',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _conditionController,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCondition = value;
                                    _searchResults = [];
                                  });
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Condition',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Category: $_selectedCategory · Gender: $_selectedGender · '
                                'Location: $_selectedLocation'
                                '${_selectedSize.trim().isEmpty ? '' : ' · Size: ${_selectedSize.trim()}'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            // Thumbnail Preview
                            GestureDetector(
                              onTap: () => _pickImage(ImageSource.camera),
                              child: Container(
                                height: 100,
                                width: 100,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[400]!),
                                ),
                                child: _searchImage != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                          _searchImage!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt,
                                        color: Colors.grey,
                                        size: 40,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Search Button & Status
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!_isSearching && _searchResults.isEmpty)
                                    FilledButton.icon(
                                      onPressed: _searchImage == null
                                          ? _searchInventory
                                          : _executeSearch,
                                      icon: const Icon(Icons.search),
                                      label: Text(
                                        _searchImage == null
                                            ? 'Search inventory'
                                            : _aiCriteria == null
                                            ? 'Analyze image & search'
                                            : 'Search inventory',
                                      ),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _pickImage(ImageSource.gallery),
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    label: const Text('Choose from phone'),
                                  ),
                                  if (_isSearching)
                                    Row(
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(width: 10),
                                        Text(
                                          _aiCriteria == null
                                              ? 'AI elemzés...'
                                              : 'Keresés...',
                                        ),
                                      ],
                                    ),
                                  if (_aiCriteria != null) ...[
                                    const Text(
                                      "AI Keresési szűrők:",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      "${_aiCriteria!['category']} | ${_aiCriteria!['gender']} | ${_aiCriteria!['color']} | ${_aiCriteria!['pattern']}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // --- BOTTOM SECTION: RESULTS GRID ---
            Expanded(
              child: _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchImage == null
                            ? 'Choose filters, then search inventory.'
                            : _usedFallback
                            ? 'No matches found, including the broader search.'
                            : 'Nincs találat. (No exact matches found)',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.7,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final item = _searchResults[index];

                        // --- CHANGED: WRAPPED IN INKWELL ---
                        return InkWell(
                          onTap: () => _showItemDetails(
                            item,
                          ), // Opens the details sheet!
                          borderRadius: BorderRadius.circular(12),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    color: Colors.grey[200],
                                    child: item['image_url'] != null
                                        ? CachedRemoteImage(
                                            item['image_url'],
                                            fit: BoxFit.cover,
                                            thumbnail: true,
                                          )
                                        : const Icon(Icons.image_not_supported),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['brand'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        item['location'] ?? 'Csengery',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                      Text(
                                        item['name'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${item['category'] ?? '-'} · ${item['gender'] ?? '-'}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.blueGrey,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${item['price_est']} Ft',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
// --- GLOBAL HELPER FUNCTION ---
/*Future<T?> showSafeBottomSheet<T>({
  required BuildContext context,
  required Widget child, 
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true, // Fixes the 50% height limit
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return SafeArea( // Protects against the system navigation bar
        child: Padding(
          // Protects against the keyboard covering input fields
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            left: 20, 
            right: 20, 
            top: 20
          ),
          child: SingleChildScrollView( // Protects against overflow crashes
            child: child,
          ),
        ),
      );
    },
  );
}*/
