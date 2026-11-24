import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yoaron_app/widgets/safe_bottom_sheet.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
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
          SnackBar(content: Text('Hiba: $e'), backgroundColor: Colors.red),
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
            item['name']?.toString() ?? 'Ismeretlen Termék',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            item['brand']?.toString() ?? 'Ismeretlen Márka',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const Divider(height: 30),
          _buildDetailRow(
            'Ár (Price):',
            '${item['price_est']} Ft',
            isHighlight: true,
          ),
          _buildDetailRow('Kategória:', item['category']?.toString() ?? '-'),
          _buildDetailRow('Nem / Gender:', item['gender']?.toString() ?? '-'),
          _buildDetailRow(
            'Location:',
            item['location']?.toString() ?? 'Csengery',
          ),
          _buildDetailRow('Méret (Size):', item['size']?.toString() ?? '-'),
          _buildDetailRow('Szín (Color):', item['color']?.toString() ?? '-'),
          _buildDetailRow('Minta (Pattern):', item['pattern']?.toString() ?? '-'),
          _buildDetailRow(
            'Állapot (Condition):',
            item['condition']?.toString() ?? '-',
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keresés'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<ImageSource>(
            tooltip: 'Search by photo',
            icon: const Icon(Icons.image_search),
            onSelected: _pickImage,
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
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: InventorySearchView(
        key: const ValueKey('standalone-search-screen'),
        controller: _searchController,
        initiallyExpanded: true,
        emptyMessage: 'No unsold inventory items found.',
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
        onItemTap: _showItemDetails,
      ),
    );
  }
}
