import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/widgets/cached_remote_image.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';
import '../widgets/inventory_search_view.dart';
import '../widgets/safe_bottom_sheet.dart';
import 'inventory_intake_screen.dart';
import 'sales_dashboard_screen.dart';
import 'sales_screen.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({
    super.key,
    this.searchGateway = const SupabaseInventorySearchGateway(),
    this.checkMissingEmbeddings = true,
  });

  final InventorySearchGateway searchGateway;
  final bool checkMissingEmbeddings;

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  static const _locations = InventorySearch.storeLocations;

  late final InventorySearchController _searchController;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isBackfillingEmbeddings = false;
  bool _checkedMissingEmbeddings = false;
  bool _hasMissingEmbeddings = true;
  String? _embeddingProgress;
  bool _isCheckingDuplicates = false;
  bool _showingDuplicates = false;
  bool _soldAndAvailableOnly = false;
  List<Map<String, dynamic>> _duplicatePairs = [];
  List<Map<String, dynamic>> _visibleDuplicatePairs = [];

  @override
  void initState() {
    super.initState();
    _searchController = InventorySearchController(
      onlyUnsold: false,
      allowFallbackOnManualSearch: false,
      imageMaxResults: 100,
      gateway: widget.searchGateway,
    );
    _searchController.applyFiltersAndSearch();
    if (widget.checkMissingEmbeddings) {
      _refreshMissingEmbeddings();
    } else {
      _checkedMissingEmbeddings = true;
      _hasMissingEmbeddings = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectInventoryMenuAction(String action) {
    switch (action) {
      case 'backfill':
        _backfillImageEmbeddings();
      case 'duplicates':
        _checkPossibleDuplicates();
      case 'intake':
        Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const InventoryScreen()),
        );
      case 'dashboard':
        Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const SalesDashboardScreen()),
        );
      case 'sale':
        Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const SalesScreen()),
        ).then((recorded) {
          if (recorded == true && mounted) _refreshCurrentInventoryView();
        });
    }
  }

  Future<void> _refreshCurrentInventoryView() async {
    if (_showingDuplicates) {
      setState(() => _showingDuplicates = false);
    }
    await _searchController.applyFiltersAndSearch();
  }

  Future<void> _refreshMissingEmbeddings() async {
    try {
      final hasMissing = await ImageInventorySearch.hasMissingEmbeddings();
      if (!mounted) return;
      setState(() {
        _hasMissingEmbeddings = hasMissing;
        _checkedMissingEmbeddings = true;
      });
    } catch (error) {
      debugPrint('Could not check for missing image vectors: $error');
    }
  }

  Future<void> _searchByPhoto(ImageSource source) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (photo == null || !mounted) return;
      if (_showingDuplicates) {
        setState(() {
          _showingDuplicates = false;
          _soldAndAvailableOnly = false;
          _duplicatePairs = [];
          _visibleDuplicatePairs = [];
        });
      }
      await _searchController.setImage(SearchImageInput.fromXFile(photo));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo search failed: $error')));
      }
    }
  }

  Future<void> _backfillImageEmbeddings() async {
    setState(() => _isBackfillingEmbeddings = true);
    try {
      final result = await ImageInventorySearch.backfillMissing(
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() => _embeddingProgress = '$completed/$total');
        },
      );
      if (!mounted) return;
      if (result.total == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No inventory photos are missing embeddings.'),
          ),
        );
      } else {
        final errorSummary = result.errors.take(5).join('\n\n');
        final moreErrors = result.errors.length > 5
            ? '\n\n…and ${result.errors.length - 5} more errors.'
            : '';
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              result.stoppedEarly
                  ? 'Embedding backfill paused'
                  : 'Embedding backfill complete',
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(
                  'Updated ${result.updated} of ${result.total} photos. '
                  '${result.failed} failed; attempted ${result.attempted}.'
                  '${result.stoppedEarly ? '\n\nStopped after 3 consecutive errors. Remaining photos were left untouched.' : ''}'
                  '${errorSummary.isEmpty ? '' : '\n\n$errorSummary$moreErrors'}',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      await _refreshMissingEmbeddings();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Embedding backfill failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackfillingEmbeddings = false;
          _embeddingProgress = null;
        });
      }
    }
  }

  Future<void> _checkPossibleDuplicates() async {
    if (_showingDuplicates) {
      setState(() {
        _showingDuplicates = false;
        _soldAndAvailableOnly = false;
        _duplicatePairs = [];
        _visibleDuplicatePairs = [];
      });
      await _searchController.applyFiltersAndSearch();
      return;
    }
    setState(() => _isCheckingDuplicates = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'find_possible_inventory_duplicates',
      );
      final pairs = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _duplicatePairs = pairs;
        _soldAndAvailableOnly = false;
        _showingDuplicates = true;
      });
      _applyDuplicateFilter();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check duplicates: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingDuplicates = false);
    }
  }

  void _applyDuplicateFilter() {
    final visiblePairs = <Map<String, dynamic>>[];
    for (final pair in _duplicatePairs) {
      final first = Map<String, dynamic>.from(pair['first_item'] as Map);
      final second = Map<String, dynamic>.from(pair['second_item'] as Map);
      final firstId = first['id']?.toString();
      final secondId = second['id']?.toString();
      if (firstId == null || secondId == null || firstId == secondId) continue;
      final firstIsSold = first['is_sold'] == true;
      final secondIsSold = second['is_sold'] == true;
      if (_soldAndAvailableOnly && firstIsSold == secondIsSold) continue;
      visiblePairs.add(pair);
    }
    setState(() => _visibleDuplicatePairs = visiblePairs);
  }

  String? _duplicatePairKey(Map<String, dynamic> pair) {
    final first = Map<String, dynamic>.from(pair['first_item'] as Map);
    final second = Map<String, dynamic>.from(pair['second_item'] as Map);
    final firstId = first['id']?.toString();
    final secondId = second['id']?.toString();
    if (firstId == null || secondId == null || firstId == secondId) return null;
    final sorted = [firstId, secondId]..sort();
    return '${sorted[0]}|${sorted[1]}';
  }

  Future<void> _ignoreDuplicatePair(Map<String, dynamic> pair) async {
    final first = Map<String, dynamic>.from(pair['first_item'] as Map);
    final second = Map<String, dynamic>.from(pair['second_item'] as Map);
    final firstId = first['id']?.toString();
    final secondId = second['id']?.toString();
    final pairKey = _duplicatePairKey(pair);
    if (firstId == null || secondId == null || pairKey == null) return;

    try {
      await Supabase.instance.client
          .from('inventory_duplicate_exclusions')
          .insert({'item_a': firstId, 'item_b': secondId});
      if (!mounted) return;
      _duplicatePairs.removeWhere(
        (candidate) => _duplicatePairKey(candidate) == pairKey,
      );
      _applyDuplicateFilter();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This pair will be hidden from duplicate results.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not exclude this pair: $error')),
        );
      }
    }
  }

  Widget _buildDuplicatePairCard(Map<String, dynamic> pair, int index) {
    final first = Map<String, dynamic>.from(pair['first_item'] as Map);
    final second = Map<String, dynamic>.from(pair['second_item'] as Map);
    final similarity =
        ((pair['description_similarity'] as num?)?.toDouble() ?? 0) * 100;
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text('Possible match ${index + 1}'),
            subtitle: Text(
              '${similarity.toStringAsFixed(0)}% description match',
            ),
            trailing: TextButton.icon(
              onPressed: () => _ignoreDuplicatePair(pair),
              icon: const Icon(Icons.not_interested, size: 18),
              label: const Text('Not a duplicate'),
            ),
          ),
          const Divider(height: 1),
          _buildDuplicateItemTile(first),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _buildDuplicateItemTile(second),
        ],
      ),
    );
  }

  Widget _buildDuplicateItemTile(Map<String, dynamic> item) {
    final imageUrl = item['image_url']?.toString() ?? '';
    final isSold = item['is_sold'] == true;
    final details =
        [
              item['brand'],
              item['category'],
              item['color'],
              '${item['price_est'] ?? '-'} Ft',
              item['location'],
            ]
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .join(' · ');
    return ListTile(
      onTap: () => _showEditSheet(item),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56,
          height: 56,
          child: imageUrl.isEmpty
              ? const ColoredBox(
                  color: Color(0xFFECEFF1),
                  child: Icon(Icons.image_not_supported, color: Colors.grey),
                )
              : CachedRemoteImage(imageUrl, fit: BoxFit.cover, thumbnail: true),
        ),
      ),
      title: Text(
        item['name']?.toString() ?? 'Unknown item',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        isSold ? 'SOLD' : 'AVAILABLE',
        style: TextStyle(
          color: isSold ? Colors.red.shade700 : Colors.green.shade700,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _addToSale(Map<String, dynamic> item) async {
    final recorded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SalesScreen(initialItems: [item])),
    );
    if (recorded == true && mounted) {
      await _refreshCurrentInventoryView();
    }
  }

  Future<void> _updateItem(
    dynamic id,
    String name,
    String brand,
    double price,
    String category,
    String gender,
    String location,
    bool isSold,
  ) async {
    await Supabase.instance.client
        .from('inventory')
        .update({
          'name': name,
          'brand': brand,
          'price_est': price,
          'category': category,
          'gender': gender,
          'location': location,
          'is_sold': isSold,
        })
        .eq('id', id);

    if (mounted) Navigator.pop(context);
    if (_showingDuplicates) {
      await _checkPossibleDuplicates();
    } else {
      await _searchController.applyFiltersAndSearch();
    }
  }

  Future<void> _deleteItem(dynamic id) async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Törlés (Delete)'),
            content: const Text('Biztosan törlöd ezt a terméket?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Mégse'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Törlés',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await Supabase.instance.client.from('inventory').delete().eq('id', id);

      if (mounted) {
        Navigator.pop(context);
      }

      if (_showingDuplicates) {
        await _checkPossibleDuplicates();
      } else {
        await _searchController.applyFiltersAndSearch();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Termék törölve! (Deleted)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditSheet(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(
      text: item['name']?.toString() ?? '',
    );
    final brandCtrl = TextEditingController(
      text: item['brand']?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: item['price_est']?.toString() ?? '',
    );
    final sizeCtrl = TextEditingController(
      text: item['size']?.toString() ?? '',
    );

    bool itemIsSold = item['is_sold'] == true;
    final imageUrl = item['image_url'] as String?;

    const editCategories = clothingCategories;

    String selectedCat = editCategories.contains(item['category'])
        ? item['category'].toString()
        : defaultClothingCategory;
    String selectedGender = genderOptions.contains(item['gender'])
        ? item['gender'].toString()
        : defaultClothingGender;
    String selectedLocation = _locations.contains(item['location'])
        ? item['location'].toString()
        : _locations.first;

    showSafeBottomSheet(
      context: context,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _showFullImage(imageUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 300,
                      width: double.infinity,
                      color: Colors.black12,
                      child: CachedRemoteImage(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Termék Szerkesztése',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              SwitchListTile(
                title: const Text(
                  'Eladva (Mark as Sold)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                activeThumbColor: Colors.green,
                value: itemIsSold,
                onChanged: (bool val) {
                  setSheetState(() => itemIsSold = val);
                },
              ),
              const Divider(),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Név',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brandCtrl,
                decoration: const InputDecoration(
                  labelText: 'Márka',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ár (Ft)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sizeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Méret',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedCat,
                decoration: const InputDecoration(
                  labelText: 'Kategória',
                  border: OutlineInputBorder(),
                ),
                items: editCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setSheetState(() => selectedCat = val);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Nem / Gender',
                  border: OutlineInputBorder(),
                ),
                items: genderOptions
                    .map(
                      (gender) =>
                          DropdownMenuItem(value: gender, child: Text(gender)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => selectedGender = value);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedLocation,
                decoration: const InputDecoration(
                  labelText: 'Store location',
                  border: OutlineInputBorder(),
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
                    setSheetState(() => selectedLocation = value);
                  }
                },
              ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteItem(item['id']),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        'Törlés',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        _updateItem(
                          item['id'],
                          nameCtrl.text,
                          brandCtrl.text,
                          double.tryParse(priceCtrl.text) ?? 0.0,
                          selectedCat,
                          selectedGender,
                          selectedLocation,
                          itemIsSold,
                        );
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('Mentés'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Colors.green[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }

  void _showFullImage(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: MediaQuery.sizeOf(dialogContext).width * 0.9,
          height: MediaQuery.sizeOf(dialogContext).height * 0.8,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: CachedRemoteImage(
              imageUrl,
              fit: BoxFit.contain,
              cacheWidth: null,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDuplicatesBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Possible duplicate pairs · ${_visibleDuplicatePairs.length}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            'Matches require the same brand, exact price, category, and color family, plus a similar description.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('All possible duplicates'),
                selected: !_soldAndAvailableOnly,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() => _soldAndAvailableOnly = false);
                  _applyDuplicateFilter();
                },
              ),
              FilterChip(
                label: const Text('Sold item + unsold copy'),
                selected: _soldAndAvailableOnly,
                onSelected: (selected) {
                  setState(() => _soldAndAvailableOnly = selected);
                  _applyDuplicateFilter();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _isCheckingDuplicates
              ? const Center(child: CircularProgressIndicator())
              : _visibleDuplicatePairs.isEmpty
              ? const Center(
                  child: Text(
                    'No likely duplicates found.',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _visibleDuplicatePairs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, index) => _buildDuplicatePairCard(
                    _visibleDuplicatePairs[index],
                    index,
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Készlet (Inventory)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<ImageSource>(
            tooltip: 'Search by photo',
            icon: const Icon(Icons.image_search),
            onSelected: _searchByPhoto,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: ImageSource.gallery,
                child: Text('Choose photo'),
              ),
              PopupMenuItem(
                value: ImageSource.camera,
                child: Text('Take photo'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: _isBackfillingEmbeddings
                ? 'Generating vectors ${_embeddingProgress ?? ''}'
                : 'More inventory actions',
            icon: _isBackfillingEmbeddings
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            onSelected: _isBackfillingEmbeddings
                ? null
                : _selectInventoryMenuAction,
            itemBuilder: (context) => [
              if (!_checkedMissingEmbeddings || _hasMissingEmbeddings)
                PopupMenuItem(
                  value: 'backfill',
                  enabled: !_isBackfillingEmbeddings,
                  child: Text(
                    _isBackfillingEmbeddings
                        ? 'Generating vectors ${_embeddingProgress ?? ''}…'
                        : 'Generate vectors for all items',
                  ),
                ),
              PopupMenuItem(
                value: 'duplicates',
                enabled: !_isCheckingDuplicates,
                child: Text(
                  _showingDuplicates
                      ? 'Show all inventory'
                      : 'Check possible duplicates',
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'intake',
                child: Text('Add inventory items'),
              ),
              const PopupMenuItem(value: 'sale', child: Text('Record a sale')),
              const PopupMenuItem(
                value: 'dashboard',
                child: Text('Sales dashboard'),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: _showingDuplicates
          ? _buildDuplicatesBody()
          : InventorySearchView(
              key: const ValueKey('inventory-list-search'),
              controller: _searchController,
              initiallyExpanded: false,
              emptyMessage: 'Nincs találat (No items found)',
              imageActions: TextButton.icon(
                onPressed: () => _searchController.clearImage(),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear photo'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              itemOverlayBuilder: (context, item) {
                final isSold = item['is_sold'] == true;
                if (isSold) {
                  return Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'SOLD',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Add to sale',
                        icon: const Icon(Icons.add_shopping_cart),
                        onPressed: () => _addToSale(item),
                      ),
                    ),
                  ),
                );
              },
              onItemTap: _showEditSheet,
            ),
    );
  }
}
