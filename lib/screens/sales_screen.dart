import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';
import '../services/inventory_search.dart';

class _SalePhoto {
  _SalePhoto(this.file);

  final XFile file;
  Uint8List? bytes;
  Map<String, dynamic>? aiCriteria;
  List<Map<String, dynamic>> matches = [];
  Map<String, dynamic>? selectedItem;
  String? error;
  bool isAnalyzing = false;
  bool usedFallback = false;
  String selectedCategory = 'Minden';
  String selectedGender = 'Minden';
  String locationFilter = 'All locations';
  String sizeFilter = '';
  String colorFilter = '';
  String patternFilter = '';
  String nameFilter = '';
  String brandFilter = '';
  String conditionFilter = '';
  bool colorWasChangedManually = false;
  bool patternWasChangedManually = false;
  int filterRevision = 0;
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, this.initialItems = const []});

  final List<Map<String, dynamic>> initialItems;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  static const _locations = ['Csengery', 'Astoria'];

  final ImagePicker _picker = ImagePicker();
  final List<_SalePhoto> _photos = [];
  final List<Map<String, dynamic>> _selectedItems = [];
  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );
  final TextEditingController _finalPriceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _sizeFilterController = TextEditingController();
  final TextEditingController _manualSearchController = TextEditingController();
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customPriceController = TextEditingController();
  final List<Map<String, dynamic>> _manualResults = [];

  int _currentPhotoIndex = 0;
  bool _isCheckout = false;
  bool _showAddOptions = false;
  bool _isSaving = false;
  bool _syncingPrices = false;
  bool _filtersExpanded = true;
  bool _isManualSearch = false;
  bool _isLoadingManualResults = false;
  String _manualCategory = 'Minden';
  String _manualGender = 'Minden';
  String _manualLocation = 'All locations';
  String _manualSearchText = '';
  String _location = _locations.first;
  String _paymentMethod = 'cash';
  String _sortOption = 'newest';
  DateTime _soldAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedItems.addAll(widget.initialItems);
    if (widget.initialItems.isNotEmpty) {
      _showAddOptions = true;
      final itemLocation = widget.initialItems.first['location']?.toString();
      if (_locations.contains(itemLocation)) _location = itemLocation!;
    }
  }

  double get _listedTotal => _selectedItems.fold<double>(
    0,
    (total, item) => total + _asDouble(item['price_est']),
  );

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  double _roundCurrency(double amount) => (amount * 100).round() / 100;

  @override
  void dispose() {
    _discountController.dispose();
    _finalPriceController.dispose();
    _notesController.dispose();
    _sizeFilterController.dispose();
    _manualSearchController.dispose();
    _customNameController.dispose();
    _customPriceController.dispose();
    super.dispose();
  }

  Future<void> _pickGalleryPhotos() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 55,
        maxWidth: 700,
      );
      if (files.isNotEmpty) _addPhotos(files);
    } catch (error) {
      _showMessage('Could not select photos: $error', isError: true);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 55,
        maxWidth: 700,
      );
      if (file != null) _addPhotos([file]);
    } catch (error) {
      _showMessage('Could not take a photo: $error', isError: true);
    }
  }

  void _addPhotos(List<XFile> files) {
    setState(() {
      _isManualSearch = false;
      _showAddOptions = false;
      _photos.addAll(files.map(_SalePhoto.new));
      _currentPhotoIndex = _photos.length - files.length;
      _filtersExpanded = true;
      _sizeFilterController.clear();
      _isCheckout = false;
    });
    _analyzeCurrentPhoto();
  }

  void _startManualSearch() {
    setState(() {
      _manualResults.clear();
      _isCheckout = false;
      _isManualSearch = true;
      _isLoadingManualResults = false;
      _manualCategory = 'Minden';
      _manualGender = 'Minden';
      _manualLocation = 'All locations';
      _manualSearchText = '';
      _manualSearchController.clear();
    });
    _loadManualResults();
  }

  Future<void> _loadManualResults() async {
    setState(() => _isLoadingManualResults = true);
    try {
      final (sortColumn, ascending) = switch (_sortOption) {
        'oldest' => ('created_at', true),
        'price_low' => ('price_est', true),
        'price_high' => ('price_est', false),
        _ => ('created_at', false),
      };

      final results = await InventorySearch.search(
        InventorySearchCriteria(
          category: _manualCategory,
          gender: _manualGender,
          location: _manualLocation,
          text: _manualSearchText,
          onlyUnsold: true,
          sortColumn: sortColumn,
          ascending: ascending,
        ),
      );

      if (!mounted) return;
      setState(() {
        _manualResults
          ..clear()
          ..addAll(results);
        _isLoadingManualResults = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingManualResults = false);
      _showMessage('Could not search inventory: $error', isError: true);
    }
  }

  void _toggleManualItem(Map<String, dynamic> item) {
    setState(() {
      final index = _selectedItems.indexWhere(
        (selected) => selected['id'] == item['id'],
      );
      if (index >= 0) {
        _selectedItems.removeAt(index);
      } else {
        _selectedItems.add(item);
        final itemLocation = item['location']?.toString();
        if (_selectedItems.length == 1 && _locations.contains(itemLocation)) {
          _location = itemLocation!;
        }
      }
    });
  }

  Future<void> _addCustomItem() async {
    _customNameController.clear();
    _customPriceController.clear();
    final formKey = GlobalKey<FormState>();
    final item = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add custom sale item'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _customNameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Item name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an item name'
                    : null,
              ),
              TextFormField(
                controller: _customPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Price (Ft)'),
                validator: (value) {
                  final price = double.tryParse(
                    value?.trim().replaceAll(',', '.') ?? '',
                  );
                  return price == null || price < 0
                      ? 'Enter a valid non-negative price'
                      : null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, {
                'custom_id': DateTime.now().microsecondsSinceEpoch.toString(),
                'name': _customNameController.text.trim(),
                'price_est': double.parse(
                  _customPriceController.text.trim().replaceAll(',', '.'),
                ),
                'is_custom': true,
              });
            },
            child: const Text('Add item'),
          ),
        ],
      ),
    );
    if (item == null || !mounted) return;
    setState(() {
      _selectedItems.add(item);
      _isManualSearch = false;
      _showAddOptions = true;
    });
  }

  Future<void> _analyzeCurrentPhoto() async {
    if (_currentPhotoIndex >= _photos.length) return;
    final photo = _photos[_currentPhotoIndex];
    setState(() {
      photo.isAnalyzing = true;
      photo.error = null;
    });

    try {
      final bytes = await photo.file.readAsBytes();
      final response = await Supabase.instance.client.functions.invoke(
        'gemini-vision',
        body: {
          'task': 'search',
          'imageBase64': base64Encode(bytes),
          'mimeType': _mimeTypeFor(photo.file),
        },
      );
      if (response.status != 200) {
        throw Exception('Image analysis failed: ${response.data}');
      }

      final criteria = Map<String, dynamic>.from(response.data as Map);
      final detectedCategory = _normalizeOption(
        criteria['category'],
        clothingCategories,
      );
      final detectedGender = _normalizeGender(criteria['gender']);
      final gender = detectedGender.isNotEmpty
          ? detectedGender
          : _normalizeGender(criteria['category']);
      if (!mounted) return;
      setState(() {
        photo.bytes = bytes;
        photo.aiCriteria = criteria;
        photo.selectedCategory = detectedCategory.isNotEmpty
            ? detectedCategory
            : 'Minden';
        photo.selectedGender = genderOptions.contains(gender)
            ? gender
            : 'Minden';
        photo.brandFilter = criteria['brand']?.toString() ?? '';
        photo.colorFilter = criteria['color']?.toString() ?? '';
        photo.patternFilter = criteria['pattern']?.toString() ?? '';
        photo.sizeFilter = criteria['size']?.toString() ?? '';
        _sizeFilterController.text = photo.sizeFilter;
      });
      await _refreshPhotoMatches(photo);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        photo.error = error.toString();
        photo.isAnalyzing = false;
      });
    }
  }

  String _mimeTypeFor(XFile file) {
    final mimeType = file.mimeType;
    if (mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp') {
      return mimeType!;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
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

  Future<List<Map<String, dynamic>>> _findMatches(
    _SalePhoto photo, {
    bool fallback = false,
  }) async {
    final (sortColumn, ascending) = switch (_sortOption) {
      'oldest' => ('created_at', true),
      'price_low' => ('price_est', true),
      'price_high' => ('price_est', false),
      _ => ('created_at', false),
    };

    return InventorySearch.search(
      InventorySearchCriteria(
        category: photo.selectedCategory,
        gender: photo.selectedGender,
        location: photo.locationFilter,
        brand: photo.brandFilter,
        size: photo.sizeFilter,
        color: photo.colorFilter,
        pattern: photo.patternFilter,
        name: photo.nameFilter,
        condition: photo.conditionFilter,
        onlyUnsold: true,
        fallback: fallback,
        sortColumn: sortColumn,
        ascending: ascending,
        maxResults: 100,
      ),
    );
  }

  Future<void> _refreshPhotoMatches(_SalePhoto photo) async {
    setState(() {
      photo.isAnalyzing = true;
      photo.error = null;
    });
    try {
      var matches = await _findMatches(photo);
      var usedFallback = false;

      if (matches.isEmpty) {
        matches = await _findMatches(photo, fallback: true);
        usedFallback = true;
        photo.selectedGender = 'Minden';
        photo.sizeFilter = '';
        photo.colorFilter = '';
        photo.patternFilter = '';
        photo.nameFilter = '';
        photo.conditionFilter = '';
        photo.filterRevision++;
        if (identical(photo, _photos[_currentPhotoIndex])) {
          _sizeFilterController.clear();
        }
      }

      if (!mounted) return;
      setState(() {
        photo.matches = matches;
        photo.usedFallback = usedFallback;
        photo.isAnalyzing = false;
        if (photo.selectedItem != null &&
            !matches.any((item) => item['id'] == photo.selectedItem!['id'])) {
          photo.selectedItem = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        photo.error = error.toString();
        photo.isAnalyzing = false;
      });
    }
  }

  void _selectItem(Map<String, dynamic> item) {
    final photo = _photos[_currentPhotoIndex];
    final alreadySelected = _selectedItems.any(
      (selected) => selected['id'] == item['id'],
    );
    if (alreadySelected && photo.selectedItem?['id'] != item['id']) return;

    setState(() {
      photo.selectedItem = photo.selectedItem?['id'] == item['id']
          ? null
          : item;
    });
  }

  void _advancePhoto() {
    final photo = _photos[_currentPhotoIndex];
    if (photo.selectedItem != null) {
      _selectedItems.add(photo.selectedItem!);
      final location = photo.selectedItem!['location']?.toString();
      if (_selectedItems.length == 1 && _locations.contains(location)) {
        _location = location!;
      }
    }

    if (_currentPhotoIndex + 1 < _photos.length) {
      setState(() {
        _currentPhotoIndex++;
        _sizeFilterController.text = _photos[_currentPhotoIndex].sizeFilter;
      });
      _analyzeCurrentPhoto();
    } else {
      setState(() => _showAddOptions = true);
    }
  }

  void _openCheckout() {
    setState(() {
      _isCheckout = true;
      _showAddOptions = false;
      _discountController.text = '0';
      _finalPriceController.text = _formatAmount(_listedTotal);
    });
  }

  void _onDiscountChanged(String value) {
    if (_syncingPrices) return;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null) return;
    final discount = parsed.clamp(0.0, 100.0).toDouble();
    _syncingPrices = true;
    if (discount != parsed) {
      final text = _formatAmount(discount);
      _discountController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _finalPriceController.text = _formatAmount(
      _listedTotal * (1 - discount / 100),
    );
    _syncingPrices = false;
    setState(() {});
  }

  void _onFinalPriceChanged(String value) {
    if (_syncingPrices) return;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null) return;
    final amount = parsed.clamp(0.0, _listedTotal).toDouble();
    final discount = _listedTotal == 0
        ? 0.0
        : ((_listedTotal - amount) / _listedTotal * 100).clamp(0.0, 100.0);
    _syncingPrices = true;
    if (amount != parsed) {
      final text = _formatAmount(amount);
      _finalPriceController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _discountController.text = _formatAmount(discount);
    _syncingPrices = false;
    setState(() {});
  }

  void _removeItem(Map<String, dynamic> item) {
    final discount =
        double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0;
    setState(() => _selectedItems.remove(item));
    final boundedDiscount = discount.clamp(0.0, 100.0).toDouble();
    _syncingPrices = true;
    _finalPriceController.text = _formatAmount(
      _listedTotal * (1 - boundedDiscount / 100),
    );
    _syncingPrices = false;
  }

  Future<void> _chooseSaleDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _soldAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_soldAt),
    );
    if (time == null) return;

    setState(() {
      _soldAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  List<Map<String, dynamic>> _buildSaleLines() {
    final total =
        double.tryParse(_finalPriceController.text.replaceAll(',', '.')) ??
        _listedTotal;
    final subtotal = _listedTotal;
    var allocated = 0.0;

    return List.generate(_selectedItems.length, (index) {
      final item = _selectedItems[index];
      final listedPrice = _asDouble(item['price_est']);
      final actualPrice = index == _selectedItems.length - 1
          ? _roundCurrency(total - allocated)
          : _roundCurrency(
              subtotal > 0
                  ? total * listedPrice / subtotal
                  : total / _selectedItems.length,
            );
      allocated += actualPrice;
      return {
        if (item['is_custom'] == true)
          'item_name': item['name']
        else
          'inventory_id': item['id'].toString(),
        'actual_price': actualPrice,
        if (item['is_custom'] == true)
          'original_price': _asDouble(item['price_est']),
      };
    });
  }

  Future<void> _recordSale() async {
    if (_selectedItems.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client.rpc(
        'record_sale',
        params: {
          'p_location': _location,
          'p_payment_method': _paymentMethod,
          'p_items': _buildSaleLines(),
          'p_sold_at': _soldAt.toUtc().toIso8601String(),
          'p_notes': _notesController.text.trim(),
        },
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Could not record sale: $error', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isCheckout
              ? 'Sale total'
              : _showAddOptions
              ? 'Add sale items'
              : 'Match sold items',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      backgroundColor: Colors.grey[100],
      body: _photos.isEmpty
          ? _isManualSearch
                ? _isCheckout
                      ? _buildCheckout()
                      : _buildManualSearch()
                : _isCheckout
                ? _buildCheckout()
                : _showAddOptions
                ? _buildAddOptions()
                : _buildPhotoPicker()
          : _isCheckout
          ? _buildCheckout()
          : _isManualSearch
          ? _buildManualSearch()
          : _showAddOptions
          ? _buildAddOptions()
          : _buildMatcher(),
    );
  }

  Widget _buildPhotoPicker() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.point_of_sale, size: 72, color: Colors.blueGrey),
            const SizedBox(height: 16),
            const Text(
              'Record a sale',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose photos of the sold items. Match each photo to an '
              'inventory item, then review the sale total.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickGalleryPhotos,
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose sold item photos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take a photo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addCustomItem,
              icon: const Icon(Icons.add),
              label: const Text('Add custom item'),
            ),
            const SizedBox(height: 16),
            const Text('Or select unsold inventory directly'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _startManualSearch,
              icon: const Icon(Icons.search),
              label: const Text('Search inventory'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOptions() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_selectedItems.length} item${_selectedItems.length == 1 ? '' : 's'} added',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickGalleryPhotos,
              icon: const Icon(Icons.photo_library),
              label: const Text('Add another photo'),
            ),
            OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take another photo'),
            ),
            OutlinedButton.icon(
              onPressed: _startManualSearch,
              icon: const Icon(Icons.search),
              label: const Text('Add from inventory'),
            ),
            OutlinedButton.icon(
              onPressed: _addCustomItem,
              icon: const Icon(Icons.add),
              label: const Text('Add custom item'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _openCheckout,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Done adding items'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualSearch() {
    return Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(_manualCategory),
                    initialValue: _manualCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: filterCategories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: _isLoadingManualResults
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _manualCategory = value);
                              _loadManualResults();
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  _responsivePair(
                    DropdownButtonFormField<String>(
                      key: ValueKey(_manualGender),
                      initialValue: _manualGender,
                      decoration: const InputDecoration(
                        labelText: 'Gender',
                        prefixIcon: Icon(Icons.people),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ['Minden', ...genderOptions]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: _isLoadingManualResults
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _manualGender = value);
                                _loadManualResults();
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_manualLocation),
                      initialValue: _manualLocation,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        prefixIcon: Icon(Icons.store),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ['All locations', ..._locations]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: _isLoadingManualResults
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _manualLocation = value);
                                _loadManualResults();
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualSearchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) => _manualSearchText = value,
                    onSubmitted: (_) => _loadManualResults(),
                    decoration: InputDecoration(
                      labelText: 'Name or brand',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: 'Search inventory',
                        onPressed: _isLoadingManualResults
                            ? null
                            : _loadManualResults,
                        icon: const Icon(Icons.search),
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_manualResults.length} items · ${_selectedItems.length} selected',
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoadingManualResults
              ? const Center(child: CircularProgressIndicator())
              : _manualResults.isEmpty
              ? const Center(child: Text('No unsold inventory items found.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _manualResults.length,
                  itemBuilder: (context, index) =>
                      _buildManualItemCard(_manualResults[index]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runAlignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _isLoadingManualResults
                      ? null
                      : () => setState(() {
                          _isManualSearch = false;
                          _showAddOptions = _selectedItems.isNotEmpty;
                        }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                FilledButton.icon(
                  onPressed: _selectedItems.isEmpty || _isLoadingManualResults
                      ? null
                      : () => setState(() {
                          _isManualSearch = false;
                          _showAddOptions = true;
                        }),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('Continue (${_selectedItems.length})'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualItemCard(Map<String, dynamic> item) {
    final isSelected = _selectedItems.any(
      (selected) => selected['id'] == item['id'],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      color: isSelected ? Colors.green[50] : null,
      child: InkWell(
        onTap: () => _toggleManualItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black12,
                    child: item['image_url'] == null
                        ? const Icon(Icons.image_not_supported)
                        : Image.network(
                            item['image_url'].toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                          ),
                  ),
                  if (isSelected)
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.check, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['brand']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    item['name']?.toString() ?? 'Unknown item',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${item['category'] ?? '-'} · ${item['gender'] ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text('${item['price_est'] ?? 0} Ft'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatcher() {
    final photo = _photos[_currentPhotoIndex];
    final activeFilters = <String>[
      photo.selectedCategory == 'Minden'
          ? 'all categories'
          : photo.selectedCategory,
      photo.selectedGender == 'Minden' ? 'all genders' : photo.selectedGender,
      if (photo.sizeFilter.trim().isNotEmpty) 'size ${photo.sizeFilter.trim()}',
      if (photo.locationFilter != 'All locations')
        'location ${photo.locationFilter}',
      if (photo.colorFilter.trim().isNotEmpty)
        'color ${photo.colorFilter.trim()}',
      if (photo.patternFilter.trim().isNotEmpty)
        'pattern ${photo.patternFilter.trim()}',
      if (photo.nameFilter.trim().isNotEmpty) 'name ${photo.nameFilter.trim()}',
      if (photo.brandFilter.trim().isNotEmpty)
        'brand ${photo.brandFilter.trim()}',
      if (photo.conditionFilter.trim().isNotEmpty)
        'condition ${photo.conditionFilter.trim()}',
    ].join(' · ');
    final sortDescription = switch (_sortOption) {
      'oldest' => 'oldest upload',
      'price_low' => 'price low to high',
      'price_high' => 'price high to low',
      _ => 'newest upload',
    };
    return Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 390),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo ${_currentPhotoIndex + 1} of ${_photos.length}  ·  '
                    '${_selectedItems.length} matched',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (photo.bytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photo.bytes!,
                            width: 92,
                            height: 112,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        const SizedBox(
                          width: 92,
                          height: 112,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: photo.isAnalyzing
                            ? const Text(
                                'Analyzing photo and searching inventory…',
                              )
                            : photo.error != null
                            ? Text(
                                photo.error!,
                                style: const TextStyle(color: Colors.red),
                              )
                            : Text(
                                'AI match: ${photo.aiCriteria?['category'] ?? '-'} · '
                                '${photo.aiCriteria?['gender'] ?? '-'} · '
                                '${photo.aiCriteria?['color'] ?? '-'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
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
                          _filtersExpanded ? Icons.expand_less : Icons.tune,
                        ),
                        label: Text(_filtersExpanded ? 'Hide' : 'Edit'),
                      ),
                    ],
                  ),
                  if (_filtersExpanded) ...[
                    DropdownButtonFormField<String>(
                      initialValue: photo.selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Search category (change AI result)',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: filterCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: photo.isAnalyzing
                          ? null
                          : (category) {
                              if (category == null) return;
                              setState(() {
                                photo.selectedCategory = category;
                              });
                              _refreshPhotoMatches(photo);
                            },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: photo.selectedGender,
                      decoration: const InputDecoration(
                        labelText: 'Search gender (change AI result)',
                        prefixIcon: Icon(Icons.people),
                        border: OutlineInputBorder(),
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
                      onChanged: photo.isAnalyzing
                          ? null
                          : (gender) {
                              if (gender == null) return;
                              setState(() => photo.selectedGender = gender);
                              _refreshPhotoMatches(photo);
                            },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: photo.locationFilter,
                      decoration: const InputDecoration(
                        labelText: 'Inventory location',
                        prefixIcon: Icon(Icons.store),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ['All locations', ..._locations]
                          .map(
                            (location) => DropdownMenuItem(
                              value: location,
                              child: Text(location),
                            ),
                          )
                          .toList(),
                      onChanged: photo.isAnalyzing
                          ? null
                          : (location) {
                              if (location == null) return;
                              setState(() => photo.locationFilter = location);
                              _refreshPhotoMatches(photo);
                            },
                    ),
                    const SizedBox(height: 8),
                    _responsivePair(
                      TextField(
                        controller: _sizeFilterController,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) => photo.sizeFilter = value,
                        onSubmitted: (_) => _refreshPhotoMatches(photo),
                        decoration: InputDecoration(
                          labelText: 'Size',
                          hintText: 'M, 32, 42',
                          prefixIcon: Icon(Icons.straighten),
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'Apply size filter',
                            icon: const Icon(Icons.search),
                            onPressed: photo.isAnalyzing
                                ? null
                                : () => _refreshPhotoMatches(photo),
                          ),
                        ),
                      ),
                      _criteriaTextField(
                        photo: photo,
                        field: 'color',
                        label: 'Color',
                        initialValue: photo.colorFilter,
                        onChanged: (value) {
                          photo.colorFilter = value;
                          photo.colorWasChangedManually = true;
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _responsivePair(
                      _criteriaTextField(
                        photo: photo,
                        field: 'pattern',
                        label: 'Pattern',
                        initialValue: photo.patternFilter,
                        onChanged: (value) {
                          photo.patternFilter = value;
                          photo.patternWasChangedManually = true;
                        },
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _sortOption,
                        decoration: const InputDecoration(
                          labelText: 'Sort matches',
                          prefixIcon: Icon(Icons.sort),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'newest',
                            child: Text('Newest upload'),
                          ),
                          DropdownMenuItem(
                            value: 'oldest',
                            child: Text('Oldest upload'),
                          ),
                          DropdownMenuItem(
                            value: 'price_low',
                            child: Text('Price ascending'),
                          ),
                          DropdownMenuItem(
                            value: 'price_high',
                            child: Text('Price descending'),
                          ),
                        ],
                        onChanged: photo.isAnalyzing
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _sortOption = value);
                                _refreshPhotoMatches(photo);
                              },
                      ),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('More filters: name, brand, condition'),
                      children: [
                        _criteriaTextField(
                          photo: photo,
                          field: 'name',
                          label: 'Name',
                          initialValue: photo.nameFilter,
                          onChanged: (value) => photo.nameFilter = value,
                        ),
                        const SizedBox(height: 8),
                        _criteriaTextField(
                          photo: photo,
                          field: 'brand',
                          label: 'Brand',
                          initialValue: photo.brandFilter,
                          onChanged: (value) => photo.brandFilter = value,
                        ),
                        const SizedBox(height: 8),
                        _criteriaTextField(
                          photo: photo,
                          field: 'condition',
                          label: 'Condition',
                          initialValue: photo.conditionFilter,
                          onChanged: (value) => photo.conditionFilter = value,
                        ),
                      ],
                    ),
                  ],
                  if (!photo.isAnalyzing &&
                      photo.usedFallback &&
                      photo.matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No matches found, including the broader search using '
                        'category, location, and brand.',
                        style: TextStyle(color: Colors.blueGrey),
                      ),
                    ),
                  if (!photo.isAnalyzing &&
                      photo.matches.isNotEmpty &&
                      photo.aiCriteria != null &&
                      _matchesMayBeUnfiltered(photo))
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No exact matches; showing broader results using category, '
                        'location, and brand only.',
                        style: TextStyle(color: Colors.blueGrey),
                      ),
                    ),
                  Text(
                    'Searching: $activeFilters · sorted by $sortDescription',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (photo.isAnalyzing)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (photo.error != null)
          Expanded(
            child: Center(
              child: FilledButton.tonalIcon(
                onPressed: _analyzeCurrentPhoto,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry analysis'),
              ),
            ),
          )
        else if (photo.matches.isEmpty)
          const Expanded(
            child: Center(child: Text('No unsold inventory items found.')),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.68,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: photo.matches.length,
              itemBuilder: (context, index) =>
                  _buildMatchCard(photo, photo.matches[index]),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runAlignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: photo.isAnalyzing ? null : _advancePhoto,
                  child: const Text('Skip photo'),
                ),
                FilledButton.icon(
                  onPressed: photo.isAnalyzing || photo.selectedItem == null
                      ? null
                      : _advancePhoto,
                  icon: const Icon(Icons.check),
                  label: Text(
                    _currentPhotoIndex + 1 == _photos.length
                        ? 'Finish matching'
                        : 'Add & next',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _matchesMayBeUnfiltered(_SalePhoto photo) {
    return photo.usedFallback;
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

  Widget _criteriaTextField({
    required _SalePhoto photo,
    required String field,
    required String label,
    required String initialValue,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      key: ValueKey('sale-$_currentPhotoIndex-${photo.filterRevision}-$field'),
      initialValue: initialValue,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onFieldSubmitted: (_) => _refreshPhotoMatches(photo),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: 'Apply $label filter',
          icon: const Icon(Icons.search),
          onPressed: photo.isAnalyzing
              ? null
              : () => _refreshPhotoMatches(photo),
        ),
      ),
    );
  }

  Widget _buildMatchCard(_SalePhoto photo, Map<String, dynamic> item) {
    final alreadySelected = _selectedItems.any(
      (selected) => selected['id'] == item['id'],
    );
    final selectedHere = photo.selectedItem?['id'] == item['id'];
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selectedHere ? Colors.green[50] : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selectedHere ? Colors.green : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: alreadySelected && !selectedHere
            ? null
            : () => _selectItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black12,
                    child: item['image_url'] == null
                        ? const Icon(Icons.image_not_supported)
                        : Image.network(
                            item['image_url'].toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                          ),
                  ),
                  if (selectedHere)
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.check, color: Colors.white),
                        ),
                      ),
                    ),
                  if (alreadySelected && !selectedHere)
                    ColoredBox(
                      color: Colors.black45,
                      child: const Center(
                        child: Text(
                          'Already matched',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['brand']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Text(
                    item['name']?.toString() ?? 'Unknown item',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${item['category'] ?? '-'} · ${item['gender'] ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text('${item['price_est'] ?? 0} Ft'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckout() {
    final subtotal = _listedTotal;
    final finalTotal =
        double.tryParse(_finalPriceController.text.replaceAll(',', '.')) ??
        subtotal;
    final discount = subtotal == 0
        ? 0.0
        : ((subtotal - finalTotal) / subtotal * 100).clamp(0.0, 100.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sale items (${_selectedItems.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_selectedItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No items matched. Go back and try again.'),
            )
          else
            ..._selectedItems.map(_buildSaleItemTile),
          const Divider(height: 28),
          _summaryRow('Listed total', subtotal),
          const SizedBox(height: 12),
          TextField(
            controller: _discountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _onDiscountChanged,
            decoration: const InputDecoration(
              labelText: 'Discount (%)',
              suffixText: '%',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _finalPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _onFinalPriceChanged,
            decoration: const InputDecoration(
              labelText: 'Final price paid (Ft)',
              suffixText: 'Ft',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          _summaryRow('Discount amount', subtotal - finalTotal),
          _summaryRow('Discount rate', discount, suffix: '%'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _location,
            decoration: const InputDecoration(
              labelText: 'Sale location',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.store),
            ),
            items: _locations
                .map(
                  (location) =>
                      DropdownMenuItem(value: location, child: Text(location)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _location = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.payments),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'mixed', child: Text('Mixed cash/card')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _paymentMethod = value);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Sale time'),
            subtitle: Text(_formatDateTime(_soldAt)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _chooseSaleDateTime,
          ),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selectedItems.isEmpty || _isSaving
                  ? null
                  : _recordSale,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Recording sale…' : 'Record sale'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green[700],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSaleItemTile(Map<String, dynamic> item) {
    return Card(
      child: ListTile(
        title: Text(item['name']?.toString() ?? 'Unknown item'),
        subtitle: Text(
          '${item['category'] ?? '-'} · ${item['gender'] ?? '-'} · '
          'Listed ${_formatAmount(_asDouble(item['price_est']))} Ft',
        ),
        trailing: IconButton(
          tooltip: 'Remove from this sale',
          onPressed: () => _removeItem(item),
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double amount, {String suffix = ' Ft'}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '${_formatAmount(amount)}$suffix',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
