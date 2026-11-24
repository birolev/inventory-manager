import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/widgets/cached_remote_image.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';

/// Canonical, reusable category- and image-based inventory search interface.
///
/// Matches the sales-logging post-analysis layout across every search screen.
/// When [controller.hasImage] is false (manual searches), the uploaded image
/// and photo search method sections are omitted while keeping all filters,
/// sorting controls, and result cards identical.
class InventorySearchView extends StatefulWidget {
  const InventorySearchView({
    super.key,
    required this.controller,
    this.topBanner,
    this.imageActions,
    this.initiallyExpanded = true,
    this.emptyMessage = 'No unsold inventory items found.',
    this.isItemSelected,
    this.isItemDisabled,
    this.itemOverlayBuilder,
    this.onItemTap,
    this.bottomBar,
    this.maxFilterPanelHeight = 390,
  });

  final InventorySearchController controller;
  final Widget? topBanner;
  final Widget? imageActions;
  final bool initiallyExpanded;
  final String emptyMessage;
  final bool Function(Map<String, dynamic> item)? isItemSelected;
  final bool Function(Map<String, dynamic> item)? isItemDisabled;
  final Widget? Function(BuildContext context, Map<String, dynamic> item)?
  itemOverlayBuilder;
  final void Function(Map<String, dynamic> item)? onItemTap;
  final Widget? bottomBar;
  final double maxFilterPanelHeight;

  @override
  State<InventorySearchView> createState() => _InventorySearchViewState();
}

class _InventorySearchViewState extends State<InventorySearchView> {
  late bool _filtersExpanded = widget.initiallyExpanded;
  bool _imageExpanded = true;
  int _syncedRevision = -1;

  final TextEditingController _sizeController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _patternController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _syncControllersFromState(force: true);
  }

  @override
  void didUpdateWidget(covariant InventorySearchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _syncedRevision = -1;
      _syncControllersFromState(force: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _sizeController.dispose();
    _colorController.dispose();
    _patternController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _conditionController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _syncControllersFromState();
    if (mounted) setState(() {});
  }

  void _syncControllersFromState({bool force = false}) {
    final c = widget.controller;
    if (!force && _syncedRevision == c.filterRevision) return;
    _syncedRevision = c.filterRevision;
    _setTextIfDifferent(_sizeController, c.sizeFilter);
    _setTextIfDifferent(_colorController, c.colorFilter);
    _setTextIfDifferent(_patternController, c.patternFilter);
    _setTextIfDifferent(_nameController, c.nameFilter);
    _setTextIfDifferent(_brandController, c.brandFilter);
    _setTextIfDifferent(_conditionController, c.conditionFilter);
  }

  void _setTextIfDifferent(TextEditingController controller, String text) {
    if (controller.text != text) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
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

  Widget _buildFilterTextField({
    required TextEditingController textController,
    required String label,
    String? hintText,
    IconData? prefixIcon,
    required ValueChanged<String> onChanged,
  }) {
    final controller = widget.controller;
    return TextField(
      controller: textController,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: (_) => controller.applyFiltersAndSearch(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: 'Apply $label filter',
          icon: const Icon(Icons.search),
          onPressed: controller.isLoading
              ? null
              : controller.applyFiltersAndSearch,
        ),
      ),
    );
  }

  void _showFullPhoto(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(dialogContext).width * 0.9,
              height: MediaQuery.sizeOf(dialogContext).height * 0.8,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(InventorySearchController controller) {
    final isGemini = controller.searchMode == ImageSearchMode.gemini;
    final bytes = controller.imageBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isGemini ? 'Photo search (Gemini)' : 'Photo search (Vectors)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('toggle-image-section'),
              onPressed: () =>
                  setState(() => _imageExpanded = !_imageExpanded),
              icon: Icon(
                _imageExpanded ? Icons.expand_less : Icons.image_outlined,
              ),
              label: Text(_imageExpanded ? 'Hide' : 'Show'),
            ),
          ],
        ),
        if (_imageExpanded) ...[
          Row(
            children: [
              if (bytes != null)
                GestureDetector(
                  onTap: () => _showFullPhoto(bytes),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          bytes,
                          width: 92,
                          height: 112,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const Positioned(
                        right: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.zoom_in,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.isLoading)
                      Text(
                        isGemini
                            ? 'Analyzing photo with Gemini…'
                            : 'Searching with embedded vectors…',
                      )
                    else if (controller.error != null)
                      Text(
                        controller.error!,
                        style: const TextStyle(color: Colors.red),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        isGemini
                            ? 'AI match: ${controller.aiCriteria?['category'] ?? '-'} · '
                                  '${controller.aiCriteria?['gender'] ?? '-'} · '
                                  '${controller.aiCriteria?['color'] ?? '-'}'
                            : 'Embedded vector results',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    if (widget.imageActions != null) ...[
                      const SizedBox(height: 6),
                      widget.imageActions!,
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ImageSearchMode>(
            key: ValueKey(
              'search-mode-${controller.searchMode.name}-${controller.filterRevision}',
            ),
            initialValue: controller.searchMode,
            decoration: const InputDecoration(
              labelText: 'Photo search method',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: ImageSearchMode.embedded,
                child: Text('Embedded vectors'),
              ),
              DropdownMenuItem(
                value: ImageSearchMode.gemini,
                child: Text('Gemini analysis'),
              ),
            ],
            onChanged: (mode) {
              if (mode == null) return;
              controller.switchSearchMode(mode);
            },
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final selected = widget.isItemSelected?.call(item) ?? false;
    final disabled = widget.isItemDisabled?.call(item) ?? false;
    final overlay = widget.itemOverlayBuilder?.call(context, item);
    final imageUrl = item['image_url']?.toString();
    final price = item['price_est'];

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? Colors.green[50] : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? Colors.green : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: disabled || widget.onItemTap == null
            ? null
            : () => widget.onItemTap!(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black12,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? const Icon(Icons.image_not_supported)
                        : CachedRemoteImage(
                            imageUrl,
                            fit: BoxFit.cover,
                            thumbnail: true,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                          ),
                  ),
                  if (selected)
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
                  ?overlay,
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
                  Text('${price ?? 0} Ft'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isGeminiImage =
        controller.hasImage && controller.searchMode == ImageSearchMode.gemini;
    final categoryItems = filterCategories.contains(controller.selectedCategory)
        ? filterCategories
        : [...filterCategories, controller.selectedCategory];
    final genderItems =
        InventorySearch.genderFilterOptions.contains(controller.selectedGender)
        ? InventorySearch.genderFilterOptions
        : [...InventorySearch.genderFilterOptions, controller.selectedGender];
    final locationItems =
        InventorySearch.locationFilterOptions.contains(
          controller.selectedLocation,
        )
        ? InventorySearch.locationFilterOptions
        : [
            ...InventorySearch.locationFilterOptions,
            controller.selectedLocation,
          ];
    final sortOptions = controller.availableSortOptions;
    final currentSort = sortOptions.contains(controller.sortOption)
        ? controller.sortOption
        : sortOptions.first;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveMaxPanelHeight = constraints.hasBoundedHeight
            ? math.min(widget.maxFilterPanelHeight, constraints.maxHeight * 0.52)
            : widget.maxFilterPanelHeight;
        final bottomSafeInset = widget.bottomBar == null
            ? MediaQuery.paddingOf(context).bottom
            : 0.0;
        final isAnySectionExpanded =
            _filtersExpanded || (controller.hasImage && _imageExpanded);
        final hasScrollableResults =
            !controller.isLoading &&
            controller.error == null &&
            controller.results.isNotEmpty;
        final foldHeaderOnScroll = hasScrollableResults && !isAnySectionExpanded;

        final topPanelContent = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.topBanner != null) ...[
                widget.topBanner!,
                const SizedBox(height: 10),
              ],
              if (controller.hasImage) _buildImageSection(controller),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Search filters',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (controller.hasActiveFilters)
                    TextButton(
                      onPressed: controller.isLoading
                          ? null
                          : () => controller.resetFilters(),
                      child: const Text('Reset'),
                    ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _filtersExpanded = !_filtersExpanded),
                    icon: Icon(
                      _filtersExpanded ? Icons.expand_less : Icons.tune,
                    ),
                    label: Text(_filtersExpanded ? 'Hide' : 'Edit'),
                  ),
                ],
              ),
              if (_filtersExpanded) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'cat-${controller.selectedCategory}-${controller.filterRevision}',
                  ),
                  initialValue: controller.selectedCategory,
                  decoration: InputDecoration(
                    labelText: isGeminiImage
                        ? 'Search category (change AI result)'
                        : 'Search category',
                    prefixIcon: const Icon(Icons.category),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: categoryItems
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
                  onChanged: controller.isLoading
                      ? null
                      : (category) {
                          if (category == null) return;
                          controller.setCategory(category);
                        },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'gender-${controller.selectedGender}-${controller.filterRevision}',
                  ),
                  initialValue: controller.selectedGender,
                  decoration: InputDecoration(
                    labelText: isGeminiImage
                        ? 'Search gender (change AI result)'
                        : 'Search gender',
                    prefixIcon: const Icon(Icons.people),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: genderItems
                      .map(
                        (gender) => DropdownMenuItem(
                          value: gender,
                          child: Text(gender),
                        ),
                      )
                      .toList(),
                  onChanged: controller.isLoading
                      ? null
                      : (gender) {
                          if (gender == null) return;
                          controller.setGender(gender);
                        },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'loc-${controller.selectedLocation}-${controller.filterRevision}',
                  ),
                  initialValue: controller.selectedLocation,
                  decoration: const InputDecoration(
                    labelText: 'Inventory location',
                    prefixIcon: Icon(Icons.store),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: locationItems
                      .map(
                        (location) => DropdownMenuItem(
                          value: location,
                          child: Text(location),
                        ),
                      )
                      .toList(),
                  onChanged: controller.isLoading
                      ? null
                      : (location) {
                          if (location == null) return;
                          controller.setLocation(location);
                        },
                ),
                const SizedBox(height: 8),
                _responsivePair(
                  _buildFilterTextField(
                    textController: _sizeController,
                    label: 'Size',
                    hintText: 'M, 32, 42',
                    prefixIcon: Icons.straighten,
                    onChanged: controller.setSizeFilter,
                  ),
                  _buildFilterTextField(
                    textController: _colorController,
                    label: 'Color',
                    onChanged: controller.setColorFilter,
                  ),
                ),
                const SizedBox(height: 8),
                _responsivePair(
                  _buildFilterTextField(
                    textController: _patternController,
                    label: 'Pattern',
                    onChanged: controller.setPatternFilter,
                  ),
                  DropdownButtonFormField<InventorySortOption>(
                    key: ValueKey(
                      'sort-${currentSort.name}-${controller.searchMode.name}-${controller.filterRevision}',
                    ),
                    initialValue: currentSort,
                    decoration: const InputDecoration(
                      labelText: 'Sort matches',
                      prefixIcon: Icon(Icons.sort),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: sortOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                        )
                        .toList(),
                    onChanged: controller.isLoading
                        ? null
                        : (option) {
                            if (option == null) return;
                            controller.setSortOption(option);
                          },
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('More filters: name, brand, condition'),
                  children: [
                    _buildFilterTextField(
                      textController: _nameController,
                      label: 'Name',
                      onChanged: controller.setNameFilter,
                    ),
                    const SizedBox(height: 8),
                    _buildFilterTextField(
                      textController: _brandController,
                      label: 'Brand',
                      onChanged: controller.setBrandFilter,
                    ),
                    const SizedBox(height: 8),
                    _buildFilterTextField(
                      textController: _conditionController,
                      label: 'Condition',
                      onChanged: controller.setConditionFilter,
                    ),
                  ],
                ),
              ],
              if (!controller.isLoading &&
                  controller.usedFallback &&
                  controller.results.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No matches found, including the broader search using '
                    'category, location, and brand.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              if (!controller.isLoading &&
                  controller.results.isNotEmpty &&
                  controller.usedFallback)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'No exact matches; showing broader results using category, '
                    'location, and brand only.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                ),
              Text(
                '${controller.results.length} items · '
                'Searching: ${controller.activeFiltersSummary} · '
                'sorted by ${currentSort.shortDescription}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ],
          ),
        );

        return Column(
          children: [
            if (!foldHeaderOnScroll)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: effectiveMaxPanelHeight),
                child: SingleChildScrollView(child: topPanelContent),
              ),
            if (controller.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (controller.error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          controller.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: controller.hasImage
                              ? controller.analyzeImage
                              : controller.applyFiltersAndSearch,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            controller.hasImage
                                ? 'Retry analysis'
                                : 'Retry search',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (controller.results.isEmpty)
              Expanded(child: Center(child: Text(widget.emptyMessage)))
            else if (foldHeaderOnScroll)
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: topPanelContent),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        4,
                        10,
                        16 + bottomSafeInset,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.68,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildItemCard(controller.results[index]),
                          childCount: controller.results.length,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    16 + bottomSafeInset,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: controller.results.length,
                  itemBuilder: (context, index) =>
                      _buildItemCard(controller.results[index]),
                ),
              ),
            if (widget.bottomBar != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: widget.bottomBar!,
                ),
              ),
          ],
        );
      },
    );
  }
}
