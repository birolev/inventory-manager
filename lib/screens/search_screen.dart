import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yoaron_app/widgets/safe_bottom_sheet.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../theme/app_theme.dart';
import '../widgets/inventory_search_view.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.searchGateway = const SupabaseInventorySearchGateway(),
    this.initialImage,
  });

  final InventorySearchGateway searchGateway;
  final SearchImageInput? initialImage;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ImagePicker _picker = ImagePicker();
  late final InventorySearchController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = InventorySearchController(
      onlyUnsold: true,
      allowFallbackOnManualSearch: false,
      imageMaxResults: 100,
      initialImage: widget.initialImage,
      gateway: widget.searchGateway,
    );
    if (widget.initialImage != null) {
      _searchController.analyzeImage();
    } else {
      _searchController.applyFiltersAndSearch();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (pickedFile == null || !mounted) return;
      await _searchController.setImage(SearchImageInput.fromXFile(pickedFile));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hiba: $e'), backgroundColor: AppColors.brick),
        );
      }
    }
  }

  void _showItemDetails(Map<String, dynamic> item) {
    showSafeBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['name']?.toString() ?? 'Ismeretlen termék',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            item['brand']?.toString() ?? 'Ismeretlen márka',
            style: const TextStyle(fontSize: 15, color: AppColors.inkMuted),
          ),
          const Divider(height: 28),
          _buildDetailRow(
            'Ár:',
            AppFormat.forint(item['price_est']),
            isHighlight: true,
          ),
          _buildDetailRow('Kategória:', item['category']?.toString() ?? '-'),
          _buildDetailRow('Nem:', item['gender']?.toString() ?? '-'),
          _buildDetailRow(
            'Üzlet:',
            item['location']?.toString() ?? 'Csengery',
          ),
          _buildDetailRow('Méret:', item['size']?.toString() ?? '-'),
          _buildDetailRow('Szín:', item['color']?.toString() ?? '-'),
          _buildDetailRow('Minta:', item['pattern']?.toString() ?? '-'),
          _buildDetailRow('Állapot:', item['condition']?.toString() ?? '-'),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text('Rendben'),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
              fontSize: isHighlight ? 18 : 15,
              color: isHighlight ? AppColors.olive : AppColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keresés'),
        actions: [
          PopupMenuButton<ImageSource>(
            tooltip: 'Keresés fotóval',
            icon: const Icon(Icons.image_search),
            onSelected: _pickImage,
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
        ],
      ),
      body: InventorySearchView(
        key: const ValueKey('standalone-search-screen'),
        controller: _searchController,
        initiallyExpanded: true,
        emptyMessage: 'Nem található eladatlan termék.',
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
        onItemTap: _showItemDetails,
      ),
    );
  }
}
