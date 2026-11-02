import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SalesDashboardScreen extends StatefulWidget {
  const SalesDashboardScreen({super.key});

  @override
  State<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends State<SalesDashboardScreen> {
  DateTime _displayedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _sales = [];
  bool _isLoading = true;
  bool _isSavingEdit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final start = DateTime(_displayedMonth.year, _displayedMonth.month);
    final end = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    try {
      final rows = await Supabase.instance.client
          .from('sales')
          .select(
            'id, sold_at, location, payment_method, notes, recorded_by_name, recorded_by_email, recorded_by, '
            'sale_items(id, item_name, brand, category, size, gender, actual_price)',
          )
          .gte('sold_at', start.toUtc().toIso8601String())
          .lt('sold_at', end.toUtc().toIso8601String())
          .order('sold_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _sales = rows.map((row) => Map<String, dynamic>.from(row)).toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + offset,
      );
      _selectedDate = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    });
    _loadMonth();
  }

  List<Map<String, dynamic>> _salesOn(DateTime date) => _sales.where((sale) {
    final soldAt = DateTime.parse(sale['sold_at'].toString()).toLocal();
    return soldAt.year == date.year &&
        soldAt.month == date.month &&
        soldAt.day == date.day;
  }).toList();

  List<dynamic> _itemsFor(Map<String, dynamic> sale) =>
      sale['sale_items'] as List<dynamic>? ?? const [];

  double _saleTotal(Map<String, dynamic> sale) => _itemsFor(
    sale,
  ).fold<double>(0, (sum, item) => sum + _asDouble(item['actual_price']));

  double _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String _money(double value) {
    final formatted = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '$formatted Ft';
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  String _formatExportAmount(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  Future<void> _exportDailySales() async {
    final sales = _salesOn(_selectedDate)
      ..sort(
        (first, second) => DateTime.parse(
          first['sold_at'].toString(),
        ).compareTo(DateTime.parse(second['sold_at'].toString())),
      );
    if (sales.isEmpty) return;

    const monthNames = [
      'Jan',
      'Feb',
      'Már',
      'Ápr',
      'Máj',
      'Jún',
      'Júl',
      'Aug',
      'Szept',
      'Okt',
      'Nov',
      'Dec',
    ];
    String describeItem(dynamic value) {
      final item = Map<String, dynamic>.from(value as Map);
      final name = item['item_name']?.toString().trim() ?? '';
      final brand = item['brand']?.toString().trim() ?? '';
      if (brand.isEmpty || name.toLowerCase().contains(brand.toLowerCase())) {
        return name.isEmpty ? 'Item' : name;
      }
      return name.isEmpty ? brand : '$brand $name';
    }

    final lines = <String>[
      '${monthNames[_selectedDate.month - 1]} ${_selectedDate.day}.',
    ];
    for (final sale in sales) {
      final itemNames = _itemsFor(sale).map(describeItem).join(', ');
      final payment = switch (sale['payment_method']) {
        'cash' => 'kp',
        'card' => 'kartya',
        'mixed' => 'cash+kartya',
        _ => sale['payment_method']?.toString() ?? '',
      };
      final notes = sale['notes']?.toString().trim() ?? '';
      lines.add(
        '$itemNames ${_formatExportAmount(_saleTotal(sale))} $payment'
        '${notes.isEmpty ? '' : ' — $notes'}',
      );
    }
    final log = lines.join('\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily sales log'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(child: SelectableText(log)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Daily log copied to clipboard'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy log'),
          ),
        ],
      ),
    );
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _daySummary(DateTime date) {
    final daySales = _salesOn(date);
    return {
      'count': daySales.length,
      'revenue': daySales.fold<double>(
        0,
        (sum, sale) => sum + _saleTotal(sale),
      ),
      'items': daySales.fold<int>(
        0,
        (sum, sale) => sum + _itemsFor(sale).length,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthSales = _sales;
    final monthRevenue = monthSales.fold<double>(
      0,
      (sum, sale) => sum + _saleTotal(sale),
    );
    final monthItems = monthSales.fold<int>(
      0,
      (sum, sale) => sum + _itemsFor(sale).length,
    );
    final selectedSales = _salesOn(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily sales'),
        backgroundColor: theme.colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh sales',
            onPressed: _isLoading || _isSavingEdit ? null : _loadMonth,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: _isLoading && _sales.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _sales.isEmpty
          ? _ErrorPanel(message: _error!, onRetry: _loadMonth)
          : RefreshIndicator(
              onRefresh: _loadMonth,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _MonthStats(
                    monthLabel: MaterialLocalizations.of(
                      context,
                    ).formatMonthYear(_displayedMonth),
                    revenue: _money(monthRevenue),
                    saleCount: monthSales.length,
                    itemCount: monthItems,
                  ),
                  const SizedBox(height: 18),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _InlineError(message: _error!),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final calendar = _CalendarPanel(
                        month: _displayedMonth,
                        selectedDate: _selectedDate,
                        dateKey: _dateKey,
                        summaryFor: _daySummary,
                        onPrevious: () => _changeMonth(-1),
                        onNext: () => _changeMonth(1),
                        onSelect: (date) =>
                            setState(() => _selectedDate = date),
                      );
                      final log = _DailySalesPanel(
                        date: _selectedDate,
                        sales: selectedSales,
                        itemsFor: _itemsFor,
                        saleTotal: _saleTotal,
                        money: _money,
                        onEdit: _editSale,
                        onDelete: _deleteSale,
                        onExport: _exportDailySales,
                      );

                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: calendar),
                            const SizedBox(width: 18),
                            Expanded(flex: 4, child: log),
                          ],
                        );
                      }
                      return Column(
                        children: [calendar, const SizedBox(height: 16), log],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _editSale(Map<String, dynamic> sale) async {
    if (_isSavingEdit) return;
    final items = _itemsFor(
      sale,
    ).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    if (items.isEmpty) return;

    final editItems = items
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final detailControllers = <dynamic, Map<String, TextEditingController>>{
      for (final item in editItems)
        item['id']: {
          'name': TextEditingController(
            text: item['item_name']?.toString() ?? '',
          ),
          'brand': TextEditingController(text: item['brand']?.toString() ?? ''),
          'category': TextEditingController(
            text: item['category']?.toString() ?? '',
          ),
          'size': TextEditingController(text: item['size']?.toString() ?? ''),
          'price': TextEditingController(
            text: _asDouble(item['actual_price']).toStringAsFixed(2),
          ),
        },
    };
    final notesController = TextEditingController(
      text: sale['notes']?.toString() ?? '',
    );
    var soldAt = DateTime.parse(sale['sold_at'].toString()).toLocal();
    var location = sale['location']?.toString() ?? 'Csengery';
    var paymentMethod = sale['payment_method']?.toString() ?? 'cash';
    String? validationError;

    Map<String, dynamic>? edit;
    try {
      edit = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit sale'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Removed items return to unsold inventory when you save.',
                      style: TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    for (final item in editItems) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['item_name']?.toString() ?? 'Item',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove item from sale',
                            onPressed: editItems.length <= 1
                                ? null
                                : () => setDialogState(() {
                                    editItems.removeWhere(
                                      (entry) => entry['id'] == item['id'],
                                    );
                                  }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                      TextField(
                        controller: detailControllers[item['id']]!['name'],
                        decoration: const InputDecoration(
                          labelText: 'Item name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller:
                                  detailControllers[item['id']]!['brand'],
                              decoration: const InputDecoration(
                                labelText: 'Brand',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller:
                                  detailControllers[item['id']]!['category'],
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller:
                                  detailControllers[item['id']]!['size'],
                              decoration: const InputDecoration(
                                labelText: 'Size',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller:
                                  detailControllers[item['id']]!['price'],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Sale price (Ft)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                    ],
                    DropdownButtonFormField<String>(
                      key: ValueKey(location),
                      initialValue: location,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder(),
                      ),
                      items: const ['Csengery', 'Astoria']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => location = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(paymentMethod),
                      initialValue: paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(
                          value: 'mixed',
                          child: Text('Mixed cash/card'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => paymentMethod = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sale date and time'),
                      subtitle: Text(_formatDateTime(soldAt)),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: dialogContext,
                          initialDate: soldAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date == null || !dialogContext.mounted) return;
                        final time = await showTimePicker(
                          context: dialogContext,
                          initialTime: TimeOfDay.fromDateTime(soldAt),
                        );
                        if (time == null) return;
                        setDialogState(() {
                          soldAt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                    ),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final parsedPrices = editItems
                      .map(
                        (item) => double.tryParse(
                          detailControllers[item['id']]!['price']!.text
                              .trim()
                              .replaceAll(',', '.'),
                        ),
                      )
                      .toList();
                  final prices = parsedPrices.whereType<double>().toList();
                  if (prices.length != editItems.length ||
                      prices.any((price) => !price.isFinite || price < 0)) {
                    setDialogState(
                      () => validationError =
                          'Enter a valid non-negative price for each item.',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'location': location,
                    'payment_method': paymentMethod,
                    'sold_at': soldAt.toUtc().toIso8601String(),
                    'notes': notesController.text.trim(),
                    'items': [
                      for (var index = 0; index < editItems.length; index++)
                        {
                          'sale_item_id': editItems[index]['id'],
                          'actual_price': prices[index],
                          'item_name':
                              detailControllers[editItems[index]['id']]!['name']!
                                  .text
                                  .trim(),
                          'brand':
                              detailControllers[editItems[index]['id']]!['brand']!
                                  .text
                                  .trim(),
                          'category':
                              detailControllers[editItems[index]['id']]!['category']!
                                  .text
                                  .trim(),
                          'size':
                              detailControllers[editItems[index]['id']]!['size']!
                                  .text
                                  .trim(),
                        },
                    ],
                  });
                },
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controllers in detailControllers.values) {
        for (final controller in controllers.values) {
          controller.dispose();
        }
      }
      notesController.dispose();
    }

    if (edit == null || !mounted) return;
    setState(() => _isSavingEdit = true);
    try {
      await Supabase.instance.client.rpc(
        'update_sale',
        params: {
          'p_sale_id': sale['id'],
          'p_sold_at': edit['sold_at'],
          'p_location': edit['location'],
          'p_payment_method': edit['payment_method'],
          'p_notes': edit['notes'],
          'p_items': edit['items'],
        },
      );
      if (!mounted) return;
      final editedDate = DateTime.parse(edit['sold_at'] as String).toLocal();
      setState(() {
        _selectedDate = editedDate;
        _displayedMonth = DateTime(editedDate.year, editedDate.month);
        _isSavingEdit = false;
      });
      await _loadMonth();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update sale: $error')));
    }
  }

  Future<void> _deleteSale(Map<String, dynamic> sale) async {
    if (_isSavingEdit) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete entire sale?'),
        content: const Text(
          'This removes the sale record and returns its items to unsold inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSavingEdit = true);
    try {
      await Supabase.instance.client.rpc(
        'delete_sale',
        params: {'p_sale_id': sale['id']},
      );
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      await _loadMonth();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingEdit = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete sale: $error')));
    }
  }
}

class _MonthStats extends StatelessWidget {
  const _MonthStats({
    required this.monthLabel,
    required this.revenue,
    required this.saleCount,
    required this.itemCount,
  });

  final String monthLabel;
  final String revenue;
  final int saleCount;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          label: '$monthLabel revenue',
          value: revenue,
          icon: Icons.payments_outlined,
          color: color.primary,
        ),
        _StatCard(
          label: 'Sales',
          value: '$saleCount',
          icon: Icons.receipt_long_outlined,
          color: color.tertiary,
        ),
        _StatCard(
          label: 'Items sold',
          value: '$itemCount',
          icon: Icons.inventory_2_outlined,
          color: color.secondary,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.month,
    required this.selectedDate,
    required this.dateKey,
    required this.summaryFor,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selectedDate;
  final String Function(DateTime) dateKey;
  final Map<String, dynamic> Function(DateTime) summaryFor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthName = MaterialLocalizations.of(context).formatMonthYear(month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = DateTime(month.year, month.month, 1).weekday - 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    monthName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            day,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final day = index - offset + 1;
                if (day < 1 || day > daysInMonth) return const SizedBox();

                final date = DateTime(month.year, month.month, day);
                final summary = summaryFor(date);
                final saleCount = summary['count'] as int;
                final selected = dateKey(date) == dateKey(selectedDate);
                final today = dateKey(date) == dateKey(DateTime.now());
                final background = selected
                    ? theme.colorScheme.primary
                    : saleCount > 0
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent;
                final foreground = selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface;

                return Material(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onSelect(date),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: today && !selected
                            ? Border.all(color: theme.colorScheme.primary)
                            : null,
                      ),
                      padding: EdgeInsets.zero,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$day',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: selected || saleCount > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (saleCount > 0) ...[
                            const SizedBox(height: 1),
                            Text(
                              '${summary['revenue'].round()} Ft',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: foreground, fontSize: 9),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DailySalesPanel extends StatelessWidget {
  const _DailySalesPanel({
    required this.date,
    required this.sales,
    required this.itemsFor,
    required this.saleTotal,
    required this.money,
    required this.onEdit,
    required this.onDelete,
    required this.onExport,
  });

  final DateTime date;
  final List<Map<String, dynamic>> sales;
  final List<dynamic> Function(Map<String, dynamic>) itemsFor;
  final double Function(Map<String, dynamic>) saleTotal;
  final String Function(double) money;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final dayRevenue = sales.fold<double>(
      0,
      (sum, sale) => sum + saleTotal(sale),
    );
    final dayItemCount = sales.fold<int>(
      0,
      (sum, sale) => sum + itemsFor(sale).length,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    localizations.formatMediumDate(date),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: sales.isEmpty ? null : onExport,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${money(dayRevenue)} · ${sales.length} sales · $dayItemCount items',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Divider(height: 24),
            if (sales.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text(
                  'No sales recorded for this day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...sales.map((sale) {
                final soldAt = DateTime.parse(
                  sale['sold_at'].toString(),
                ).toLocal();
                final recorderName = sale['recorded_by_name']?.toString();
                final recorderEmail = sale['recorded_by_email']?.toString();
                final recorder = (recorderName?.isNotEmpty ?? false)
                    ? recorderName!
                    : recorderEmail ??
                          sale['recorded_by']?.toString() ??
                          'Unknown user';
                final recorderLabel =
                    (recorderName?.isNotEmpty ?? false) &&
                        (recorderEmail?.isNotEmpty ?? false) &&
                        recorderName != recorderEmail
                    ? '$recorder ($recorderEmail)'
                    : recorder;
                final items = itemsFor(sale);

                return ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  leading: const CircleAvatar(
                    child: Icon(Icons.receipt_long_outlined),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          localizations.formatTimeOfDay(
                            TimeOfDay.fromDateTime(soldAt),
                          ),
                        ),
                      ),
                      Text(
                        money(saleTotal(sale)),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${sale['location']} · ${sale['payment_method']} · $recorderLabel',
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () => onEdit(sale),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit sale'),
                          ),
                          TextButton.icon(
                            onPressed: () => onDelete(sale),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete sale'),
                          ),
                        ],
                      ),
                    ),
                    for (final item in items)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 12),
                        title: Text(item['item_name']?.toString() ?? 'Item'),
                        subtitle: Text(
                          [
                                item['brand']?.toString(),
                                item['category']?.toString(),
                                item['size']?.toString(),
                                'Sale price: ${money(_readPrice(item['actual_price']))}',
                              ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                        ),
                      ),
                    if ((sale['notes']?.toString() ?? '').trim().isNotEmpty)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.notes),
                        title: Text(sale['notes'].toString()),
                      ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  double _readPrice(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 42),
          const SizedBox(height: 12),
          const Text(
            'Could not load sales. Confirm the sales migrations are applied and you are signed in.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(8),
    child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
  );
}
