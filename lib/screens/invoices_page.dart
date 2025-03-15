import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // RawKeyboardListener, LogicalKeyboardKey
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import 'package:billing_pro/services/buildInvoicePdf.dart';
import '../services/invoices_repository.dart';
import '../services/companies_repository.dart';
import '../services/prices_repository.dart';

/// Minimal line item model with 2 price variables:
///  - originalPrice: from DB (unchanged)
///  - unitPrice: user override for calculations
class InvoiceItem {
  String docId;
  String name;

  // The read-only DB price
  final double originalPrice;

  // The user-override price that we actually use for calculations
  double unitPrice;

  int quantity;
  bool vatApplied;

  InvoiceItem({
    required this.docId,
    required this.name,
    required this.originalPrice,
    required this.unitPrice,
    this.quantity = 1,
    this.vatApplied = false,
  });

  double get lineTotal =>
      vatApplied ? (unitPrice * quantity * 1.05) : (unitPrice * quantity);
}

/// Full invoice in memory
class Invoice {
  String docId;
  String invoiceNumber;
  bool isCredit;
  String? companyDocId;
  String? companyName;
  String? companyAddress;
  String? companyCr;
  String? companyVat;
  List<InvoiceItem> items;
  DateTime date;
  DateTime? createdAt;
  DateTime? updatedAt;

  Invoice({
    required this.docId,
    required this.invoiceNumber,
    required this.isCredit,
    this.companyDocId,
    this.companyName,
    this.companyAddress,
    this.companyCr,
    this.companyVat,
    required this.items,
    DateTime? date,
    this.createdAt,
    this.updatedAt,
  }) : date = date ?? DateTime.now();

  double get total {
    double sum = 0.0;
    for (final item in items) {
      sum += item.lineTotal;
    }
    return sum;
  }
}

/// Custom button widget that shows a box UI and inverts colors on hover and focus.
class HoverFocusButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  const HoverFocusButton({Key? key, required this.onPressed, required this.child})
      : super(key: key);

  @override
  _HoverFocusButtonState createState() => _HoverFocusButtonState();
}

class _HoverFocusButtonState extends State<HoverFocusButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bool invert = _isHovered || _isFocused;
    return Focus(
      onFocusChange: (hasFocus) {
        setState(() {
          _isFocused = hasFocus;
        });
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: invert ? Colors.white : Colors.black,
            border: Border.all(color: Colors.black, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextButton(
            onPressed: widget.onPressed,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              foregroundColor: invert ? Colors.black : Colors.white,
              backgroundColor: invert ? Colors.white : Colors.black,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class InvoicesPage extends StatefulWidget {
  final InvoicesRepository invoicesRepo;
  final CompaniesRepository companiesRepo;
  final PricesRepository pricesRepo;

  const InvoicesPage({
    Key? key,
    required this.invoicesRepo,
    required this.companiesRepo,
    required this.pricesRepo,
  }) : super(key: key);

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  bool _isLoading = false;

  // All invoices
  List<Invoice> _allInvoices = [];
  List<Invoice> _filteredInvoices = [];
  final TextEditingController _searchController = TextEditingController();

  // If editing an invoice
  Invoice? _editingInvoice;
  Invoice? _originalInvoice;
  bool get _isEditing => _editingInvoice != null;

  // Price DB items
  List<Map<String, dynamic>> _allPrices = [];
  List<Map<String, dynamic>> _filteredPrices = [];
  final TextEditingController _itemSearchController = TextEditingController();
  Timer? _itemDebounce;
  bool _showItemResults = false;
  int _itemSelectedIndex = -1; // arrow key highlight for items

  // Companies
  List<Map<String, dynamic>> _allCompanies = [];
  List<Map<String, dynamic>> _filteredCompanies = [];
  final TextEditingController _companySearchController = TextEditingController();
  bool _showCompanySearchResults = false;
  int _companySelectedIndex = -1; // arrow key highlight for companies

  // For hover effect on the invoice list and arrow navigation:
  int _hoveredIndex = -1;

  // Stable controllers for quantity and userPrice
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _priceControllers = {};

  // Map for quantity FocusNodes to control focus after item addition.
  final Map<String, FocusNode> _qtyFocusNodes = {};

  // We'll use UUID for docId
  final _uuid = const Uuid();

  // PERSISTENT local invoice counter
  int _localInvoiceCounter = 0;
  bool _counterLoaded = false; // track if we've loaded from DB

  // If we come from CompanyDetailsPage with docId, store it here until loaded
  String? _pendingDocId;

  // Universal VAT toggle
  bool _allVatOn = false;

  // ScrollControllers to keep arrow-selected items in view
  late ScrollController _companyScrollController;
  late ScrollController _itemScrollController;

  // We throttle arrow keys so user can't "hold" them and outrun the code
  DateTime _lastCompanyArrow = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastItemArrow = DateTime.fromMillisecondsSinceEpoch(0);
  static const int kArrowThrottleMs = 50;

  // We'll define item heights and container heights for the "center highlight"
  static const double ITEM_HEIGHT = 60.0;
  static const double CONTAINER_HEIGHT = 240.0;

  // FocusNodes so we can re-focus the TextFields after selection
  final FocusNode _companySearchFocusNode = FocusNode();
  final FocusNode _itemSearchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _companyScrollController = ScrollController();
    _itemScrollController = ScrollController();

    _initData();
  }

  @override
  void dispose() {
    _companySearchFocusNode.dispose();
    _itemSearchFocusNode.dispose();
    _companyScrollController.dispose();
    _itemScrollController.dispose();
    // Dispose quantity FocusNodes
    _qtyFocusNodes.forEach((key, node) => node.dispose());
    _qtyFocusNodes.clear();
    super.dispose();
  }

  /// If we come from CompanyDetailsPage with docId, store it in _pendingDocId.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.isNotEmpty) {
      _pendingDocId = args;
    }
  }

  /// Build item row
  Widget _buildItemRow(InvoiceItem item) {
    final qtyController = _getQtyController(item);
    final priceController = _getPriceController(item);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            // Name
            Expanded(
              flex: 2,
              child: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ),
            // Qty
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.black),
                    onPressed: () {
                      setState(() {
                        if (item.quantity > 1) {
                          item.quantity--;
                          qtyController.text = item.quantity.toString();
                        }
                      });
                    },
                  ),
                  SizedBox(
                    width: 60,
                    child: Focus(
                      onKey: (node, event) {
                        if (event is RawKeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          // Stop propagation and shift focus back to the item search field.
                          _getQtyFocusNode(item).unfocus();
                          FocusScope.of(context).requestFocus(_itemSearchFocusNode);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: qtyController,
                        focusNode: _getQtyFocusNode(item),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          _getQtyFocusNode(item).unfocus();
                          FocusScope.of(context).requestFocus(_itemSearchFocusNode);
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.black),
                    onPressed: () {
                      setState(() {
                        item.quantity++;
                        qtyController.text = item.quantity.toString();
                      });
                    },
                  ),
                ],
              ),
            ),
            // Price
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  const Text("Price:", style: TextStyle(color: Colors.black)),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // VAT
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  const Text("VAT", style: TextStyle(color: Colors.black)),
                  Switch(
                    activeColor: Colors.green,
                    activeTrackColor: Colors.greenAccent,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.black12,
                    value: item.vatApplied,
                    onChanged: (val) {
                      setState(() {
                        item.vatApplied = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            // Price total
            Expanded(
              flex: 1,
              child: Text(
                "OMR ${item.lineTotal.toStringAsFixed(3)}",
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.black),
              ),
            ),
            // Remove button with disposal of controllers and focus node
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  _editingInvoice!.items.remove(item);
                });
                if (_qtyControllers.containsKey(item.docId)) {
                  _qtyControllers[item.docId]?.dispose();
                  _qtyControllers.remove(item.docId);
                }
                if (_priceControllers.containsKey(item.docId)) {
                  _priceControllers[item.docId]?.dispose();
                  _priceControllers.remove(item.docId);
                }
                if (_qtyFocusNodes.containsKey(item.docId)) {
                  _qtyFocusNodes[item.docId]?.dispose();
                  _qtyFocusNodes.remove(item.docId);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper: get or create the FocusNode for the quantity field of an item.
  FocusNode _getQtyFocusNode(InvoiceItem item) {
    if (_qtyFocusNodes.containsKey(item.docId)) {
      return _qtyFocusNodes[item.docId]!;
    } else {
      final node = FocusNode();
      _qtyFocusNodes[item.docId] = node;
      return node;
    }
  }

  TextEditingController _getQtyController(InvoiceItem item) {
    if (_qtyControllers.containsKey(item.docId)) {
      return _qtyControllers[item.docId]!;
    }
    final controller = TextEditingController(text: item.quantity.toString());
    controller.addListener(() {
      final parsed = int.tryParse(controller.text);
      setState(() {
        item.quantity = parsed ?? 1;
      });
    });
    _qtyControllers[item.docId] = controller;
    return controller;
  }

  TextEditingController _getPriceController(InvoiceItem item) {
    if (_priceControllers.containsKey(item.docId)) {
      return _priceControllers[item.docId]!;
    }
    final controller = TextEditingController(
      text: item.unitPrice.toStringAsFixed(3),
    );
    controller.addListener(() {
      final parsed = double.tryParse(controller.text);
      setState(() {
        item.unitPrice = parsed ?? item.originalPrice;
      });
    });
    _priceControllers[item.docId] = controller;
    return controller;
  }

  /// Read the last known invoiceCounter from local DB (appSettings)
  Future<void> _loadPersistentCounter() async {
    if (_counterLoaded) return;
    final localDb = widget.invoicesRepo.localDb;
    final storedVal = await localDb.getSetting('invoiceCounter');
    if (storedVal != null) {
      final parsed = int.tryParse(storedVal);
      if (parsed != null) {
        _localInvoiceCounter = parsed;
      }
    }
    _counterLoaded = true;
  }

  /// Write the new counter to DB so it persists
  Future<void> _savePersistentCounter() async {
    final localDb = widget.invoicesRepo.localDb;
    await localDb.setSetting('invoiceCounter', _localInvoiceCounter.toString());
  }

  // ---------------------------------------------------------------------------
  // LOAD data
  // ---------------------------------------------------------------------------
  Future<void> _loadInvoices() async {
    try {
      final models = await widget.invoicesRepo.loadAllInvoices();
      final loaded = models.map((m) {
        String invoiceNumber = "INV-???";
        bool isCredit = false;
        String? companyName;
        String? companyAddress;
        String? companyCr;
        String? companyVat;
        final List<InvoiceItem> items = [];
        DateTime? createdAt;
        DateTime? updatedAt;

        if (m.lineItemsJson != null && m.lineItemsJson!.isNotEmpty) {
          try {
            final decoded = jsonDecode(m.lineItemsJson!) as Map<String, dynamic>;
            invoiceNumber = decoded['invoiceNumber'] ?? "INV-???";
            isCredit = decoded['isCredit'] ?? false;
            companyName = decoded['companyName'] as String?;
            companyAddress = decoded['companyAddress'] as String?;
            companyCr = decoded['companyCr'] as String?;
            companyVat = decoded['companyVat'] as String?;
            final createdAtStr = decoded['createdAt'] as String?;
            final updatedAtStr = decoded['updatedAt'] as String?;
            if (createdAtStr != null) {
              createdAt = DateTime.tryParse(createdAtStr);
            }
            if (updatedAtStr != null) {
              updatedAt = DateTime.tryParse(updatedAtStr);
            }
            final lineList = decoded['items'] as List<dynamic>;
            for (var itemMap in lineList) {
              final double userPrice =
              (itemMap['unitPrice'] as num).toDouble();
              items.add(
                InvoiceItem(
                  docId: itemMap['docId'],
                  name: itemMap['name'],
                  originalPrice: userPrice,
                  unitPrice: userPrice,
                  quantity: itemMap['quantity'],
                  vatApplied: itemMap['vatApplied'],
                ),
              );
            }
          } catch (e) {
            debugPrint("Error parsing lineItemsJson for docId=${m.docId}: $e");
          }
        }

        return Invoice(
          docId: m.docId,
          invoiceNumber: invoiceNumber,
          isCredit: isCredit,
          companyDocId: m.companyDocId,
          companyName: companyName,
          companyAddress: companyAddress,
          companyCr: companyCr,
          companyVat: companyVat,
          items: items,
          date: DateTime.tryParse(m.date) ?? DateTime.now(),
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
      }).toList();

      loaded.sort((a, b) {
        final aCreated = a.createdAt ?? a.date;
        final bCreated = b.createdAt ?? b.date;
        return bCreated.compareTo(aCreated);
      });

      setState(() {
        _allInvoices = loaded;
        _filteredInvoices = List.from(loaded);
      });
    } catch (e) {
      _showError("Error loading invoices: $e");
    }
  }

  Future<void> _loadPrices() async {
    try {
      final data = await widget.pricesRepo.loadLocalPrices();
      _allPrices = data;
    } catch (e) {
      _showError("Error loading prices: $e");
    }
  }

  Future<void> _loadCompanies() async {
    try {
      final comps = await widget.companiesRepo.loadLocalCompanies();
      _allCompanies = comps.map((c) {
        return {
          'docId': c.docId,
          'name': c.name,
          'address': c.address,
          'crNumber': c.crNumber ?? '',
          'vatNumber': c.vatNumber ?? '',
          'outstanding': c.outstanding,
        };
      }).toList();
      _filteredCompanies = List.from(_allCompanies);
    } catch (e) {
      _showError("Error loading companies: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Searching
  // ---------------------------------------------------------------------------
  void _onSearchChanged(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) {
      setState(() => _filteredInvoices = List.from(_allInvoices));
      return;
    }
    final results = _allInvoices.where((inv) {
      return inv.invoiceNumber.toLowerCase().contains(lower);
    }).toList();
    setState(() => _filteredInvoices = results);
  }

  // ---------------------------------------------------------------------------
  // CREATE / EDIT / DELETE
  // ---------------------------------------------------------------------------
  Future<String> _getNextInvoiceNumber() async {
    if (!_counterLoaded) {
      await _loadPersistentCounter();
    }
    _localInvoiceCounter++;
    await _savePersistentCounter();
    final padded = _localInvoiceCounter.toString().padLeft(5, '0');
    return "INV-$padded";
  }

  void _createNewInvoice() async {
    // Clear controllers and focus nodes so that a fresh state is used.
    _qtyControllers.clear();
    _priceControllers.clear();
    _qtyFocusNodes.clear();

    final docId = _uuid.v4();
    final invoiceNumber = await _getNextInvoiceNumber();

    final inv = Invoice(
      docId: docId,
      invoiceNumber: invoiceNumber,
      isCredit: false,
      items: [],
    );
    setState(() {
      _editingInvoice = inv;
      _originalInvoice = Invoice(
        docId: inv.docId,
        invoiceNumber: inv.invoiceNumber,
        isCredit: inv.isCredit,
        companyDocId: inv.companyDocId,
        companyName: inv.companyName,
        companyAddress: inv.companyAddress,
        companyCr: inv.companyCr,
        companyVat: inv.companyVat,
        items: inv.items.map((x) => x).toList(),
        date: inv.date,
        createdAt: inv.createdAt,
        updatedAt: inv.updatedAt,
      );
    });
  }

  // Updated _editInvoice: When editing, set the company search text to the selected company name.
  void _editInvoice(Invoice inv) {
    final copy = Invoice(
      docId: inv.docId,
      invoiceNumber: inv.invoiceNumber,
      isCredit: inv.isCredit,
      companyDocId: inv.companyDocId,
      companyName: inv.companyName,
      companyAddress: inv.companyAddress,
      companyCr: inv.companyCr,
      companyVat: inv.companyVat,
      items: inv.items.map((i) {
        return InvoiceItem(
          docId: i.docId,
          name: i.name,
          originalPrice: i.originalPrice,
          unitPrice: i.unitPrice,
          quantity: i.quantity,
          vatApplied: i.vatApplied,
        );
      }).toList(),
      date: inv.date,
      createdAt: inv.createdAt,
      updatedAt: inv.updatedAt,
    );
    setState(() {
      _editingInvoice = copy;
      _originalInvoice = Invoice(
        docId: inv.docId,
        invoiceNumber: inv.invoiceNumber,
        isCredit: inv.isCredit,
        companyDocId: inv.companyDocId,
        companyName: inv.companyName,
        companyAddress: inv.companyAddress,
        companyCr: inv.companyCr,
        companyVat: inv.companyVat,
        items: inv.items.map((x) => x).toList(),
        date: inv.date,
        createdAt: inv.createdAt,
        updatedAt: inv.updatedAt,
      );
      // Update the company search controller with the company name.
      _companySearchController.text = inv.companyName ?? '';
    });
  }

  /// Clears search fields, hides results, etc.
  void _clearFields() {
    _searchController.clear();
    _companySearchController.clear();
    _itemSearchController.clear();

    _showCompanySearchResults = false;
    _showItemResults = false;
    _filteredPrices.clear();
    _filteredCompanies.clear();
    _itemSelectedIndex = -1;
    _companySelectedIndex = -1;
  }

  void _cancelEditing() {
    _clearFields();
    setState(() {
      _editingInvoice = null;
      _originalInvoice = null;
    });
    _loadInvoices();
  }

  Future<void> _deleteInvoice(Invoice inv) async {
    setState(() => _isLoading = true);
    _clearFields();
    try {
      if (inv.isCredit && inv.companyDocId != null) {
        await widget.companiesRepo.addBillForCompany(inv.companyDocId!, -inv.total);
      }
      await widget.invoicesRepo.deleteInvoice(inv.docId);
      _allInvoices.remove(inv);
      _filteredInvoices.remove(inv);
      _showMessage("Invoice '${inv.invoiceNumber}' deleted.");
    } catch (e) {
      _showError("Error deleting invoice: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEditingInvoice() async {
    if (_editingInvoice == null) return;
    _clearFields();
    final inv = _editingInvoice!;
    setState(() => _isLoading = true);
    try {
      if (inv.isCredit && inv.companyDocId != null) {
        await widget.companiesRepo.addBillForCompany(inv.companyDocId!, -inv.total);
      }
      await widget.invoicesRepo.deleteInvoice(inv.docId);
      _allInvoices.removeWhere((x) => x.docId == inv.docId);
      _filteredInvoices.removeWhere((x) => x.docId == inv.docId);
      _showMessage("Invoice '${inv.invoiceNumber}' deleted.");
      _editingInvoice = null;
      _originalInvoice = null;
    } catch (e) {
      _showError("Error deleting invoice: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveEditingInvoice() async {
    if (_editingInvoice == null) return;
    _clearFields();
    final inv = _editingInvoice!;
    if (inv.companyDocId == null || inv.companyDocId!.isEmpty) {
      _showError("No company selected.");
      return;
    }
    if (inv.items.isEmpty) {
      _showError("No items added.");
      return;
    }
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      inv.createdAt ??= now;
      inv.updatedAt = now;
      final lineItemsList = inv.items.map((i) {
        return {
          'docId': i.docId,
          'name': i.name,
          'unitPrice': i.unitPrice,
          'quantity': i.quantity,
          'vatApplied': i.vatApplied,
        };
      }).toList();
      final dataMap = {
        'invoiceNumber': inv.invoiceNumber,
        'isCredit': inv.isCredit,
        'companyName': inv.companyName,
        'companyAddress': inv.companyAddress,
        'companyCr': inv.companyCr,
        'companyVat': inv.companyVat,
        'createdAt': inv.createdAt!.toIso8601String(),
        'updatedAt': inv.updatedAt!.toIso8601String(),
        'items': lineItemsList,
      };
      final lineItemsJson = jsonEncode(dataMap);
      final model = InvoiceModel(
        docId: inv.docId,
        companyDocId: inv.companyDocId!,
        total: inv.total,
        date: inv.date.toIso8601String(),
        lineItemsJson: lineItemsJson,
      );
      final old = _originalInvoice;
      if (old != null) {
        if (old.isCredit && old.companyDocId != null) {
          await widget.companiesRepo.addBillForCompany(old.companyDocId!, -old.total);
        }
        if (inv.isCredit && inv.companyDocId != null) {
          await widget.companiesRepo.addBillForCompany(inv.companyDocId!, inv.total);
        }
      } else {
        if (inv.isCredit && inv.companyDocId != null) {
          await widget.companiesRepo.addBillForCompany(inv.companyDocId!, inv.total);
        }
      }
      final existingIndex = _allInvoices.indexWhere((x) => x.docId == inv.docId);
      if (existingIndex == -1) {
        await widget.invoicesRepo.createInvoice(model);
        _allInvoices.add(inv);
      } else {
        await widget.invoicesRepo.updateInvoice(model);
        _allInvoices[existingIndex] = inv;
      }
      _showMessage("Invoice '${inv.invoiceNumber}' saved.");
      _editingInvoice = null;
      _originalInvoice = null;
      _filteredInvoices = List.from(_allInvoices);
    } catch (e) {
      _showError("Error saving invoice: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printInvoice(Invoice inv) async {
    _showMessage("Printing invoice '${inv.invoiceNumber}'...");
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      inv.createdAt ??= now;
      inv.updatedAt = now;
      final lineItemsList = inv.items.map((i) {
        return {
          'docId': i.docId,
          'name': i.name,
          'unitPrice': i.unitPrice,
          'quantity': i.quantity,
          'vatApplied': i.vatApplied,
        };
      }).toList();
      final dataMap = {
        'invoiceNumber': inv.invoiceNumber,
        'isCredit': inv.isCredit,
        'companyName': inv.companyName,
        'companyAddress': inv.companyAddress,
        'companyCr': inv.companyCr,
        'companyVat': inv.companyVat,
        'createdAt': inv.createdAt!.toIso8601String(),
        'updatedAt': inv.updatedAt!.toIso8601String(),
        'items': lineItemsList,
      };
      final lineItemsJson = jsonEncode(dataMap);
      final model = InvoiceModel(
        docId: inv.docId,
        companyDocId: inv.companyDocId ?? '',
        total: inv.total,
        date: inv.date.toIso8601String(),
        lineItemsJson: lineItemsJson,
      );
      final old = _originalInvoice;
      if (old != null) {
        if (old.isCredit && old.companyDocId != null) {
          await widget.companiesRepo.addBillForCompany(old.companyDocId!, -old.total);
        }
        if (inv.isCredit && inv.companyDocId != null) {
          await widget.companiesRepo.addBillForCompany(inv.companyDocId!, inv.total);
        }
      } else {
        if (inv.isCredit && inv.companyDocId != null) {
          await widget.companiesRepo.addBillForCompany(inv.companyDocId!, inv.total);
        }
      }
      final existingIndex = _allInvoices.indexWhere((x) => x.docId == inv.docId);
      if (existingIndex == -1) {
        await widget.invoicesRepo.createInvoice(model);
        _allInvoices.add(inv);
      } else {
        await widget.invoicesRepo.updateInvoice(model);
        _allInvoices[existingIndex] = inv;
      }
      final pdfBytes = await buildInvoicePdf(inv);
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/${inv.invoiceNumber}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
      );
      _showMessage("Invoice saved & PDF saved: $filePath");
      _editingInvoice = null;
      _originalInvoice = null;
      _filteredInvoices = List.from(_allInvoices);
      _clearFields();
    } catch (e) {
      _showError("Error printing invoice: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      // Editor
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            color: Colors.black,
            onPressed: _cancelEditing,
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          title: const Text(
            'Invoice',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: RawKeyboardListener(
            focusNode: FocusNode(),
            onKey: (RawKeyEvent event) {
              if (event is RawKeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                FocusScope.of(context).nextFocus();
              }
              if (event is RawKeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                setState(() {
                  _showItemResults = false;
                  _showCompanySearchResults = false;
                });
              }
            },
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildEditorContent(),
                        ),
                      ),
                    ),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 12),
                      child: _buildBottomBar(),
                    ),
                  ],
                ),
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Landing
      final overlay = _isLoading
          ? Container(
        color: Colors.black54,
        child: const Center(child: CircularProgressIndicator()),
      )
          : null;
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          title: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.black),
            decoration: const InputDecoration(
              hintText: 'Search invoices...',
              hintStyle: TextStyle(color: Colors.black),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Colors.black),
            ),
          ),
        ),
        body: Stack(
          children: [
            _buildInvoiceList(),
            if (overlay != null) overlay,
          ],
        ),
        floatingActionButton: _buildAddInvoiceFab(),
      );
    }
  }

  Widget _buildAddInvoiceFab() {
    return SizedBox(
      width: 56,
      height: 56,
      child: FloatingActionButton(
        onPressed: _createNewInvoice,
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEditorContent() {
    final inv = _editingInvoice!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row: Cash/Credit + universal VAT toggle
        Row(
          children: [
            const Text("Cash", style: TextStyle(color: Colors.black)),
            Switch(
              value: inv.isCredit,
              activeColor: Colors.green,
              activeTrackColor: Colors.greenAccent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.black12,
              onChanged: (val) => setState(() => inv.isCredit = val),
            ),
            const Text("Credit", style: TextStyle(color: Colors.black)),
            const SizedBox(width: 20),
            const Text("All VAT", style: TextStyle(color: Colors.black)),
            Switch(
              value: _allVatOn,
              activeColor: Colors.green,
              activeTrackColor: Colors.greenAccent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.black12,
              onChanged: (val) {
                setState(() {
                  _allVatOn = val;
                  for (final it in inv.items) {
                    it.vatApplied = val;
                  }
                });
              },
            ),
          ],
        ),
        // Company
        _buildCompanySearch(inv),
        const SizedBox(height: 8),
        Text(
          "Invoice Number: ${inv.invoiceNumber}",
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        const SizedBox(height: 8),
        if (inv.createdAt != null)
          Text(
            "Created: ${_formatDateAndTime(inv.createdAt!)}",
            style: const TextStyle(color: Colors.black54),
          ),
        if (inv.updatedAt != null)
          Text(
            "Last Edited: ${_formatDateAndTime(inv.updatedAt!)}",
            style: const TextStyle(color: Colors.black54),
          ),
        const SizedBox(height: 8),
        _buildAddItemSection(inv),
        const SizedBox(height: 8),
        ...inv.items.map(_buildItemRow).toList(),
      ],
    );
  }

  Widget _buildBottomBar() {
    final inv = _editingInvoice!;
    return Row(
      children: [
        Expanded(
          child: Text(
            "Total: OMR ${inv.total.toStringAsFixed(3)}",
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
        HoverFocusButton(
          onPressed: () {
            if (_editingInvoice != null) {
              if (_editingInvoice!.companyDocId == null || _editingInvoice!.companyDocId!.isEmpty) {
                _showError("Please select a company before printing.");
                return;
              }
              if (_editingInvoice!.items.isEmpty) {
                _showError("Please add at least one item before printing.");
                return;
              }
              _printInvoice(_editingInvoice!);
            }
          },
          child: const Icon(Icons.print, size: 20, color: Colors.cyanAccent),
        ),
        const SizedBox(width: 8),
        HoverFocusButton(
          onPressed: _saveEditingInvoice,
          child: const Text("Save", style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _cancelEditing,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
          child: const Text("Cancel"),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: _deleteEditingInvoice,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: const Text("Delete"),
        ),
      ],
    );
  }

  Widget _buildInvoiceList() {
    if (_filteredInvoices.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(
        child: Text("No matching invoices.", style: TextStyle(color: Colors.black)),
      );
    }
    if (_filteredInvoices.isEmpty) {
      return const Center(
        child: Text("No invoices. Tap + to create one.", style: TextStyle(color: Colors.black)),
      );
    }
    return Focus(
      autofocus: true,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _hoveredIndex = (_hoveredIndex + 1) % _filteredInvoices.length;
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(() {
              _hoveredIndex =
              (_hoveredIndex - 1) < 0 ? _filteredInvoices.length - 1 : _hoveredIndex - 1;
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (_hoveredIndex >= 0 && _hoveredIndex < _filteredInvoices.length) {
              _editInvoice(_filteredInvoices[_hoveredIndex]);
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: ListView.builder(
        itemCount: _filteredInvoices.length,
        itemBuilder: (context, index) {
          final inv = _filteredInvoices[index];
          final createdStr = inv.createdAt != null ? _formatDateAndTime(inv.createdAt!) : "--";
          final updatedStr = inv.updatedAt != null ? _formatDateAndTime(inv.updatedAt!) : "--";
          final payMode = inv.isCredit ? "Credit" : "Cash";
          final isSelected = index == _hoveredIndex;
          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = index),
            onExit: (_) => setState(() => _hoveredIndex = -1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
                    : [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 2,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _editInvoice(inv),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${inv.invoiceNumber} ($payMode)",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            if ((inv.companyName ?? '').isNotEmpty)
                              Text(inv.companyName!, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text("Created: $createdStr", style: const TextStyle(color: Colors.black54)),
                            Text("Edited:  $updatedStr", style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                      Text(
                        "OMR ${inv.total.toStringAsFixed(3)}",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteInvoice(inv),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompanySearch(Invoice inv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Select Company:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 8),
        RawKeyboardListener(
          focusNode: FocusNode(),
          onKey: (event) {
            if (event is RawKeyDownEvent) {
              final now = DateTime.now();
              final diff = now.difference(_lastCompanyArrow).inMilliseconds;
              if (diff < kArrowThrottleMs) return;
              _lastCompanyArrow = now;
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                setState(() {
                  if (_companySelectedIndex < _filteredCompanies.length - 1) {
                    _companySelectedIndex++;
                    _centerScrollToCompany(_companySelectedIndex);
                  }
                });
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                setState(() {
                  if (_companySelectedIndex > 0) {
                    _companySelectedIndex--;
                    _centerScrollToCompany(_companySelectedIndex);
                  }
                });
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                if (_companySelectedIndex >= 0 &&
                    _companySelectedIndex < _filteredCompanies.length) {
                  _selectCompany(inv, _filteredCompanies[_companySelectedIndex]);
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(_itemSearchFocusNode);
                    }
                  });
                }
              }
            }
          },
          child: TextField(
            controller: _companySearchController,
            focusNode: _companySearchFocusNode,
            style: const TextStyle(color: Colors.black),
            cursorColor: Colors.black,
            decoration: const InputDecoration(
              labelText: "Search company by name",
              labelStyle: TextStyle(color: Colors.black54),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black, width: 2),
              ),
            ),
            onChanged: (val) {
              setState(() {
                final lower = val.trim().toLowerCase();
                _filteredCompanies = _allCompanies.where((c) {
                  final name = (c['name'] as String).toLowerCase();
                  return name.contains(lower);
                }).toList();
                _showCompanySearchResults = true;
                _companySelectedIndex = -1;
              });
            },
          ),
        ),
        if (_showCompanySearchResults)
          _buildCompanyResults(inv),
      ],
    );
  }

  Widget _buildCompanyResults(Invoice inv) {
    if (_filteredCompanies.isEmpty) {
      return const Text("No matching companies.", style: TextStyle(color: Colors.black));
    }
    return Stack(
      children: [
        Container(
          height: CONTAINER_HEIGHT,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.only(top: 4),
          child: ListView.builder(
            controller: _companyScrollController,
            itemCount: _filteredCompanies.length,
            itemBuilder: (context, index) {
              final c = _filteredCompanies[index];
              final outstandingDouble = (c['outstanding'] as num).toDouble();
              final isHighlighted = (index == _companySelectedIndex);
              return InkWell(
                onTap: () {
                  _selectCompany(inv, c);
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(_itemSearchFocusNode);
                    }
                  });
                },
                child: Container(
                  height: ITEM_HEIGHT,
                  color: isHighlighted ? Colors.black12 : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      Text(
                        "Outstanding: OMR ${outstandingDouble.toStringAsFixed(3)}",
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: (CONTAINER_HEIGHT - ITEM_HEIGHT) / 2,
          height: ITEM_HEIGHT,
          child: IgnorePointer(
            child: Container(
              alignment: Alignment.center,
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }

  void _centerScrollToCompany(int index) {
    if (!_companyScrollController.hasClients) return;
    final listSize = _filteredCompanies.length * ITEM_HEIGHT;
    final halfContainer = CONTAINER_HEIGHT / 2;
    final itemCenter = index * ITEM_HEIGHT + (ITEM_HEIGHT / 2);
    double targetOffset = itemCenter - halfContainer;
    if (targetOffset < 0) targetOffset = 0;
    final double maxScroll =
    (listSize - CONTAINER_HEIGHT).clamp(0, double.infinity).toDouble();
    if (targetOffset > maxScroll) targetOffset = maxScroll;
    _companyScrollController.jumpTo(targetOffset);
  }

  void _selectCompany(Invoice inv, Map<String, dynamic> c) {
    setState(() {
      inv.companyDocId = c['docId'];
      inv.companyName = c['name'];
      inv.companyAddress = c['address'] as String?;
      inv.companyCr = c['crNumber'] ?? '';
      inv.companyVat = c['vatNumber'] ?? '';
      _companySearchController.text = c['name'];
      _showCompanySearchResults = false;
      _companySelectedIndex = -1;
    });
  }

  Widget _buildAddItemSection(Invoice inv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Add Item:", style: TextStyle(fontSize: 16, color: Colors.black)),
        const SizedBox(height: 8),
        RawKeyboardListener(
          focusNode: FocusNode(),
          onKey: (event) {
            if (event is RawKeyDownEvent) {
              final now = DateTime.now();
              final diff = now.difference(_lastItemArrow).inMilliseconds;
              if (diff < kArrowThrottleMs) return;
              _lastItemArrow = now;
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                setState(() {
                  if (_itemSelectedIndex < _filteredPrices.length - 1) {
                    _itemSelectedIndex++;
                    _centerScrollToItem(_itemSelectedIndex);
                  }
                });
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                setState(() {
                  if (_itemSelectedIndex > 0) {
                    _itemSelectedIndex--;
                    _centerScrollToItem(_itemSelectedIndex);
                  }
                });
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                if (_itemSelectedIndex >= 0 &&
                    _itemSelectedIndex < _filteredPrices.length) {
                  _selectItem(inv, _filteredPrices[_itemSelectedIndex]);
                  // The new item will now receive focus on its qty field.
                }
              }
            }
          },
          child: TextField(
            controller: _itemSearchController,
            focusNode: _itemSearchFocusNode,
            style: const TextStyle(color: Colors.black),
            cursorColor: Colors.black,
            decoration: const InputDecoration(
              labelText: "Search item by name",
              labelStyle: TextStyle(color: Colors.black54),
              border: OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black, width: 2),
              ),
            ),
            onChanged: _onItemSearchChanged,
          ),
        ),
        if (_showItemResults)
          _buildItemResults(inv),
      ],
    );
  }

  Widget _buildItemResults(Invoice inv) {
    if (_filteredPrices.isEmpty) {
      return const Text("No matching items.", style: TextStyle(color: Colors.black));
    }
    return Stack(
      children: [
        Container(
          height: CONTAINER_HEIGHT,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.only(top: 4),
          child: ListView.builder(
            controller: _itemScrollController,
            itemCount: _filteredPrices.length,
            itemBuilder: (context, index) {
              final p = _filteredPrices[index];
              final dbPrice = (p['price'] as num).toDouble();
              final isHighlighted = (index == _itemSelectedIndex);
              return InkWell(
                onTap: () {
                  _selectItem(inv, p);
                  Future.delayed(const Duration(milliseconds: 50), () {
                    if (mounted) {
                      FocusScope.of(context).requestFocus(_itemSearchFocusNode);
                    }
                  });
                },
                child: Container(
                  height: ITEM_HEIGHT,
                  color: isHighlighted ? Colors.black12 : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        p['itemName'],
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      Text(
                        "OMR ${dbPrice.toStringAsFixed(3)}",
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: (CONTAINER_HEIGHT - ITEM_HEIGHT) / 2,
          height: ITEM_HEIGHT,
          child: IgnorePointer(
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }

  void _centerScrollToItem(int index) {
    if (!_itemScrollController.hasClients) return;
    final listSize = _filteredPrices.length * ITEM_HEIGHT;
    final halfContainer = CONTAINER_HEIGHT / 2;
    final itemCenter = index * ITEM_HEIGHT + (ITEM_HEIGHT / 2);
    double targetOffset = itemCenter - halfContainer;
    if (targetOffset < 0) targetOffset = 0;
    final double maxScroll =
    (listSize - CONTAINER_HEIGHT).clamp(0, double.infinity).toDouble();
    if (targetOffset > maxScroll) targetOffset = maxScroll;
    _itemScrollController.jumpTo(targetOffset);
  }

  void _selectItem(Invoice inv, Map<String, dynamic> p) {
    // Dispose any existing controllers/focus nodes for this item to ensure fresh defaults.
    if (_qtyControllers.containsKey(p['docId'])) {
      _qtyControllers[p['docId']]?.dispose();
      _qtyControllers.remove(p['docId']);
    }
    if (_priceControllers.containsKey(p['docId'])) {
      _priceControllers[p['docId']]?.dispose();
      _priceControllers.remove(p['docId']);
    }
    if (_qtyFocusNodes.containsKey(p['docId'])) {
      _qtyFocusNodes[p['docId']]?.dispose();
      _qtyFocusNodes.remove(p['docId']);
    }
    final dbPrice = (p['price'] as num).toDouble();
    final existing = inv.items.firstWhere(
          (it) => it.docId == p['docId'],
      orElse: () => InvoiceItem(docId: '', name: '', originalPrice: 0, unitPrice: 0),
    );
    if (existing.docId.isNotEmpty) {
      _showError("Item '${existing.name}' is already on this invoice.");
      return;
    }
    final newItem = InvoiceItem(
      docId: p['docId'],
      name: p['itemName'],
      originalPrice: dbPrice,
      unitPrice: dbPrice,
    );
    setState(() {
      inv.items.add(newItem);
      _itemSearchController.clear();
      _showItemResults = false;
      _filteredPrices.clear();
      _itemSelectedIndex = -1;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      FocusScope.of(context).requestFocus(_getQtyFocusNode(newItem));
    });
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    // 1) Load the persistent counter from local DB
    await _loadPersistentCounter();
    // 2) Load everything else
    await _loadInvoices();
    await _loadPrices();
    await _loadCompanies();
    // 3) If we have a pending docId from arguments, open it now
    if (_pendingDocId != null) {
      final invoice = _allInvoices.firstWhere(
            (inv) => inv.docId == _pendingDocId,
        orElse: () => Invoice(
          docId: '',
          invoiceNumber: 'INV-???',
          isCredit: false,
          items: [],
        ),
      );
      if (invoice.docId.isNotEmpty) {
        _editInvoice(invoice);
      }
      _pendingDocId = null;
    }
    setState(() => _isLoading = false);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String err) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Format date/time in a friendlier style: "15/Mar/2025  01:05 PM"
  String _formatDateAndTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final monthName = months[dt.month - 1];
    final year = dt.year;
    int hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour -= 12;
    }
    return "$day/$monthName/$year  $hour:$minute $ampm";
  }

  /// Debounced item search
  void _onItemSearchChanged(String query) {
    if (_itemDebounce?.isActive ?? false) {
      _itemDebounce!.cancel();
    }
    _itemDebounce = Timer(const Duration(milliseconds: 300), () {
      final lower = query.toLowerCase();
      List<Map<String, dynamic>> matches;
      if (lower.isEmpty) {
        matches = [];
      } else {
        matches = _allPrices.where((p) {
          final name = (p['itemName'] ?? '').toString().toLowerCase();
          return name.contains(lower);
        }).toList();
        // Sort exact > prefix > partial
        matches.sort((a, b) {
          final aName = a['itemName'].toString().toLowerCase();
          final bName = b['itemName'].toString().toLowerCase();
          int rank(String name, String query) {
            if (name == query) return 0;
            if (name.startsWith(query)) return 1;
            return 2;
          }
          final aRank = rank(aName, lower);
          final bRank = rank(bName, lower);
          if (aRank != bRank) return aRank.compareTo(bRank);
          return aName.compareTo(bName);
        });
      }
      setState(() {
        _filteredPrices = matches;
        _showItemResults = true;
        _itemSelectedIndex = -1;
      });
    });
  }
}
