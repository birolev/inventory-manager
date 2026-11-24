import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yoaron_app/constants/categories.dart';
import 'package:yoaron_app/widgets/cached_remote_image.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';
import '../theme/app_theme.dart';

/// Canonical, reusable category- and image-based inventory search interface
/// styled in the Boutique Atelier design language.
class InventorySearchView extends StatefulWidget {
  const InventorySearchView({
    super.key,
    required this.controller,
    this.topBanner,
    this.imageActions,
    this.initiallyExpanded = true,
    this.emptyMessage = 'Nem található eladatlan termék.',
    this.isItemSelected,
    this.isItemDisabled,
    this.itemOverlayBuilder,
    this.onItemTap,
    this.bottomBar,
    this.maxFilterPanelHeight = 400,
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
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: '$label szűrés alkalmazása',
          icon: const Icon(Icons.search, size: 20),
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
                isGemini
                    ? 'Fotós keresés (Gemini AI)'
                    : 'Fotós keresés (Vizuális)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('toggle-image-section'),
              onPressed: () => setState(() => _imageExpanded = !_imageExpanded),
              icon: Icon(
                _imageExpanded ? Icons.expand_less : Icons.image_outlined,
                size: 18,
              ),
              label: Text(_imageExpanded ? 'Elrejtés' : 'Mutat'),
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
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          bytes,
                          width: 88,
                          height: 108,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const Positioned(
                        right: 4,
                        bottom: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.all(Radius.circular(6)),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(
                              Icons.zoom_in,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: 88,
                  height: 108,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.isLoading)
                      Text(
                        isGemini
                            ? 'Fotó elemzése Gemini-vel…'
                            : 'Hasonló ruhák keresése…',
                        style: const TextStyle(color: AppColors.inkMuted),
                      )
                    else if (controller.error != null)
                      Text(
                        controller.error!,
                        style: const TextStyle(color: AppColors.brick),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        isGemini
                            ? 'AI találat: ${controller.aiCriteria?['category'] ?? '-'} · '
                                  '${controller.aiCriteria?['gender'] ?? '-'} · '
                                  '${controller.aiCriteria?['color'] ?? '-'}'
                            : 'Vizuális hasonlóság alapján rendezve',
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
          const SizedBox(height: 10),
          DropdownButtonFormField<ImageSearchMode>(
            key: ValueKey(
              'search-mode-${controller.searchMode.name}-${controller.filterRevision}',
            ),
            initialValue: controller.searchMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Keresési mód',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: ImageSearchMode.embedded,
                child: Text(
                  'Vizuális keresés (Gyors)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: ImageSearchMode.gemini,
                child: Text(
                  'AI elemzés (Gemini)',
                  overflow: TextOverflow.ellipsis,
                ),
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
    final size = item['size']?.toString().trim() ?? '';
    final location = item['location']?.toString().trim() ?? '';
    final brand = item['brand']?.toString().trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? AppColors.oliveSoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.olive : AppColors.border,
          width: selected ? 2 : 1,
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
                    color: AppColors.surfaceMuted,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? const Icon(
                            Icons.checkroom_outlined,
                            color: AppColors.inkMuted,
                            size: 32,
                          )
                        : CachedRemoteImage(
                            imageUrl,
                            fit: BoxFit.cover,
                            thumbnail: true,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.inkMuted,
                                ),
                          ),
                  ),
                  if (location.isNotEmpty || size.isNotEmpty)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Wrap(
                        spacing: 4,
                        children: [
                          if (size.isNotEmpty) _CardPill(text: size),
                          if (location.isNotEmpty) _CardPill(text: location),
                        ],
                      ),
                    ),
                  if (selected)
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: AppColors.olive,
                          child: Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ?overlay,
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  Text(
                    item['name']?.toString() ?? 'Ismeretlen termék',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item['category'] ?? '-'} · ${item['gender'] ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppFormat.forint(price),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
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
        final foldHeaderOnScroll =
            hasScrollableResults && !isAnySectionExpanded;

        final crossAxisCount = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.64,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        );

        final topPanelContent = DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.topBanner != null) ...[
                  widget.topBanner!,
                  const SizedBox(height: 8),
                ],
                if (controller.hasImage) _buildImageSection(controller),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Szűrők',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (controller.hasActiveFilters)
                      TextButton(
                        onPressed: controller.isLoading
                            ? null
                            : () => controller.resetFilters(),
                        child: const Text('Törlés'),
                      ),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _filtersExpanded = !_filtersExpanded),
                      icon: Icon(
                        _filtersExpanded ? Icons.expand_less : Icons.tune,
                        size: 18,
                      ),
                      label: Text(_filtersExpanded ? 'Elrejtés' : 'Szűrés'),
                    ),
                  ],
                ),
                if (_filtersExpanded) ...[
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'cat-${controller.selectedCategory}-${controller.filterRevision}',
                    ),
                    initialValue: controller.selectedCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: isGeminiImage
                          ? 'Kategória (AI javítás)'
                          : 'Kategória',
                      prefixIcon: const Icon(Icons.category_outlined, size: 20),
                      isDense: true,
                    ),
                    items: categoryItems
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(
                              category,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                  _responsivePair(
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'gender-${controller.selectedGender}-${controller.filterRevision}',
                      ),
                      initialValue: controller.selectedGender,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: isGeminiImage ? 'Nem (AI)' : 'Nem',
                        prefixIcon: const Icon(Icons.people_outline, size: 20),
                        isDense: true,
                      ),
                      items: genderItems
                          .map(
                            (gender) => DropdownMenuItem(
                              value: gender,
                              child: Text(
                                gender,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'loc-${controller.selectedLocation}-${controller.filterRevision}',
                      ),
                      initialValue: controller.selectedLocation,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Üzlet',
                        prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                        isDense: true,
                      ),
                      items: locationItems
                          .map(
                            (location) => DropdownMenuItem(
                              value: location,
                              child: Text(
                                AppFormat.locationLabel(location),
                                overflow: TextOverflow.ellipsis,
                              ),
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
                  ),
                  const SizedBox(height: 8),
                  _responsivePair(
                    _buildFilterTextField(
                      textController: _sizeController,
                      label: 'Méret',
                      hintText: 'pl. M, 32, 42',
                      prefixIcon: Icons.straighten,
                      onChanged: controller.setSizeFilter,
                    ),
                    _buildFilterTextField(
                      textController: _colorController,
                      label: 'Szín',
                      onChanged: controller.setColorFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _responsivePair(
                    _buildFilterTextField(
                      textController: _patternController,
                      label: 'Minta',
                      onChanged: controller.setPatternFilter,
                    ),
                    DropdownButtonFormField<InventorySortOption>(
                      key: ValueKey(
                        'sort-${currentSort.name}-${controller.searchMode.name}-${controller.filterRevision}',
                      ),
                      initialValue: currentSort,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Rendezés',
                        prefixIcon: Icon(Icons.sort, size: 20),
                        isDense: true,
                      ),
                      items: sortOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(
                                option.label,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: const Text(
                      'További szűrők: név, márka, állapot',
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    ),
                    children: [
                      _buildFilterTextField(
                        textController: _nameController,
                        label: 'Név',
                        onChanged: controller.setNameFilter,
                      ),
                      const SizedBox(height: 8),
                      _buildFilterTextField(
                        textController: _brandController,
                        label: 'Márka',
                        onChanged: controller.setBrandFilter,
                      ),
                      const SizedBox(height: 8),
                      _buildFilterTextField(
                        textController: _conditionController,
                        label: 'Állapot',
                        onChanged: controller.setConditionFilter,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ],
                if (!controller.isLoading &&
                    controller.usedFallback &&
                    controller.results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'A bővített keresés sem talált egyezést (kategória, üzlet és márka alapján).',
                      style: TextStyle(fontSize: 12, color: AppColors.ochre),
                    ),
                  ),
                if (!controller.isLoading &&
                    controller.results.isNotEmpty &&
                    controller.usedFallback)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Nincs pontos egyezés — bővített találatok kategória, üzlet és márka alapján.',
                      style: TextStyle(fontSize: 12, color: AppColors.ochre),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${controller.results.length} találat · '
                    '${controller.activeFiltersSummary} · '
                    '${currentSort.shortDescription}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
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
                        const Icon(
                          Icons.error_outline,
                          size: 40,
                          color: AppColors.brick,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          controller.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.brick),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.tonalIcon(
                          onPressed: controller.hasImage
                              ? controller.analyzeImage
                              : controller.applyFiltersAndSearch,
                          icon: const Icon(Icons.refresh),
                          label: Text(
                            controller.hasImage
                                ? 'Elemzés újrapróbálása'
                                : 'Keresés újrapróbálása',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (controller.results.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.checkroom_outlined,
                          size: 44,
                          color: AppColors.borderStrong,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.emptyMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (foldHeaderOnScroll)
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: topPanelContent),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        10,
                        12,
                        16 + bottomSafeInset,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
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
                    12,
                    12,
                    12,
                    16 + bottomSafeInset,
                  ),
                  gridDelegate: gridDelegate,
                  itemCount: controller.results.length,
                  itemBuilder: (context, index) =>
                      _buildItemCard(controller.results[index]),
                ),
              ),
            if (widget.bottomBar != null)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: widget.bottomBar!,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CardPill extends StatelessWidget {
  const _CardPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
