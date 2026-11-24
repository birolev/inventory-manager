import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/models/batch_image_queue.dart';

import '../services/inventory_search.dart';
import '../theme/app_theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, this.onOpenAccount});

  final VoidCallback? onOpenAccount;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  BatchImageQueue? _queue;
  final ImagePicker _picker = ImagePicker();

  bool _isUploading = false;
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

  static const _locations = InventorySearch.storeLocations;

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
      _showSnackBar('Kép kiválasztási hiba: $e', isError: true);
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
      _showSnackBar('Képek kiválasztási hiba: $e', isError: true);
    }
  }

  void _initializeQueue(List<XFile> files) {
    setState(() {
      _queue = BatchImageQueue(files.map((f) => QueueItem(f)).toList());
      _isEditing = false;
    });
    _startBackgroundAnalysis();
  }

  Future<void> _startBackgroundAnalysis() async {
    if (_queue == null) return;

    for (var item in _queue!.items) {
      if (!item.isReady && !item.isAnalyzing) {
        await _analyzeItem(item);
      }
    }
  }

  Future<void> _analyzeItem(QueueItem item) async {
    item.isAnalyzing = true;
    if (_queue?.current == item && mounted) {
      setState(() {});
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
        item.aiModel =
            responseData['_model']?.toString() ??
            responseData['model']?.toString();
        item.aiResult = Map<String, dynamic>.from(responseData)
          ..remove('_model')
          ..remove('model');
      }
    } catch (e) {
      _showSnackBar('AI elemzési hiba: $e', isError: true);
      item.aiResult = {};
    } finally {
      item.isAnalyzing = false;
      item.isReady = true;

      if (mounted && _queue?.current == item) {
        _populateControllers(item);
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  void _populateControllers(QueueItem item) {
    if (item.aiResult == null) return;
    final aiResult = item.aiResult!;

    setState(() {
      _nameController.text = aiResult['name']?.toString() ?? '';
      _brandController.text = aiResult['brand']?.toString() ?? '';
      _priceController.text = aiResult['price']?.toString() ?? '0';
      _colorController.text = aiResult['color']?.toString() ?? '';
      _patternController.text = aiResult['pattern']?.toString() ?? '';
      final aiSize = aiResult['size']?.toString().trim() ?? '';
      _sizeController.text = aiSize.isNotEmpty ? aiSize : _lastUsedSize;
      if (aiSize.isNotEmpty) _rememberSize(aiSize);
      _conditionController.text = aiResult['condition']?.toString() ?? '';

      final aiCategory = aiResult['category'];
      final aiGender = aiResult['gender'];
      _selectedGender = genderOptions.contains(aiGender)
          ? aiGender.toString()
          : genderOptions.contains(aiCategory)
          ? aiCategory.toString()
          : defaultClothingGender;
      _selectedCategory = clothingCategories.contains(aiCategory)
          ? aiCategory.toString()
          : defaultClothingCategory;

      _isEditing = true;
    });
  }

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

      List<num>? embedding;
      try {
        final embeddingResponse = await Supabase.instance.client.functions
            .invoke(
              'image-embedding',
              body: {
                'imageBase64': base64Encode(imageBytes),
                'mimeType': currentItem.image.mimeType ?? 'image/jpeg',
              },
            );
        if (embeddingResponse.status != 200) {
          throw Exception('Image embedding failed: ${embeddingResponse.data}');
        }
        embedding =
            (Map<String, dynamic>.from(
                      embeddingResponse.data as Map,
                    )['embedding']
                    as List)
                .cast<num>();
      } catch (error) {
        _showSnackBar(
          'A termék mentése sikerült, de vektor nélkül: $error',
          isError: true,
        );
      }

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
            'secondary_categories':
                (currentItem.aiResult?['secondary_categories'] as List? ?? [])
                    .whereType<String>()
                    .where(
                      (category) =>
                          clothingCategories.contains(category) &&
                          category != _selectedCategory,
                    )
                    .toSet()
                    .toList(),
            'gender': _selectedGender,
            'location': _selectedLocation,
            'image_url': imageUrl,
            'embedding': ?embedding,
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

      _showSnackBar('Termék sikeresen mentve a készletbe!');
      _moveToNextItemInQueue();
    } catch (e) {
      setState(() => _isUploading = false);
      _showSnackBar('Mentési hiba: $e', isError: true);
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
        _queue = null;
      } else if (_queue!.current.isReady) {
        _populateControllers(_queue!.current);
      }
    });
  }

  void _discardCurrentItem() {
    _moveToNextItemInQueue();
  }

  Future<void> _confirmCancelEntireBatch() async {
    final remaining = _queue == null ? 0 : _queue!.total - _queue!.currentIndex;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Köteg megszakítása?'),
        content: Text(
          'Még $remaining nem mentett fotó van a sorban. Biztosan megszakítod a feltöltést?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Maradok'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brick),
            child: const Text('Megszakítás'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _queue = null;
      _isEditing = false;
      _isUploading = false;
      _nameController.clear();
      _brandController.clear();
      _priceController.clear();
    });
  }

  void _showFullPreview(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(dialogContext).width * 0.9,
              height: MediaQuery.sizeOf(dialogContext).height * 0.8,
              child: ColoredBox(
                color: AppColors.ink,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filledTonal(
                tooltip: 'Bezárás',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.brick : AppColors.olive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasQueue = _queue != null && _queue!.hasNext;
    final QueueItem? currentItem = hasQueue ? _queue!.current : null;
    final readyCount = hasQueue
        ? _queue!.items.where((item) => item.isReady).length
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Árufelvétel'),
        actions: [
          if (hasQueue && !_isUploading)
            TextButton.icon(
              onPressed: _confirmCancelEntireBatch,
              icon: const Icon(Icons.close, size: 18, color: AppColors.brick),
              label: const Text(
                'Megszakítás',
                style: TextStyle(color: AppColors.brick),
              ),
            ),
          if (widget.onOpenAccount != null)
            IconButton(
              tooltip: 'Fiók',
              onPressed: widget.onOpenAccount,
              icon: const Icon(Icons.person_outline),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasQueue) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.terracottaSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_queue!.currentNumber} / ${_queue!.total} termék',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.terracotta,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI előkészítve: $readyCount / ${_queue!.total}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _queue!.currentNumber / _queue!.total,
                      backgroundColor: AppColors.border,
                      color: AppColors.terracotta,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (!hasQueue && !_isUploading)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppColors.terracottaSoft,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.add_a_photo_outlined,
                                size: 30,
                                color: AppColors.terracotta,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Új ruhák felvétele',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Válassz ki egy vagy több fotót — az AI a háttérben automatikusan kitölti a termék adatait.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _pickGalleryImages,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Fotók kiválasztása galériából'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _pickSingleImageCamera,
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Fotózás kamerával'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Container(
                    height: 280,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: currentItem != null
                        ? FutureBuilder<Uint8List>(
                            future: currentItem.bytes,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 54,
                                    color: AppColors.inkMuted,
                                  ),
                                );
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return GestureDetector(
                                onTap: () => _showFullPreview(snapshot.data!),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const Positioned(
                                      right: 10,
                                      bottom: 10,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(8),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.zoom_in,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 18),
                ],
                if (_isUploading ||
                    (currentItem != null && currentItem.isAnalyzing))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            _isUploading
                                ? 'Feltöltés a készletbe…'
                                : 'Az AI elemzi a ruhát…',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (hasQueue && _isEditing && !_isUploading)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Adatok ellenőrzése',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Termék neve',
                              prefixIcon: Icon(Icons.label_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _brandController,
                            decoration: const InputDecoration(
                              labelText: 'Márka',
                              prefixIcon: Icon(Icons.sell_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _priceController,
                                  decoration: const InputDecoration(
                                    labelText: 'Ár',
                                    suffixText: 'Ft',
                                    prefixIcon: Icon(Icons.payments_outlined),
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _sizeController,
                                  onChanged: _rememberSize,
                                  decoration: const InputDecoration(
                                    labelText: 'Méret',
                                    prefixIcon: Icon(Icons.straighten),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey('intake-cat-$_selectedCategory'),
                            initialValue: _selectedCategory,
                            decoration: const InputDecoration(
                              labelText: 'Kategória',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: clothingCategories
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(category),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedCategory = val),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('intake-gen-$_selectedGender'),
                                  initialValue: _selectedGender,
                                  decoration: const InputDecoration(
                                    labelText: 'Nem',
                                    prefixIcon: Icon(Icons.people_outline),
                                  ),
                                  items: genderOptions
                                      .map(
                                        (gender) => DropdownMenuItem(
                                          value: gender,
                                          child: Text(gender),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _selectedGender = value);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'intake-loc-$_selectedLocation',
                                  ),
                                  initialValue: _selectedLocation,
                                  decoration: const InputDecoration(
                                    labelText: 'Üzlet',
                                    prefixIcon: Icon(Icons.storefront_outlined),
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
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _colorController,
                                  decoration: const InputDecoration(
                                    labelText: 'Szín',
                                    prefixIcon: Icon(Icons.palette_outlined),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _patternController,
                                  decoration: const InputDecoration(
                                    labelText: 'Minta',
                                    prefixIcon: Icon(Icons.texture),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _conditionController,
                            decoration: const InputDecoration(
                              labelText: 'Állapot',
                              prefixIcon: Icon(Icons.star_outline),
                            ),
                          ),
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _finalUpload,
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('Mentés a készletbe'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              backgroundColor: AppColors.olive,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _discardCurrentItem,
                            child: const Text(
                              'Tétel elvetése',
                              style: TextStyle(color: AppColors.brick),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
