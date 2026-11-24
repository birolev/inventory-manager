import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';

/// Immutable description of an image attached to a search session.
class SearchImageInput {
  const SearchImageInput({
    required this.id,
    required this.mimeType,
    this.initialBytes,
    this.loadBytes,
  }) : assert(
         initialBytes != null || loadBytes != null,
         'Provide either initialBytes or a loadBytes callback.',
       );

  final String id;
  final String mimeType;
  final Uint8List? initialBytes;
  final Future<Uint8List> Function()? loadBytes;

  static int _nextAutoId = 1;

  static String mimeTypeForName(String name, {String? declaredMimeType}) {
    if (declaredMimeType == 'image/jpeg' ||
        declaredMimeType == 'image/png' ||
        declaredMimeType == 'image/webp') {
      return declaredMimeType!;
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  factory SearchImageInput.fromXFile(XFile file, {String? id}) {
    return SearchImageInput(
      id: id ?? 'xfile-${_nextAutoId++}-${file.name}',
      mimeType: mimeTypeForName(file.name, declaredMimeType: file.mimeType),
      loadBytes: file.readAsBytes,
    );
  }
}

/// Shared state controller for every category-based and image-based inventory
/// search interface across the application.
///
/// Guarantees:
/// - Complete state reset when switching search modes or changing images.
/// - Request sequence tokens drop stale asynchronous responses.
/// - Canonical sorting over the complete result set without triggering
///   redundant image analysis or embedding generation.
/// - Independent lifecycle per image session (each sale photo owns its own
///   controller instance).
class InventorySearchController extends ChangeNotifier {
  InventorySearchController({
    this.onlyUnsold = true,
    this.allowFallbackOnManualSearch = false,
    this.imageMaxResults = 100,
    ImageSearchMode initialSearchMode = ImageSearchMode.embedded,
    SearchImageInput? initialImage,
    InventorySearchGateway gateway = const SupabaseInventorySearchGateway(),
    this.onSelectionReset,
  }) : _gateway = gateway,
       _searchMode = _normalizeMode(initialSearchMode),
       _image = initialImage,
       _imageBytes = initialImage?.initialBytes {
    _sortOption = _defaultSortOption();
  }

  final bool onlyUnsold;
  final bool allowFallbackOnManualSearch;
  final int imageMaxResults;
  final InventorySearchGateway _gateway;
  VoidCallback? onSelectionReset;

  SearchImageInput? _image;
  Uint8List? _imageBytes;
  ImageSearchMode _searchMode;

  String _selectedCategory = 'Minden';
  String _selectedGender = 'Minden';
  String _selectedLocation = 'All locations';
  String _sizeFilter = '';
  String _colorFilter = '';
  String _patternFilter = '';
  String _nameFilter = '';
  String _brandFilter = '';
  String _conditionFilter = '';
  late InventorySortOption _sortOption;

  List<Map<String, dynamic>> _results = const [];
  Map<String, dynamic>? _aiCriteria;
  List<num>? _cachedEmbedding;
  bool _usedFallback = false;
  bool _isLoading = false;
  bool _hasSearched = false;
  bool _resultsMayBeTruncated = false;
  String? _error;

  int _requestSequence = 0;
  int _filterRevision = 0;
  bool _disposed = false;

  static ImageSearchMode _normalizeMode(ImageSearchMode mode) =>
      mode == ImageSearchMode.gemini
      ? ImageSearchMode.gemini
      : ImageSearchMode.embedded;

  SearchImageInput? get image => _image;
  Uint8List? get imageBytes => _imageBytes;
  bool get hasImage => _image != null;
  ImageSearchMode get searchMode => _searchMode;

  String get selectedCategory => _selectedCategory;
  String get selectedGender => _selectedGender;
  String get selectedLocation => _selectedLocation;
  String get sizeFilter => _sizeFilter;
  String get colorFilter => _colorFilter;
  String get patternFilter => _patternFilter;
  String get nameFilter => _nameFilter;
  String get brandFilter => _brandFilter;
  String get conditionFilter => _conditionFilter;
  InventorySortOption get sortOption => _sortOption;

  List<Map<String, dynamic>> get results => _results;
  Map<String, dynamic>? get aiCriteria => _aiCriteria;
  bool get hasCachedEmbedding => _cachedEmbedding != null;
  bool get usedFallback => _usedFallback;
  bool get isLoading => _isLoading;
  bool get hasSearched => _hasSearched;
  String? get error => _error;
  int get filterRevision => _filterRevision;

  List<InventorySortOption> get availableSortOptions {
    if (hasImage && _searchMode == ImageSearchMode.embedded) {
      return const [
        InventorySortOption.relevance,
        InventorySortOption.newest,
        InventorySortOption.oldest,
        InventorySortOption.priceAsc,
        InventorySortOption.priceDesc,
      ];
    }
    return const [
      InventorySortOption.newest,
      InventorySortOption.oldest,
      InventorySortOption.priceAsc,
      InventorySortOption.priceDesc,
    ];
  }

  bool get hasActiveFilters =>
      _selectedCategory != 'Minden' ||
      _selectedGender != 'Minden' ||
      _selectedLocation != 'All locations' ||
      _sizeFilter.trim().isNotEmpty ||
      _colorFilter.trim().isNotEmpty ||
      _patternFilter.trim().isNotEmpty ||
      _nameFilter.trim().isNotEmpty ||
      _brandFilter.trim().isNotEmpty ||
      _conditionFilter.trim().isNotEmpty;

  String get activeFiltersSummary {
    return <String>[
      _selectedCategory == 'Minden' ? 'all categories' : _selectedCategory,
      _selectedGender == 'Minden' ? 'all genders' : _selectedGender,
      if (_sizeFilter.trim().isNotEmpty) 'size ${_sizeFilter.trim()}',
      if (_selectedLocation != 'All locations') 'location $_selectedLocation',
      if (_colorFilter.trim().isNotEmpty) 'color ${_colorFilter.trim()}',
      if (_patternFilter.trim().isNotEmpty) 'pattern ${_patternFilter.trim()}',
      if (_nameFilter.trim().isNotEmpty) 'name ${_nameFilter.trim()}',
      if (_brandFilter.trim().isNotEmpty) 'brand ${_brandFilter.trim()}',
      if (_conditionFilter.trim().isNotEmpty)
        'condition ${_conditionFilter.trim()}',
    ].join(' · ');
  }

  InventorySortOption _defaultSortOption() {
    if (hasImage && _searchMode == ImageSearchMode.embedded) {
      return InventorySortOption.relevance;
    }
    return InventorySortOption.newest;
  }

  InventorySearchCriteria buildCriteria({int? maxResults}) {
    return InventorySearchCriteria(
      category: _selectedCategory,
      gender: _selectedGender,
      location: _selectedLocation,
      size: _sizeFilter,
      brand: _brandFilter,
      color: _colorFilter,
      pattern: _patternFilter,
      name: _nameFilter,
      condition: _conditionFilter,
      onlyUnsold: onlyUnsold,
      sortColumn: _sortOption.sortColumn,
      ascending: _sortOption.ascending,
      maxResults: maxResults,
    );
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void _resetSearchState({required bool resetSortToModeDefault}) {
    _selectedCategory = 'Minden';
    _selectedGender = 'Minden';
    _selectedLocation = 'All locations';
    _sizeFilter = '';
    _colorFilter = '';
    _patternFilter = '';
    _nameFilter = '';
    _brandFilter = '';
    _conditionFilter = '';
    if (resetSortToModeDefault) {
      _sortOption = _defaultSortOption();
    } else if (!availableSortOptions.contains(_sortOption)) {
      _sortOption = _defaultSortOption();
    }
    _results = const [];
    _aiCriteria = null;
    _cachedEmbedding = null;
    _usedFallback = false;
    _error = null;
    _isLoading = false;
    _hasSearched = false;
    _resultsMayBeTruncated = false;
    _filterRevision++;
    onSelectionReset?.call();
  }

  void _applyCriteriaFromResult(InventorySearchCriteria criteria) {
    _selectedCategory = InventorySearch.normalizeCategory(criteria.category);
    _selectedGender = InventorySearch.normalizeGender(criteria.gender);
    _selectedLocation = InventorySearch.normalizeLocation(criteria.location);
    _brandFilter = criteria.brand?.trim() ?? '';
    _sizeFilter = criteria.size?.trim() ?? '';
    _colorFilter = criteria.color?.trim() ?? '';
    _patternFilter = criteria.pattern?.trim() ?? '';
    _nameFilter = criteria.name?.trim() ?? '';
    _conditionFilter = criteria.condition?.trim() ?? '';
    _filterRevision++;
  }

  /// Switches between Gemini and embedded vector search with a complete
  /// search-state reset so zero parameters, filters, or in-flight responses
  /// leak from the previous search mode.
  Future<void> switchSearchMode(
    ImageSearchMode mode, {
    bool runSearch = true,
  }) async {
    final normalized = _normalizeMode(mode);
    if (normalized == _searchMode && _error == null && _hasSearched) return;

    _requestSequence++;
    _searchMode = normalized;
    _resetSearchState(resetSortToModeDefault: true);
    _safeNotify();

    if (runSearch && hasImage) {
      await analyzeImage();
    }
  }

  /// Attaches or replaces the image for this search session, performing a
  /// complete reset of all prior filters, cached embeddings, AI criteria,
  /// results, and in-flight requests.
  Future<void> setImage(
    SearchImageInput? image, {
    ImageSearchMode? mode,
    bool runSearch = true,
  }) async {
    _requestSequence++;
    _image = image;
    _imageBytes = image?.initialBytes;
    if (mode != null) {
      _searchMode = _normalizeMode(mode);
    }
    _resetSearchState(resetSortToModeDefault: true);
    _safeNotify();

    if (!runSearch) return;
    if (image != null) {
      await analyzeImage();
    } else {
      await applyFiltersAndSearch();
    }
  }

  Future<void> clearImage({bool runSearch = true}) {
    return setImage(null, runSearch: runSearch);
  }

  /// Resets all filters to their clean defaults and optionally re-runs search.
  Future<void> resetFilters({bool runSearch = true}) async {
    _requestSequence++;
    _selectedCategory = 'Minden';
    _selectedGender = 'Minden';
    _selectedLocation = 'All locations';
    _sizeFilter = '';
    _colorFilter = '';
    _patternFilter = '';
    _nameFilter = '';
    _brandFilter = '';
    _conditionFilter = '';
    _usedFallback = false;
    _error = null;
    _filterRevision++;
    onSelectionReset?.call();
    _safeNotify();

    if (runSearch) {
      await applyFiltersAndSearch();
    }
  }

  /// Invalidates any in-flight asynchronous search or analysis requests.
  void cancelPendingRequests() {
    _requestSequence++;
    if (_isLoading) {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Updates the active sort option and re-sorts the complete result set
  /// without triggering unnecessary image analysis or embedding generation.
  Future<void> setSortOption(InventorySortOption option) async {
    if (!availableSortOptions.contains(option)) return;
    if (_sortOption == option) return;

    _sortOption = option;
    if (_results.isEmpty) {
      _safeNotify();
      return;
    }

    // Embedded vector results and complete non-truncated result sets can be
    // sorted immediately in memory with zero network or AI calls.
    if ((hasImage && _searchMode == ImageSearchMode.embedded) ||
        !_resultsMayBeTruncated) {
      _results = InventorySearch.sortResults(
        _results,
        sortOption: _sortOption,
        preferredCategory: _selectedCategory,
      );
      _safeNotify();
      return;
    }

    // If a criteria search was capped at maxResults, re-run the SQL query
    // only (never re-running Gemini or embedding generation).
    await applyFiltersAndSearch();
  }

  Future<void> setCategory(String category, {bool runSearch = true}) async {
    final normalized = InventorySearch.normalizeCategory(category);
    if (_selectedCategory == normalized) return;
    _selectedCategory = normalized;
    _safeNotify();
    if (runSearch) {
      await applyFiltersAndSearch();
    }
  }

  Future<void> setGender(String gender, {bool runSearch = true}) async {
    final normalized = InventorySearch.normalizeGender(gender);
    if (_selectedGender == normalized) return;
    _selectedGender = normalized;
    _safeNotify();
    if (runSearch) {
      await applyFiltersAndSearch();
    }
  }

  Future<void> setLocation(String location, {bool runSearch = true}) async {
    final normalized = InventorySearch.normalizeLocation(location);
    if (_selectedLocation == normalized) return;
    _selectedLocation = normalized;
    _safeNotify();
    if (runSearch) {
      await applyFiltersAndSearch();
    }
  }

  void setSizeFilter(String value) {
    _sizeFilter = value;
  }

  void setColorFilter(String value) {
    _colorFilter = value;
  }

  void setPatternFilter(String value) {
    _patternFilter = value;
  }

  void setNameFilter(String value) {
    _nameFilter = value;
  }

  void setBrandFilter(String value) {
    _brandFilter = value;
  }

  void setConditionFilter(String value) {
    _conditionFilter = value;
  }

  /// Runs image analysis (Gemini or embedding generation + vector search) for
  /// the attached image under the current [_searchMode].
  Future<void> analyzeImage() async {
    final activeImage = _image;
    if (activeImage == null) {
      await applyFiltersAndSearch();
      return;
    }

    final seq = ++_requestSequence;
    final activeMode = _searchMode;
    _isLoading = true;
    _error = null;
    _usedFallback = false;
    _safeNotify();

    try {
      var bytes = _imageBytes;
      if (bytes == null) {
        final loader = activeImage.loadBytes;
        if (loader == null) {
          throw StateError('Image bytes are unavailable.');
        }
        bytes = await loader();
        if (_disposed || seq != _requestSequence) return;
        _imageBytes = bytes;
        _safeNotify();
      }

      final criteria = buildCriteria(
        maxResults: activeMode == ImageSearchMode.embedded
            ? imageMaxResults
            : null,
      );
      final result = await _gateway.searchByImage(
        imageBytes: bytes,
        mimeType: activeImage.mimeType,
        criteria: criteria,
        mode: activeMode,
        sortOption: _sortOption,
      );

      if (_disposed || seq != _requestSequence) return;

      _aiCriteria = result.aiCriteria;
      _cachedEmbedding = result.embedding;
      _applyCriteriaFromResult(result.criteria);
      _results = InventorySearch.sortResults(
        result.matches,
        sortOption: _sortOption,
        preferredCategory: _selectedCategory,
      );
      _usedFallback = result.usedFallback;
      _resultsMayBeTruncated =
          criteria.maxResults != null && _results.length >= criteria.maxResults!;
      _isLoading = false;
      _hasSearched = true;
      _error = null;
      _safeNotify();
    } catch (error) {
      if (_disposed || seq != _requestSequence) return;
      _error = error.toString();
      _results = const [];
      _isLoading = false;
      _hasSearched = true;
      _safeNotify();
    }
  }

  /// Runs a filtered inventory search using the current filters & sort option
  /// without re-running image analysis or regenerating embeddings.
  Future<void> applyFiltersAndSearch() async {
    final seq = ++_requestSequence;
    final activeMode = _searchMode;
    final embedding = _cachedEmbedding;

    _isLoading = true;
    _error = null;
    _usedFallback = false;
    _safeNotify();

    try {
      final ImageInventorySearchResult result;
      if (hasImage &&
          activeMode == ImageSearchMode.embedded &&
          embedding != null) {
        final criteria = buildCriteria(maxResults: imageMaxResults);
        result = await _gateway.searchByExistingEmbedding(
          embedding: embedding,
          criteria: criteria,
          sortOption: _sortOption,
        );
      } else {
        final effectiveSort = _sortOption == InventorySortOption.relevance
            ? InventorySortOption.newest
            : _sortOption;
        final criteria = buildCriteria(maxResults: null);
        result = await _gateway.searchByCriteria(
          criteria: criteria,
          sortOption: effectiveSort,
          allowFallback:
              (hasImage && activeMode == ImageSearchMode.gemini) ||
              allowFallbackOnManualSearch,
        );
      }

      if (_disposed || seq != _requestSequence) return;

      if (result.usedFallback) {
        _applyCriteriaFromResult(result.criteria);
      }
      _results = InventorySearch.sortResults(
        result.matches,
        sortOption: _sortOption,
        preferredCategory: _selectedCategory,
      );
      _usedFallback = result.usedFallback;
      _resultsMayBeTruncated = false;
      _isLoading = false;
      _hasSearched = true;
      _error = null;
      _safeNotify();
    } catch (error) {
      if (_disposed || seq != _requestSequence) return;
      _error = error.toString();
      _results = const [];
      _isLoading = false;
      _hasSearched = true;
      _safeNotify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestSequence++;
    super.dispose();
  }
}
