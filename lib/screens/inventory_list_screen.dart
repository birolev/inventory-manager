import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/widgets/cached_remote_image.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';
import '../theme/app_theme.dart';
import '../widgets/inventory_search_view.dart';
import '../widgets/safe_bottom_sheet.dart';
import 'sales_screen.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({
    super.key,
    this.searchGateway = const SupabaseInventorySearchGateway(),
    this.checkMissingEmbeddings = true,
    this.onOpenAccount,
    this.refreshListenable,
    this.onSaleRecorded,
  });

  final InventorySearchGateway searchGateway;
  final bool checkMissingEmbeddings;
  final VoidCallback? onOpenAccount;
  final ValueListenable<int>? refreshListenable;
  final VoidCallback? onSaleRecorded;

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
      initialSaleStatus: InventorySaleStatusFilter.all,
      allowFallbackOnManualSearch: false,
      imageMaxResults: 100,
      gateway: widget.searchGateway,
    );
    _searchController.addListener(_onSearchControllerChanged);
    widget.refreshListenable?.addListener(_onExternalRefresh);
    _searchController.applyFiltersAndSearch();
    if (widget.checkMissingEmbeddings) {
      _refreshMissingEmbeddings();
    } else {
      _checkedMissingEmbeddings = true;
      _hasMissingEmbeddings = false;
    }
  }

  @override
  void didUpdateWidget(covariant InventoryListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_onExternalRefresh);
      widget.refreshListenable?.addListener(_onExternalRefresh);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_onExternalRefresh);
    _searchController.removeListener(_onSearchControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onExternalRefresh() {
    if (!mounted) return;
    if (_showingDuplicates) {
      _checkPossibleDuplicates();
    } else {
      _searchController.applyFiltersAndSearch();
    }
  }

  void _selectInventoryMenuAction(String action) {
    switch (action) {
      case 'backfill':
        _backfillImageEmbeddings();
      case 'duplicates':
        _checkPossibleDuplicates();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotós keresési hiba: $error'),
            backgroundColor: AppColors.brick,
          ),
        );
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
            content: Text('Minden termékfotóhoz létezik már keresési vektor.'),
          ),
        );
      } else {
        final errorSummary = result.errors.take(5).join('\n\n');
        final moreErrors = result.errors.length > 5
            ? '\n\n…és további ${result.errors.length - 5} hiba.'
            : '';
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              result.stoppedEarly
                  ? 'Vektorgenerálás szüneteltetve'
                  : 'Vektorgenerálás kész',
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(
                  '${result.updated} / ${result.total} fotó frissítve. '
                  '${result.failed} sikertelen; feldolgozva: ${result.attempted}.'
                  '${result.stoppedEarly ? '\n\n3 egymást követő hiba után leállítva. A többi fotó változatlan maradt.' : ''}'
                  '${errorSummary.isEmpty ? '' : '\n\n$errorSummary$moreErrors'}',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Bezárás'),
              ),
            ],
          ),
        );
      }
      await _refreshMissingEmbeddings();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vektorgenerálás sikertelen: $error'),
            backgroundColor: AppColors.brick,
          ),
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
          SnackBar(
            content: Text('Nem sikerült ellenőrizni a duplikátumokat: $error'),
            backgroundColor: AppColors.brick,
          ),
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
          content: Text('Ez a pár a jövőben el lesz rejtve a duplikátumokból.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nem sikerült kizárni a párt: $error'),
            backgroundColor: AppColors.brick,
          ),
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
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              'Lehetséges egyezés #${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${similarity.toStringAsFixed(0)}% leírás-egyezés'),
            trailing: TextButton.icon(
              onPressed: () => _ignoreDuplicatePair(pair),
              icon: const Icon(Icons.not_interested, size: 18),
              label: const Text('Nem duplikátum'),
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
              AppFormat.forint(item['price_est']),
              item['location'],
            ]
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .join(' · ');
    final p = context.palette;
    return ListTile(
      onTap: () => _showEditSheet(item),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: imageUrl.isEmpty
              ? ColoredBox(
                  color: p.surfaceMuted,
                  child: Icon(
                    Icons.checkroom_outlined,
                    color: p.inkMuted,
                  ),
                )
              : CachedRemoteImage(imageUrl, fit: BoxFit.cover, thumbnail: true),
        ),
      ),
      title: Text(
        item['name']?.toString() ?? 'Ismeretlen termék',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSold ? p.brickSoft : p.oliveSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isSold ? 'ELADVA' : 'ELÉRHETŐ',
          style: TextStyle(
            color: isSold ? p.brick : p.olive,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
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
      widget.onSaleRecorded?.call();
      await _refreshCurrentInventoryView();
    }
  }

  Future<void> _updateItem({
    required dynamic id,
    required String name,
    required String brand,
    required double price,
    required String size,
    required String category,
    required List<String> secondaryCategories,
    required String gender,
    required String location,
    required String color,
    required String pattern,
    required String condition,
    required bool isSold,
  }) async {
    await Supabase.instance.client
        .from('inventory')
        .update({
          'name': name.trim(),
          'brand': brand.trim(),
          'price_est': price,
          'size': size.trim(),
          'category': category,
          'secondary_categories': secondaryCategories
              .where((c) => c != category)
              .toSet()
              .toList(),
          'gender': gender,
          'location': location,
          'color': color.trim(),
          'pattern': pattern.trim(),
          'condition': condition.trim(),
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
            title: const Text('Termék törlése'),
            content: const Text('Biztosan törlöd ezt a terméket a készletből?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Mégse'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.brick),
                child: const Text('Törlés'),
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
            content: Text('Termék törölve.'),
            backgroundColor: AppColors.brick,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba: $e'), backgroundColor: AppColors.brick),
        );
      }
    }
  }

  String _formatMetadataDate(dynamic raw) {
    final dt = InventorySearch.parseTimestamp(raw)?.toLocal();
    if (dt == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}.${two(dt.month)}.${two(dt.day)}. ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _metadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: context.palette.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(fontSize: 12, color: context.palette.ink),
            ),
          ),
        ],
      ),
    );
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
    final colorCtrl = TextEditingController(
      text: item['color']?.toString() ?? '',
    );
    final patternCtrl = TextEditingController(
      text: item['pattern']?.toString() ?? '',
    );
    final conditionCtrl = TextEditingController(
      text: item['condition']?.toString() ?? '',
    );

    bool itemIsSold = item['is_sold'] == true;
    final imageUrl = item['image_url'] as String?;

    const editCategories = clothingCategories;

    String selectedCat = editCategories.contains(item['category'])
        ? item['category'].toString()
        : defaultClothingCategory;
    final secondaryCats =
        (item['secondary_categories'] as List? ?? const [])
            .map((e) => e.toString())
            .where((c) => editCategories.contains(c) && c != selectedCat)
            .toSet();
    String selectedGender = genderOptions.contains(item['gender'])
        ? item['gender'].toString()
        : defaultClothingGender;
    String selectedLocation = _locations.contains(item['location'])
        ? item['location'].toString()
        : _locations.first;

    final uploaderName = item['uploaded_by_name']?.toString().trim() ?? '';
    final uploaderEmail = item['uploaded_by_email']?.toString().trim() ?? '';
    final uploaderDisplay = uploaderName.isNotEmpty
        ? (uploaderEmail.isNotEmpty && uploaderEmail != uploaderName
              ? '$uploaderName ($uploaderEmail)'
              : uploaderName)
        : (uploaderEmail.isNotEmpty ? uploaderEmail : 'Ismeretlen');

    showSafeBottomSheet(
      context: context,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final p = context.palette;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _showFullImage(imageUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 260,
                      width: double.infinity,
                      color: p.surfaceMuted,
                      child: CachedRemoteImage(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 48,
                            color: p.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                'Termék szerkesztése',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Card(
                color: itemIsSold ? p.brickSoft : p.oliveSoft,
                child: SwitchListTile(
                  title: Text(
                    itemIsSold ? 'Eladva' : 'Elérhető készleten',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: itemIsSold ? p.brick : p.olive,
                    ),
                  ),
                  activeThumbColor: p.brick,
                  value: itemIsSold,
                  onChanged: (bool val) {
                    setSheetState(() => itemIsSold = val);
                  },
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Név'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: brandCtrl,
                decoration: const InputDecoration(labelText: 'Márka'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ár',
                        suffixText: 'Ft',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sizeCtrl,
                      decoration: const InputDecoration(labelText: 'Méret'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: selectedCat,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategória'),
                items: editCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setSheetState(() {
                      selectedCat = val;
                      secondaryCats.remove(val);
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedGender,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Nem'),
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
                          setSheetState(() => selectedGender = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedLocation,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Üzlet'),
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
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: colorCtrl,
                      decoration: const InputDecoration(labelText: 'Szín'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: patternCtrl,
                      decoration: const InputDecoration(labelText: 'Minta'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: conditionCtrl,
                decoration: const InputDecoration(labelText: 'Állapot'),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  'További részletek és metaadatok',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.inkMuted,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Másodlagos kategóriák',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: editCategories
                        .where((category) => category != selectedCat)
                        .map(
                          (category) => FilterChip(
                            label: Text(category),
                            selected: secondaryCats.contains(category),
                            onSelected: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  secondaryCats.add(category);
                                } else {
                                  secondaryCats.remove(category);
                                }
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const Divider(height: 20),
                  _metadataRow('Feltöltötte:', uploaderDisplay),
                  _metadataRow(
                    'Feltöltés ideje:',
                    _formatMetadataDate(item['created_at']),
                  ),
                  _metadataRow(
                    'Azonosító:',
                    item['id']?.toString() ?? '-',
                  ),
                  const SizedBox(height: 6),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteItem(item['id']),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.brick,
                      ),
                      label: const Text(
                        'Törlés',
                        style: TextStyle(color: AppColors.brick),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.brick),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        _updateItem(
                          id: item['id'],
                          name: nameCtrl.text,
                          brand: brandCtrl.text,
                          price: double.tryParse(priceCtrl.text) ?? 0.0,
                          size: sizeCtrl.text,
                          category: selectedCat,
                          secondaryCategories: secondaryCats.toList(),
                          gender: selectedGender,
                          location: selectedLocation,
                          color: colorCtrl.text,
                          pattern: patternCtrl.text,
                          condition: conditionCtrl.text,
                          isSold: itemIsSold,
                        );
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Mentés'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.olive,
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
                  child: CachedRemoteImage(
                    imageUrl,
                    fit: BoxFit.contain,
                    cacheWidth: null,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: Colors.white54,
                      ),
                    ),
                  ),
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

  Widget _buildDuplicatesBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            'Lehetséges duplikátumok · ${_visibleDuplicatePairs.length} pár',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Az egyezések azonos márkát, árat, kategóriát, színcsaládot és hasonló leírást igényelnek.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Összes duplikátum'),
                selected: !_soldAndAvailableOnly,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() => _soldAndAvailableOnly = false);
                  _applyDuplicateFilter();
                },
              ),
              FilterChip(
                label: const Text('Eladott + elérhető pár'),
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
                    'Nem található valószínű duplikátum.',
                    style: TextStyle(fontSize: 16, color: AppColors.inkMuted),
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
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(_showingDuplicates ? 'Duplikátumok' : 'Készlet'),
        actions: [
          PopupMenuButton<ImageSource>(
            tooltip: 'Keresés fotóval',
            icon: const Icon(Icons.image_search),
            onSelected: _searchByPhoto,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: ImageSource.gallery,
                child: Text('Fotó kiválasztása'),
              ),
              PopupMenuItem(
                value: ImageSource.camera,
                child: Text('Fotózás kamerával'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: _isBackfillingEmbeddings
                ? 'Vektorok generálása ${_embeddingProgress ?? ''}'
                : 'Készlet eszközök',
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
                        ? 'Vektorok generálása ${_embeddingProgress ?? ''}…'
                        : 'Hiányzó vektorok generálása',
                  ),
                ),
              PopupMenuItem(
                value: 'duplicates',
                enabled: !_isCheckingDuplicates,
                child: Text(
                  _showingDuplicates
                      ? 'Teljes készlet mutatása'
                      : 'Duplikátumok ellenőrzése',
                ),
              ),
            ],
          ),
          if (widget.onOpenAccount != null)
            IconButton(
              tooltip: 'Fiók',
              onPressed: widget.onOpenAccount,
              icon: const Icon(Icons.person_outline),
            ),
        ],
      ),
      body: _showingDuplicates
          ? _buildDuplicatesBody()
          : InventorySearchView(
              key: const ValueKey('inventory-list-search'),
              controller: _searchController,
              initiallyExpanded: false,
              emptyMessage: 'Nem található termék a megadott szűrőkkel.',
              topBanner: SizedBox(
                width: double.infinity,
                child: SegmentedButton<InventorySaleStatusFilter>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    backgroundColor: p.surface,
                    selectedBackgroundColor: p.accentSoft,
                    selectedForegroundColor: p.accent,
                    foregroundColor: p.inkMuted,
                    side: BorderSide(color: p.border),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: InventorySaleStatusFilter.available,
                      label: Text('Elérhető'),
                    ),
                    ButtonSegment(
                      value: InventorySaleStatusFilter.sold,
                      label: Text('Eladva'),
                    ),
                    ButtonSegment(
                      value: InventorySaleStatusFilter.all,
                      label: Text('Összes'),
                    ),
                  ],
                  selected: {_searchController.saleStatusFilter},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    _searchController.setSaleStatusFilter(selection.first);
                  },
                ),
              ),
              imageActions: TextButton.icon(
                onPressed: () => _searchController.clearImage(),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Fotó törlése'),
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
                      padding: const EdgeInsets.all(8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.brick,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          child: Text(
                            'ELADVA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
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
                    padding: const EdgeInsets.all(6),
                    child: Material(
                      color: p.surface.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Eladáshoz adás',
                        icon: Icon(
                          Icons.add_shopping_cart,
                          size: 19,
                          color: p.ink,
                        ),
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
