import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/models/batch_image_queue.dart';

import 'inventory_list_screen.dart';
import 'sales_dashboard_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  BatchImageQueue? _queue;
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false; // Used for final Supabase upload
  bool _isEditing = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _patternController = TextEditingController();
  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();

  static const _lastUsedSizeKey = 'inventory_last_used_size';
  String _lastUsedSize = '';
  bool _sizePreferenceLoaded = false;

  String? _selectedCategory = defaultClothingCategory;
  String _selectedGender = defaultClothingGender;
  String _selectedLocation = 'Csengery';

  static const _locations = ['Csengery', 'Astoria'];

  Future<void> _loadLastUsedSize() async {
    if (_sizePreferenceLoaded) return;
    final preferences = await SharedPreferences.getInstance();
    _lastUsedSize = preferences.getString(_lastUsedSizeKey) ?? '';
    _sizePreferenceLoaded = true;
  }

  void _rememberSize(String value) {
    _lastUsedSize = value.trim();
    SharedPreferences.getInstance().then((preferences) {
      preferences.setString(_lastUsedSizeKey, _lastUsedSize);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _colorController.dispose();
    _patternController.dispose();
    _sizeController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  // --- Image Picking ---

  Future<void> _pickSingleImageCamera() async {
    try {
      await _loadLastUsedSize();
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (pickedFile != null) {
        _initializeQueue([pickedFile]);
      }
    } catch (e) {
      _showSnackBar('Error picking image: $e', isError: true);
    }
  }

  Future<void> _pickGalleryImages() async {
    try {
      await _loadLastUsedSize();
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (pickedFiles.isNotEmpty) {
        _initializeQueue(pickedFiles);
      }
    } catch (e) {
      _showSnackBar('Error picking images: $e', isError: true);
    }
  }

  void _initializeQueue(List<XFile> files) {
    setState(() {
      _queue = BatchImageQueue(files.map((f) => QueueItem(f)).toList());
      _isEditing = false;
    });
    _startBackgroundAnalysis();
  }

  // --- AI Background Processing ---

  Future<void> _startBackgroundAnalysis() async {
    if (_queue == null) return;

    // Process all items in the background
    for (var item in _queue!.items) {
      if (!item.isReady && !item.isAnalyzing) {
        await _analyzeItem(item);
      }
    }
  }

  Future<void> _analyzeItem(QueueItem item) async {
    item.isAnalyzing = true;
    if (_queue?.current == item && mounted) {
      setState(() {}); // Rebuild to show spinner if it's the current item
    }

    try {
      final imageBytes = await item.bytes;
      final result = await Supabase.instance.client.functions.invoke(
        'gemini-vision',
        body: {
          'task': 'inventory',
          'imageBase64': base64Encode(imageBytes),
          'mimeType': 'image/jpeg',
        },
      );
      final responseData = Map<String, dynamic>.from(result.data as Map);
      if (responseData['result'] is Map) {
        item.aiResult = Map<String, dynamic>.from(
          responseData['result'] as Map,
        );
        item.aiModel = responseData['model']?.toString();
      } else {
        // Continue to accept results from an Edge Function that has not yet
        // been redeployed with model metadata.
        item.aiModel =
            responseData['_model']?.toString() ??
            responseData['model']?.toString();
        item.aiResult = Map<String, dynamic>.from(responseData)
          ..remove('_model')
          ..remove('model');
      }
    } catch (e) {
      _showSnackBar('AI Error on an image: $e', isError: true);
      // Even if it fails, mark as ready so user can manually fill it out
      item.aiResult = {};
    } finally {
      item.isAnalyzing = false;
      item.isReady = true;

      // If the user is currently looking at this item, populate the form
      if (mounted && _queue?.current == item) {
        _populateControllers(item);
      } else if (mounted) {
        setState(
          () {},
        ); // Silent rebuild to update background progress indicators if needed
      }
    }
  }

  void _populateControllers(QueueItem item) {
    if (item.aiResult == null) return;
    final aiResult = item.aiResult!;

    setState(() {
      _nameController.text = aiResult['name'] ?? "";
      _brandController.text = aiResult['brand'] ?? "";
      _priceController.text = aiResult['price']?.toString() ?? "0";
      _colorController.text = aiResult['color'] ?? "";
      _patternController.text = aiResult['pattern'] ?? "";
      final aiSize = aiResult['size']?.toString().trim() ?? '';
      _sizeController.text = aiSize.isNotEmpty ? aiSize : _lastUsedSize;
      if (aiSize.isNotEmpty) _rememberSize(aiSize);
      _conditionController.text = aiResult['condition'] ?? "";

      final aiCategory = aiResult['category'];
      final aiGender = aiResult['gender'];
      // Accept responses from an older Edge Function until it is redeployed.
      _selectedGender = genderOptions.contains(aiGender)
          ? aiGender
          : genderOptions.contains(aiCategory)
          ? aiCategory
          : defaultClothingGender;
      _selectedCategory = clothingCategories.contains(aiCategory)
          ? aiCategory
          : defaultClothingCategory;

      _isEditing = true;
    });
  }

  // --- Uploading and Queue Management ---

  Map<String, dynamic> _aiValuesForReview(QueueItem item) {
    final result = item.aiResult;
    if (result == null) return {};

    const fields = [
      'name',
      'brand',
      'price',
      'category',
      'gender',
      'color',
      'pattern',
      'size',
      'condition',
    ];
    return {
      for (final field in fields)
        if (result.containsKey(field) && result[field] != null)
          field: result[field],
    };
  }

  Map<String, dynamic> _finalValuesForReview() => {
    'name': _nameController.text,
    'brand': _brandController.text,
    'price': double.tryParse(_priceController.text) ?? 0.0,
    'category': _selectedCategory,
    'gender': _selectedGender,
    'color': _colorController.text,
    'pattern': _patternController.text,
    'size': _sizeController.text,
    'condition': _conditionController.text,
  };

  bool _auditValuesDiffer(String field, dynamic aiValue, dynamic finalValue) {
    if (field == 'price') {
      final aiPrice = double.tryParse(aiValue.toString());
      final finalPrice = double.tryParse(finalValue.toString());
      return aiPrice != finalPrice;
    }
    return aiValue?.toString().trim().toLowerCase() !=
        finalValue?.toString().trim().toLowerCase();
  }

  Future<void> _writeAiIntakeReview({
    required dynamic inventoryId,
    required QueueItem item,
    required Map<String, dynamic> aiValues,
    required Map<String, dynamic> finalValues,
  }) async {
    try {
      final changedFields = aiValues.keys
          .where(
            (field) =>
                _auditValuesDiffer(field, aiValues[field], finalValues[field]),
          )
          .toList();
      await Supabase.instance.client.from('ai_intake_reviews').insert({
        'inventory_id': inventoryId,
        'model': item.aiModel,
        'ai_values': aiValues,
        'final_values': {
          for (final field in aiValues.keys) field: finalValues[field],
        },
        'changed_fields': changedFields,
      });
    } catch (error) {
      // Audit logging is best effort and must not interrupt an inventory save.
      debugPrint('Could not record AI intake review: $error');
    }
  }

  Future<void> _finalUpload() async {
    if (_queue == null) return;
    setState(() => _isUploading = true);

    try {
      final currentItem = _queue!.current;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageBytes = await currentItem.bytes;

      await Supabase.instance.client.storage
          .from('clothes-images')
          .uploadBinary(fileName, imageBytes);

      final imageUrl = Supabase.instance.client.storage
          .from('clothes-images')
          .getPublicUrl(fileName);

      final aiValues = _aiValuesForReview(currentItem);
      final finalValues = _finalValuesForReview();
      final insertedItem = await Supabase.instance.client
          .from('inventory')
          .insert({
            'name': _nameController.text,
            'brand': _brandController.text,
            'price_est': double.tryParse(_priceController.text) ?? 0.0,
            'category': _selectedCategory,
            'gender': _selectedGender,
            'location': _selectedLocation,
            'image_url': imageUrl,
            'color': _colorController.text,
            'pattern': _patternController.text,
            'size': _sizeController.text,
            'condition': _conditionController.text,
            'is_sold': false,
          })
          .select('id')
          .single();

      if (currentItem.aiModel != null && aiValues.isNotEmpty) {
        unawaited(
          _writeAiIntakeReview(
            inventoryId: insertedItem['id'],
            item: currentItem,
            aiValues: aiValues,
            finalValues: finalValues,
          ),
        );
      }

      _showSnackBar('Item successfully saved to inventory!');
      _moveToNextItemInQueue();
    } catch (e) {
      setState(() => _isUploading = false);
      _showSnackBar('Save Error: $e', isError: true);
    }
  }

  void _moveToNextItemInQueue() {
    _nameController.clear();
    _brandController.clear();
    _priceController.clear();
    _colorController.clear();
    _patternController.clear();
    _sizeController.clear();
    _conditionController.clear();
    _selectedCategory = defaultClothingCategory;
    _selectedGender = defaultClothingGender;
    _isEditing = false;
    _isUploading = false;

    setState(() {
      _queue!.moveNext();
      if (!_queue!.hasNext) {
        _queue = null; // Finished batch
      } else {
        // If the next item has already finished processing in the background, load it instantly!
        if (_queue!.current.isReady) {
          _populateControllers(_queue!.current);
        }
      }
    });
  }

  void _discardCurrentItem() {
    _moveToNextItemInQueue();
  }

  void _cancelEntireBatch() {
    setState(() {
      _queue = null;
      _isEditing = false;
      _isUploading = false;
      _nameController.clear();
      _brandController.clear();
      _priceController.clear();
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final bool hasQueue = _queue != null && _queue!.hasNext;
    final QueueItem? currentItem = hasQueue ? _queue!.current : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart, size: 28),
            tooltip: 'My daily sales',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SalesDashboardScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list, size: 30),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const InventoryListScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Batch Progress Indicator
            if (hasQueue) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Item ${_queue!.currentNumber} of ${_queue!.total}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _cancelEntireBatch,
                    icon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                    label: const Text(
                      'Cancel Batch',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // Image Preview Container
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: currentItem != null
                  ? FutureBuilder<Uint8List>(
                      future: currentItem.bytes,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(
                            child: Icon(
                              Icons.broken_image,
                              size: 60,
                              color: Colors.grey,
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        );
                      },
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 80, color: Colors.grey),
                        Text(
                          'No Image Selected',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 20),

            // Selection Buttons (Only visible if no queue is active)
            if (!hasQueue && !_isUploading)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickSingleImageCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickGalleryImages,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery (Multi)'),
                  ),
                ],
              ),

            // Background Processing / Uploading Indicators
            if (_isUploading ||
                (currentItem != null && currentItem.isAnalyzing))
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(
                    _isUploading
                        ? "Uploading to inventory..."
                        : "AI is analyzing this item...",
                  ),
                ],
              ),

            // Edit Form (Appears when item is ready)
            if (hasQueue && _isEditing && !_isUploading) ...[
              const Divider(height: 40),

              const Text(
                'Verify Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),

              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Gender (Női/Férfi)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people),
                ),
                items: genderOptions
                    .map(
                      (gender) =>
                          DropdownMenuItem(value: gender, child: Text(gender)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedGender = value);
                  }
                },
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _brandController,
                decoration: const InputDecoration(
                  labelText: 'Brand',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.branding_watermark),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price (Ft)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _sizeController,
                onChanged: _rememberSize,
                decoration: const InputDecoration(
                  labelText: 'Méret (Size)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _colorController,
                decoration: const InputDecoration(
                  labelText: 'Szín (Color)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.color_lens),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _patternController,
                decoration: const InputDecoration(
                  labelText: 'Minta (Pattern)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.texture),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _conditionController,
                decoration: const InputDecoration(
                  labelText: 'Állapot (Condition)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.star),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: clothingCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedLocation,
                decoration: const InputDecoration(
                  labelText: 'Store location',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.store),
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
                    setState(() => _selectedLocation = value);
                  }
                },
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _finalUpload,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Confirm & Save to Inventory'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green[700],
                  ),
                ),
              ),

              TextButton(
                onPressed: _discardCurrentItem,
                child: const Text(
                  'Discard This Item',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
