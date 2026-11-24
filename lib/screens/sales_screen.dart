import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';
import '../widgets/inventory_search_view.dart';
import 'inventory_list_screen.dart';
import 'sales_dashboard_screen.dart';

enum _SalesStage { start, matchingPhoto, manualSearch, addOptions, checkout }

class _SalePhotoSession {
  _SalePhotoSession({
    required this.id,
    required this.image,
    required this.controller,
  });

  final int id;
  final SearchImageInput image;
  final InventorySearchController controller;
  Map<String, dynamic>? selectedItem;
  bool hasStartedAnalysis = false;

  void dispose() {
    controller.dispose();
  }
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({
    super.key,
    this.initialItems = const [],
    this.initialPhotos = const [],
    this.searchGateway = const SupabaseInventorySearchGateway(),
    this.onRecordSale,
  });

  final List<Map<String, dynamic>> initialItems;
  final List<SearchImageInput> initialPhotos;
  final InventorySearchGateway searchGateway;
  final Future<void> Function(Map<String, dynamic> params)? onRecordSale;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  static const _locations = InventorySearch.storeLocations;

  final ImagePicker _picker = ImagePicker();
  final List<_SalePhotoSession> _photos = [];
  final List<Map<String, dynamic>> _selectedItems = [];
  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );
  final TextEditingController _finalPriceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customPriceController = TextEditingController();

  late final InventorySearchController _manualSearchController;

  _SalesStage _stage = _SalesStage.start;
  int _nextPhotoSessionId = 1;
  int _currentPhotoIndex = 0;
  bool _isSaving = false;
  bool _syncingPrices = false;
  String _location = _locations.first;
  String _paymentMethod = 'cash';
  ImageSearchMode _preferredPhotoSearchMode = ImageSearchMode.embedded;
  DateTime _soldAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _manualSearchController = InventorySearchController(
      onlyUnsold: true,
      allowFallbackOnManualSearch: false,
      gateway: widget.searchGateway,
    );
    _selectedItems.addAll(widget.initialItems);
    if (widget.initialItems.isNotEmpty) {
      _stage = _SalesStage.addOptions;
      final itemLocation = widget.initialItems.first['location']?.toString();
      if (_locations.contains(itemLocation)) _location = itemLocation!;
    }
    if (widget.initialPhotos.isNotEmpty) {
      _enqueuePhotoInputs(widget.initialPhotos, triggerSetState: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startCurrentPhotoAnalysis();
      });
    }
  }

  double get _listedTotal => _selectedItems.fold<double>(
    0,
    (total, item) => total + _asDouble(item['price_est']),
  );

  double _asDouble(dynamic value) => InventorySearch.parsePrice(value) ?? 0;

  String _formatAmount(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  double _roundCurrency(double amount) => (amount * 100).round() / 100;

  _SalePhotoSession? get _currentPhoto =>
      _currentPhotoIndex >= 0 && _currentPhotoIndex < _photos.length
      ? _photos[_currentPhotoIndex]
      : null;

  bool get _canSystemPopDirectly =>
      !_isSaving && _stage == _SalesStage.start && _selectedItems.isEmpty;

  bool get _showExplicitBackArrow => _stage != _SalesStage.start;

  @override
  void dispose() {
    _disposePhotoSessions();
    _manualSearchController.dispose();
    _discountController.dispose();
    _finalPriceController.dispose();
    _notesController.dispose();
    _customNameController.dispose();
    _customPriceController.dispose();
    super.dispose();
  }

  void _disposePhotoSessions() {
    for (final session in _photos) {
      session.dispose();
    }
    _photos.clear();
    _currentPhotoIndex = 0;
  }

  _SalePhotoSession _createPhotoSession(SearchImageInput image) {
    final sessionId = _nextPhotoSessionId++;
    late final _SalePhotoSession session;
    final controller = InventorySearchController(
      onlyUnsold: true,
      allowFallbackOnManualSearch: false,
      imageMaxResults: 100,
      initialSearchMode: _preferredPhotoSearchMode,
      initialImage: image,
      gateway: widget.searchGateway,
      onSelectionReset: () {
        if (session.selectedItem != null) {
          session.selectedItem = null;
        }
      },
    );
    controller.addListener(() {
      if (!mounted) return;
      // Keep the preferred mode in sync so subsequent photos start with the
      // user's last explicitly chosen provider while still having clean state.
      if (identical(session, _currentPhoto)) {
        _preferredPhotoSearchMode = controller.searchMode;
        if (session.selectedItem != null &&
            !controller.results.any(
              (item) => item['id'] == session.selectedItem!['id'],
            )) {
          session.selectedItem = null;
        }
      }
      setState(() {});
    });
    session = _SalePhotoSession(
      id: sessionId,
      image: image,
      controller: controller,
    );
    return session;
  }

  Future<void> _pickGalleryPhotos() async {
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (files.isNotEmpty) {
        _addPhotoInputs(files.map(SearchImageInput.fromXFile).toList());
      }
    } catch (error) {
      _showMessage('Could not select photos: $error', isError: true);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file != null) {
        _addPhotoInputs([SearchImageInput.fromXFile(file)]);
      }
    } catch (error) {
      _showMessage('Could not take a photo: $error', isError: true);
    }
  }

  void _enqueuePhotoInputs(
    List<SearchImageInput> inputs, {
    required bool triggerSetState,
  }) {
    if (inputs.isEmpty) return;
    // Cancel any previous batch that is no longer active before starting a new batch.
    if (_stage != _SalesStage.matchingPhoto) {
      _disposePhotoSessions();
    } else {
      _currentPhoto?.controller.cancelPendingRequests();
    }

    final startIndex = _photos.length;
    for (final input in inputs) {
      _photos.add(_createPhotoSession(input));
    }
    _currentPhotoIndex = startIndex;
    _stage = _SalesStage.matchingPhoto;

    if (triggerSetState) {
      setState(() {});
    }
  }

  void _addPhotoInputs(List<SearchImageInput> inputs) {
    if (inputs.isEmpty) return;
    _enqueuePhotoInputs(inputs, triggerSetState: true);
    _startCurrentPhotoAnalysis();
  }

  Future<void> _startCurrentPhotoAnalysis() async {
    final photo = _currentPhoto;
    if (photo == null) return;
    if (photo.hasStartedAnalysis) return;
    photo.hasStartedAnalysis = true;
    // Ensure a clean controller initialized to the current preferred mode.
    if (photo.controller.searchMode != _preferredPhotoSearchMode) {
      await photo.controller.switchSearchMode(
        _preferredPhotoSearchMode,
        runSearch: false,
      );
    }
    await photo.controller.analyzeImage();
  }

  void _startManualSearch() {
    _currentPhoto?.controller.cancelPendingRequests();
    _disposePhotoSessions();
    setState(() {
      _stage = _SalesStage.manualSearch;
    });
    _manualSearchController.resetFilters(runSearch: true);
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
      _stage = _SalesStage.addOptions;
    });
  }

  void _selectPhotoMatch(Map<String, dynamic> item) {
    final photo = _currentPhoto;
    if (photo == null) return;
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

  void _advancePhoto({required bool commitSelection}) {
    final photo = _currentPhoto;
    if (photo == null) return;

    // Stop any in-flight request for the photo we are leaving.
    photo.controller.cancelPendingRequests();

    if (commitSelection && photo.selectedItem != null) {
      final alreadyAdded = _selectedItems.any(
        (selected) => selected['id'] == photo.selectedItem!['id'],
      );
      if (!alreadyAdded) {
        _selectedItems.add(photo.selectedItem!);
        final location = photo.selectedItem!['location']?.toString();
        if (_selectedItems.length == 1 && _locations.contains(location)) {
          _location = location!;
        }
      }
    }

    if (_currentPhotoIndex + 1 < _photos.length) {
      setState(() {
        _currentPhotoIndex++;
      });
      _startCurrentPhotoAnalysis();
    } else {
      _disposePhotoSessions();
      setState(() {
        _stage = _selectedItems.isNotEmpty
            ? _SalesStage.addOptions
            : _SalesStage.start;
      });
    }
  }

  Future<bool> _confirmDiscard({
    required String title,
    required String content,
    String confirmLabel = 'Discard',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _handleBackNavigation() async {
    if (_isSaving) return;

    switch (_stage) {
      case _SalesStage.start:
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        return;

      case _SalesStage.checkout:
        setState(() {
          _stage = _selectedItems.isNotEmpty
              ? _SalesStage.addOptions
              : _SalesStage.start;
        });
        return;

      case _SalesStage.manualSearch:
        _manualSearchController.cancelPendingRequests();
        setState(() {
          _stage = _selectedItems.isNotEmpty
              ? _SalesStage.addOptions
              : _SalesStage.start;
        });
        return;

      case _SalesStage.matchingPhoto:
        final photo = _currentPhoto;
        if (photo != null && photo.selectedItem != null) {
          final leave = await _confirmDiscard(
            title: 'Leave photo matching?',
            content: _selectedItems.isNotEmpty
                ? 'The item selected for this photo has not been added yet. '
                      'Your ${_selectedItems.length} previously matched '
                      'item${_selectedItems.length == 1 ? '' : 's'} will be kept.'
                : 'Leaving will discard the item selected for this photo.',
            confirmLabel: 'Leave',
          );
          if (!leave || !mounted) return;
        }
        photo?.controller.cancelPendingRequests();
        _disposePhotoSessions();
        setState(() {
          _stage = _selectedItems.isNotEmpty
              ? _SalesStage.addOptions
              : _SalesStage.start;
        });
        return;

      case _SalesStage.addOptions:
        if (_selectedItems.isNotEmpty) {
          final discard = await _confirmDiscard(
            title: 'Discard this sale?',
            content:
                'You have ${_selectedItems.length} matched '
                'item${_selectedItems.length == 1 ? '' : 's'} that have not '
                'been recorded yet.',
          );
          if (!discard || !mounted) return;
        }
        _resetSaleWorkflow();
        if (Navigator.canPop(context)) {
          Navigator.pop(context, false);
        }
        return;
    }
  }

  void _resetSaleWorkflow() {
    _manualSearchController.cancelPendingRequests();
    _disposePhotoSessions();
    _selectedItems.clear();
    _discountController.text = '0';
    _finalPriceController.clear();
    _notesController.clear();
    _location = _locations.first;
    _paymentMethod = 'cash';
    _soldAt = DateTime.now();
    _isSaving = false;
    _stage = _SalesStage.start;
    if (mounted) setState(() {});
  }

  void _openCheckout() {
    if (_selectedItems.isEmpty) return;
    setState(() {
      _stage = _SalesStage.checkout;
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
    if (time == null || !mounted) return;

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

    final params = <String, dynamic>{
      'p_location': _location,
      'p_payment_method': _paymentMethod,
      'p_items': _buildSaleLines(),
      'p_sold_at': _soldAt.toUtc().toIso8601String(),
      'p_notes': _notesController.text.trim(),
    };

    try {
      if (widget.onRecordSale != null) {
        await widget.onRecordSale!(params);
      } else {
        await Supabase.instance.client.rpc('record_sale', params: params);
      }

      if (!mounted) return;
      if (Navigator.canPop(context)) {
        _isSaving = false;
        Navigator.pop(context, true);
      } else {
        // Root route: never pop the last route (which produces a dark screen).
        _resetSaleWorkflow();
        _showMessage('Sale recorded successfully!');
      }
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

  String _appBarTitle() => switch (_stage) {
    _SalesStage.checkout => 'Sale total',
    _SalesStage.addOptions => 'Add sale items',
    _SalesStage.manualSearch => 'Search inventory',
    _SalesStage.matchingPhoto => 'Match sold items',
    _SalesStage.start => 'Record a sale',
  };

  @override
  Widget build(BuildContext context) {
    final canRoutePop = Navigator.canPop(context);
    return PopScope(
      canPop: _canSystemPopDirectly,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _showExplicitBackArrow || canRoutePop
              ? IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _isSaving ? null : _handleBackNavigation,
                )
              : null,
          title: Text(_appBarTitle()),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Navigate',
              onSelected: (destination) {
                final page = destination == 'inventory'
                    ? const InventoryListScreen()
                    : const SalesDashboardScreen();
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => page),
                );
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'inventory', child: Text('Inventory')),
                PopupMenuItem(
                  value: 'dashboard',
                  child: Text('Sales dashboard'),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.grey[100],
        body: switch (_stage) {
          _SalesStage.start => _buildPhotoPicker(),
          _SalesStage.matchingPhoto => _buildMatcher(),
          _SalesStage.manualSearch => _buildManualSearch(),
          _SalesStage.addOptions => _buildAddOptions(),
          _SalesStage.checkout => _buildCheckout(),
        },
      ),
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take another photo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _startManualSearch,
              icon: const Icon(Icons.search),
              label: const Text('Add from inventory'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addCustomItem,
              icon: const Icon(Icons.add),
              label: const Text('Add custom item'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _selectedItems.isEmpty ? null : _openCheckout,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Done adding items'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualSearch() {
    return InventorySearchView(
      key: const ValueKey('sales-manual-search'),
      controller: _manualSearchController,
      initiallyExpanded: true,
      emptyMessage: 'No unsold inventory items found.',
      isItemSelected: (item) =>
          _selectedItems.any((selected) => selected['id'] == item['id']),
      onItemTap: _toggleManualItem,
      bottomBar: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runAlignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: _handleBackNavigation,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
          FilledButton.icon(
            onPressed: _selectedItems.isEmpty
                ? null
                : () {
                    _manualSearchController.cancelPendingRequests();
                    setState(() => _stage = _SalesStage.addOptions);
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text('Continue (${_selectedItems.length})'),
          ),
        ],
      ),
    );
  }

  Widget _buildMatcher() {
    final photo = _currentPhoto;
    if (photo == null) {
      return _buildPhotoPicker();
    }
    return InventorySearchView(
      key: ValueKey('sale-photo-${photo.id}'),
      controller: photo.controller,
      initiallyExpanded: true,
      emptyMessage: 'No unsold inventory items found.',
      topBanner: Text(
        'Photo ${_currentPhotoIndex + 1} of ${_photos.length}  ·  '
        '${_selectedItems.length} matched',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      isItemSelected: (item) => photo.selectedItem?['id'] == item['id'],
      isItemDisabled: (item) {
        final alreadySelected = _selectedItems.any(
          (selected) => selected['id'] == item['id'],
        );
        return alreadySelected && photo.selectedItem?['id'] != item['id'];
      },
      itemOverlayBuilder: (context, item) {
        final alreadySelected = _selectedItems.any(
          (selected) => selected['id'] == item['id'],
        );
        final selectedHere = photo.selectedItem?['id'] == item['id'];
        if (!alreadySelected || selectedHere) return null;
        return const ColoredBox(
          color: Colors.black45,
          child: Center(
            child: Text(
              'Already matched',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      },
      onItemTap: _selectPhotoMatch,
      bottomBar: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runAlignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton(
            onPressed: () => _advancePhoto(commitSelection: false),
            child: const Text('Skip photo'),
          ),
          FilledButton.icon(
            onPressed: photo.controller.isLoading || photo.selectedItem == null
                ? null
                : () => _advancePhoto(commitSelection: true),
            icon: const Icon(Icons.check),
            label: Text(
              _currentPhotoIndex + 1 == _photos.length
                  ? 'Finish matching'
                  : 'Add & next',
            ),
          ),
        ],
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No items matched. Go back and try again.'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _handleBackNavigation,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to add items'),
                  ),
                ],
              ),
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
            key: ValueKey('checkout-location-$_location'),
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
            key: ValueKey('checkout-payment-$_paymentMethod'),
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
