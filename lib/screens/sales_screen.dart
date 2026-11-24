import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../controllers/inventory_search_controller.dart';
import '../services/image_inventory_search.dart';
import '../services/inventory_search.dart';
import '../theme/app_theme.dart';
import '../widgets/cached_remote_image.dart';
import '../widgets/inventory_search_view.dart';

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

class _LastSaleSummary {
  const _LastSaleSummary({
    required this.total,
    required this.itemCount,
    required this.location,
    required this.paymentMethod,
    required this.soldAt,
    required this.itemNames,
  });

  final double total;
  final int itemCount;
  final String location;
  final String paymentMethod;
  final DateTime soldAt;
  final List<String> itemNames;
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({
    super.key,
    this.initialItems = const [],
    this.initialPhotos = const [],
    this.searchGateway = const SupabaseInventorySearchGateway(),
    this.onRecordSale,
    this.onOpenAccount,
    this.onSaleRecorded,
    this.onOpenSalesLog,
  });

  final List<Map<String, dynamic>> initialItems;
  final List<SearchImageInput> initialPhotos;
  final InventorySearchGateway searchGateway;
  final Future<void> Function(Map<String, dynamic> params)? onRecordSale;
  final VoidCallback? onOpenAccount;
  final VoidCallback? onSaleRecorded;
  final VoidCallback? onOpenSalesLog;

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
  _LastSaleSummary? _lastRecordedSale;

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

  String _formatEditableAmount(double amount) =>
      amount == amount.roundToDouble()
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
      _showMessage('Nem sikerült kiválasztani a fotókat: $error', isError: true);
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
      _showMessage('Nem sikerült elkészíteni a fotót: $error', isError: true);
    }
  }

  void _enqueuePhotoInputs(
    List<SearchImageInput> inputs, {
    required bool triggerSetState,
  }) {
    if (inputs.isEmpty) return;
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
        title: const Text('Egyedi tétel hozzáadása'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _customNameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Tétel neve'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Add meg a tétel nevét'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Ár (Ft)',
                  suffixText: 'Ft',
                ),
                validator: (value) {
                  final price = double.tryParse(
                    value?.trim().replaceAll(',', '.') ?? '',
                  );
                  return price == null || price < 0
                      ? 'Adj meg érvényes, nem negatív árat'
                      : null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Mégse'),
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
            child: const Text('Hozzáadás'),
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
    String confirmLabel = 'Elvetés',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Maradok'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brick),
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
            title: 'Kilépsz a fotópárosításból?',
            content: _selectedItems.isNotEmpty
                ? 'Az ehhez a fotóhoz kijelölt tétel még nincs hozzáadva. '
                      'A korábbi ${_selectedItems.length} párosított tétel megmarad.'
                : 'Kilépéskor elvész az ehhez a fotóhoz kijelölt tétel.',
            confirmLabel: 'Kilépés',
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
            title: 'Elveted ezt az eladást?',
            content:
                '${_selectedItems.length} kiválasztott tétel még nincs rögzítve.',
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
      _finalPriceController.text = _formatEditableAmount(_listedTotal);
    });
  }

  void _onDiscountChanged(String value) {
    if (_syncingPrices) return;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null) return;
    final discount = parsed.clamp(0.0, 100.0).toDouble();
    _syncingPrices = true;
    if (discount != parsed) {
      final text = _formatEditableAmount(discount);
      _discountController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _finalPriceController.text = _formatEditableAmount(
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
      final text = _formatEditableAmount(amount);
      _finalPriceController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    _discountController.text = _formatEditableAmount(discount);
    _syncingPrices = false;
    setState(() {});
  }

  void _removeItem(Map<String, dynamic> item) {
    final discount =
        double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0;
    setState(() => _selectedItems.remove(item));
    final boundedDiscount = discount.clamp(0.0, 100.0).toDouble();
    _syncingPrices = true;
    _finalPriceController.text = _formatEditableAmount(
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
    return '${value.year}.${twoDigits(value.month)}.${twoDigits(value.day)}. '
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

    final saleTotal =
        double.tryParse(_finalPriceController.text.replaceAll(',', '.')) ??
        _listedTotal;
    final recordedSummary = _LastSaleSummary(
      total: saleTotal,
      itemCount: _selectedItems.length,
      location: _location,
      paymentMethod: _paymentMethod,
      soldAt: _soldAt,
      itemNames: _selectedItems
          .map((item) => item['name']?.toString().trim() ?? 'Termék')
          .toList(),
    );

    try {
      if (widget.onRecordSale != null) {
        await widget.onRecordSale!(params);
      } else {
        await Supabase.instance.client.rpc('record_sale', params: params);
      }

      widget.onSaleRecorded?.call();
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        _isSaving = false;
        Navigator.pop(context, true);
      } else {
        _lastRecordedSale = recordedSummary;
        _resetSaleWorkflow();
        _showMessage('Eladás sikeresen rögzítve!');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showMessage('Nem sikerült rögzíteni az eladást: $error', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.brick : AppColors.olive,
      ),
    );
  }

  String _appBarTitle() => switch (_stage) {
    _SalesStage.checkout => 'Véglegesítés',
    _SalesStage.addOptions => 'Kosár (${_selectedItems.length})',
    _SalesStage.manualSearch => 'Keresés a készletben',
    _SalesStage.matchingPhoto => 'Fotó párosítása',
    _SalesStage.start => 'Eladás rögzítése',
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
                  tooltip: 'Vissza',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _isSaving ? null : _handleBackNavigation,
                )
              : null,
          title: Text(_appBarTitle()),
          actions: [
            if (widget.onOpenAccount != null && _stage == _SalesStage.start)
              IconButton(
                tooltip: 'Fiók',
                onPressed: widget.onOpenAccount,
                icon: const Icon(Icons.person_outline),
              ),
          ],
        ),
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
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                            color: p.accentSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.photo_camera_outlined,
                            size: 30,
                            color: p.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Új eladás rögzítése',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Válassz fotót az eladott ruhákról a gyors párosításhoz, vagy keresd ki őket közvetlenül a készletből.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _pickGalleryPhotos,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Fotók kiválasztása'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Fotózás kamerával'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.search,
                      title: 'Keresés készletben',
                      subtitle: 'Kategória vagy név alapján',
                      onTap: _startManualSearch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.add_circle_outline,
                      title: 'Egyedi tétel',
                      subtitle: 'Készleten kívüli termék',
                      onTap: _addCustomItem,
                    ),
                  ),
                ],
              ),
              if (_lastRecordedSale != null) ...[
                const SizedBox(height: 14),
                _buildLastSaleCard(_lastRecordedSale!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastSaleCard(_LastSaleSummary sale) {
    final p = context.palette;
    final previewItems = sale.itemNames.take(2).join(', ');
    final extraCount = sale.itemNames.length - 2;
    final itemsText = extraCount > 0
        ? '$previewItems +$extraCount további'
        : previewItems;

    return Card(
      color: p.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: p.oliveSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.receipt_long_outlined, color: p.olive),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Legutóbbi eladás',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: p.olive,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '· ${AppFormat.salesStoreLabel(sale.location)} · ${AppFormat.paymentMethod(sale.paymentMethod)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.inkMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    itemsText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${AppFormat.forint(sale.total)} · ${sale.itemCount} tétel · ${_formatDateTime(sale.soldAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: p.inkMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onOpenSalesLog != null)
              TextButton(
                onPressed: widget.onOpenSalesLog,
                child: const Text('Napló'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOptions() {
    final p = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: p.surfaceMuted,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedItems.length} tétel a kosárban',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppFormat.forint(_listedTotal),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: p.accent,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'Még nincs tétel a kosárban.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.inkMuted),
                      ),
                    )
                  else
                    for (final item in _selectedItems) ...[
                      _buildSaleItemTile(item),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 12),
                  Text(
                    'További tétel hozzáadása',
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: p.inkMuted),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickGalleryPhotos,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: const Text('Újabb fotó'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Kamera'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _startManualSearch,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Készletből'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addCustomItem,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Egyedi tétel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selectedItems.isEmpty ? null : _openCheckout,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.olive,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Tovább a véglegesítéshez'),
                    ),
                  ),
                ),
              ),
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
      emptyMessage: 'Nem található eladatlan termék.',
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
            label: const Text('Vissza'),
          ),
          FilledButton.icon(
            onPressed: _selectedItems.isEmpty
                ? null
                : () {
                    _manualSearchController.cancelPendingRequests();
                    setState(() => _stage = _SalesStage.addOptions);
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text('Folytatás (${_selectedItems.length})'),
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
      emptyMessage: 'Nem található eladatlan termék.',
      topBanner: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.palette.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Fotó ${_currentPhotoIndex + 1} / ${_photos.length}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: context.palette.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_selectedItems.length} párosítva',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: context.palette.inkMuted,
            ),
          ),
        ],
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
          color: Colors.black54,
          child: Center(
            child: Text(
              'Már hozzáadva',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
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
            child: const Text('Fotó kihagyása'),
          ),
          FilledButton.icon(
            onPressed: photo.controller.isLoading || photo.selectedItem == null
                ? null
                : () => _advancePhoto(commitSelection: true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.olive),
            icon: const Icon(Icons.check),
            label: Text(
              _currentPhotoIndex + 1 == _photos.length
                  ? 'Párosítás kész'
                  : 'Hozzáadás és következő',
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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Eladott tételek (${_selectedItems.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_selectedItems.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nincs kiválasztott tétel. Lépj vissza és válassz legalább egy terméket.',
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _handleBackNavigation,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Vissza a tételekhez'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final item in _selectedItems) ...[
                  _buildSaleItemTile(item),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Összegzés és kedvezmény',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      _summaryRow('Listaár összesen', subtotal),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: _onDiscountChanged,
                              decoration: const InputDecoration(
                                labelText: 'Kedvezmény',
                                suffixText: '%',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _finalPriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: _onFinalPriceChanged,
                              decoration: const InputDecoration(
                                labelText: 'Fizetendő ár',
                                suffixText: 'Ft',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _summaryRow('Kedvezmény összege', subtotal - finalTotal),
                      _summaryRow('Kedvezmény aránya', discount, suffix: '%'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Eladás részletei',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('checkout-location-$_location'),
                        initialValue: _location,
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
                          if (value != null) setState(() => _location = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('checkout-payment-$_paymentMethod'),
                        initialValue: _paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Fizetési mód',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'cash',
                            child: Text('Készpénz'),
                          ),
                          DropdownMenuItem(
                            value: 'card',
                            child: Text('Kártya'),
                          ),
                          DropdownMenuItem(
                            value: 'mixed',
                            child: Text('Készpénz + kártya'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _paymentMethod = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('Eladás időpontja'),
                        subtitle: Text(_formatDateTime(_soldAt)),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: _chooseSaleDateTime,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Megjegyzés (opcionális)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _selectedItems.isEmpty || _isSaving
                    ? null
                    : _recordSale,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isSaving ? 'Eladás rögzítése…' : 'Eladás rögzítése',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: AppColors.olive,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaleItemTile(Map<String, dynamic> item) {
    final p = context.palette;
    final imageUrl = item['image_url']?.toString();
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: imageUrl == null || imageUrl.isEmpty
                ? ColoredBox(
                    color: p.surfaceMuted,
                    child: Icon(Icons.checkroom_outlined, color: p.inkMuted),
                  )
                : CachedRemoteImage(
                    imageUrl,
                    fit: BoxFit.cover,
                    thumbnail: true,
                  ),
          ),
        ),
        title: Text(
          item['name']?.toString() ?? 'Ismeretlen termék',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${item['category'] ?? 'Egyedi'} · ${AppFormat.forint(_asDouble(item['price_est']))}',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        trailing: IconButton(
          tooltip: 'Eltávolítás',
          onPressed: () => _removeItem(item),
          icon: Icon(Icons.close, color: p.inkMuted),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double amount, {String suffix = ' Ft'}) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: p.inkMuted)),
          Text(
            '${AppFormat.amount(amount)}$suffix',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: p.accent, size: 24),
              const SizedBox(height: 10),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
