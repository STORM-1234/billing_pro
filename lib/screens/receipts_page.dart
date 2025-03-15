// lib/screens/ledger_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For RawKeyboardListener, LogicalKeyboardKey
import 'package:uuid/uuid.dart';

import '../services/companies_repository.dart';
import '../services/receipts_repository.dart';

/// Minimal in-memory model for a single receipt
class Receipt {
  String docId;
  String receiptNumber;
  String? companyDocId;
  String? companyName;
  double amount;
  String? description;
  DateTime date;
  DateTime? createdAt;
  DateTime? updatedAt;

  // Store a snapshot of OS right after creation
  double? osAfterThisReceipt;

  Receipt({
    required this.docId,
    required this.receiptNumber,
    this.companyDocId,
    this.companyName,
    required this.amount,
    this.description,
    DateTime? date,
    this.createdAt,
    this.updatedAt,
    this.osAfterThisReceipt,
  }) : date = date ?? DateTime.now();
}

/// Custom button widget that inverts colors on hover and keyboard focus.
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
    // When hovered or focused, invert colors: background becomes white and text becomes black.
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
              // Set text color based on inversion.
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

class ReceiptsPage extends StatefulWidget {
  final ReceiptsRepository receiptsRepo;
  final CompaniesRepository companiesRepo;

  const ReceiptsPage({
    Key? key,
    required this.receiptsRepo,
    required this.companiesRepo,
  }) : super(key: key);

  @override
  State<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends State<ReceiptsPage> {
  bool _isLoading = false;

  // All loaded receipts
  List<Receipt> _allReceipts = [];
  List<Receipt> _filteredReceipts = [];
  final TextEditingController _searchController = TextEditingController();

  // For keyboard navigation in the receipts list
  int _hoveredIndex = -1;

  // "Viewing" an existing receipt (read-only)
  Receipt? _viewingReceipt;

  // "Creating" a new receipt (creation form)
  Receipt? _creatingReceipt;

  // Map of company docId to current outstanding balance.
  final Map<String, double> _companyOutMap = {};

  // For picking a company in the creation form
  List<Map<String, dynamic>> _allCompanies = [];
  List<Map<String, dynamic>> _filteredCompanies = [];
  final TextEditingController _companySearchController = TextEditingController();
  final FocusNode _companySearchFocusNode = FocusNode();
  bool _showCompanySearchResults = false;
  int _companySelectedIndex = -1;
  late ScrollController _companyScrollController;
  static const double COMPANY_ITEM_HEIGHT = 60.0;
  static const double COMPANY_CONTAINER_HEIGHT = 240.0;
  static const int kArrowThrottleMs = 50;
  DateTime _lastCompanyArrow = DateTime.fromMillisecondsSinceEpoch(0);

  // For persistent receipt counter
  int _localReceiptCounter = 0;
  bool _counterLoaded = false;
  final _uuid = const Uuid();

  // Focus and controller for amount field
  FocusNode _amountFocusNode = FocusNode();
  TextEditingController? _amountController;

  // Focus for description field
  FocusNode _descriptionFocusNode = FocusNode();

  // Focus for Save and Cancel buttons
  FocusNode _saveButtonFocusNode = FocusNode();
  FocusNode _cancelButtonFocusNode = FocusNode();

  // NEW: Focus for Change button in the date picker
  FocusNode _changeButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _companyScrollController = ScrollController();
    _initData();
  }

  @override
  void dispose() {
    _companySearchFocusNode.dispose();
    _companyScrollController.dispose();
    _amountFocusNode.dispose();
    _amountController?.dispose();
    _descriptionFocusNode.dispose();
    _saveButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    _changeButtonFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // HANDLE ROUTE ARGUMENTS (if a receipt docId is passed)
  // ---------------------------------------------------------------------------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args.containsKey("viewReceiptDocId")) {
      final viewReceiptDocId = args["viewReceiptDocId"];
      if (_allReceipts.isEmpty) {
        _loadReceipts().then((_) {
          _setViewingReceipt(viewReceiptDocId);
        });
      } else {
        _setViewingReceipt(viewReceiptDocId);
      }
    }
  }

  void _setViewingReceipt(String docId) {
    try {
      final match = _allReceipts.firstWhere((r) => r.docId == docId);
      setState(() {
        _viewingReceipt = match;
      });
    } catch (e) {
      // Optionally show an error if the receipt isn't found.
    }
  }

  // ---------------------------------------------------------------------------
  // INIT & LOAD DATA
  // ---------------------------------------------------------------------------
  Future<void> _initData() async {
    setState(() => _isLoading = true);
    await _loadPersistentCounter();
    await _loadReceipts();
    await _loadCompanies();
    setState(() => _isLoading = false);
  }

  Future<void> _loadPersistentCounter() async {
    if (_counterLoaded) return;
    final localDb = widget.receiptsRepo.localDb;
    final storedVal = await localDb.getSetting('receiptCounter');
    if (storedVal != null) {
      final parsed = int.tryParse(storedVal);
      if (parsed != null) {
        _localReceiptCounter = parsed;
      }
    }
    _counterLoaded = true;
  }

  Future<void> _savePersistentCounter() async {
    final localDb = widget.receiptsRepo.localDb;
    await localDb.setSetting('receiptCounter', _localReceiptCounter.toString());
  }

  Future<String> _getNextReceiptNumber() async {
    if (!_counterLoaded) {
      await _loadPersistentCounter();
    }
    _localReceiptCounter++;
    await _savePersistentCounter();
    final padded = _localReceiptCounter.toString().padLeft(5, '0');
    return "REC-$padded";
  }

  Future<void> _loadReceipts() async {
    try {
      final models = await widget.receiptsRepo.loadAllReceipts();
      final loaded = models.map((rm) {
        String receiptNumber = "REC-???";
        String? companyName;
        double amount = rm.amount;
        String? description;
        double? osAfterThisReceipt;
        DateTime? createdAt;
        DateTime? updatedAt;

        if ((rm.extraJson ?? '').isNotEmpty) {
          try {
            final decoded = jsonDecode(rm.extraJson!) as Map<String, dynamic>;
            receiptNumber = decoded['receiptNumber'] ?? receiptNumber;
            companyName = decoded['companyName'] as String?;
            amount = (decoded['amount'] as num?)?.toDouble() ?? amount;
            description = decoded['description'] as String?;
            osAfterThisReceipt = (decoded['osAfterThisReceipt'] as num?)?.toDouble();
            final cAt = decoded['createdAt'] as String?;
            final uAt = decoded['updatedAt'] as String?;
            if (cAt != null) createdAt = DateTime.tryParse(cAt);
            if (uAt != null) updatedAt = DateTime.tryParse(uAt);
          } catch (_) {}
        }
        final dt = DateTime.tryParse(rm.date) ?? DateTime.now();
        return Receipt(
          docId: rm.docId,
          receiptNumber: receiptNumber,
          companyDocId: rm.companyDocId,
          companyName: companyName,
          amount: amount,
          description: description,
          date: dt,
          createdAt: createdAt,
          updatedAt: updatedAt,
          osAfterThisReceipt: osAfterThisReceipt,
        );
      }).toList();

      // Sort receipts: newest first.
      loaded.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _allReceipts = loaded;
        _filteredReceipts = List.from(loaded);
      });
    } catch (e) {
      _showError("Error loading receipts: $e");
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
          'outstanding': c.outstanding,
        };
      }).toList();
      _filteredCompanies = List.from(_allCompanies);
      _companyOutMap.clear();
      for (var c in comps) {
        _companyOutMap[c.docId] = c.outstanding;
      }
    } catch (e) {
      _showError("Error loading companies: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // LANDING PAGE & SEARCH BAR (adapted from invoice page)
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final overlay = _isLoading
        ? Container(
      color: Colors.black54,
      child: const Center(child: CircularProgressIndicator()),
    )
        : null;

    if (_viewingReceipt != null) {
      return _buildViewReceiptScaffold(_viewingReceipt!);
    }
    if (_creatingReceipt != null) {
      return _buildCreateReceiptScaffold(_creatingReceipt!);
    }

    // Landing page: AppBar title as a TextField with prefix icon.
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
            hintText: 'Search receipts...',
            hintStyle: TextStyle(color: Colors.black),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.black),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildReceiptsList(),
          if (overlay != null) overlay,
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startCreateReceipt,
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildReceiptsList() {
    if (_filteredReceipts.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(child: Text("No matching receipts.", style: TextStyle(color: Colors.black)));
    }
    if (_filteredReceipts.isEmpty) {
      return const Center(child: Text("No receipts. Tap + to create one.", style: TextStyle(color: Colors.black)));
    }
    return Focus(
      autofocus: true,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _hoveredIndex = (_hoveredIndex + 1) % _filteredReceipts.length;
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(() {
              _hoveredIndex = (_hoveredIndex - 1) < 0 ? _filteredReceipts.length - 1 : _hoveredIndex - 1;
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (_hoveredIndex >= 0 && _hoveredIndex < _filteredReceipts.length) {
              _viewReceipt(_filteredReceipts[_hoveredIndex]);
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: ListView.builder(
        itemCount: _filteredReceipts.length,
        itemBuilder: (context, index) {
          final r = _filteredReceipts[index];
          final createdStr = r.createdAt != null ? _formatDateAndTime(r.createdAt!) : "--";
          final currentOs = _companyOutMap[r.companyDocId] ?? 0.0;
          final snapshotOs = r.osAfterThisReceipt ?? 0.0;
          return MouseRegion(
            onEnter: (_) => setState(() => _hoveredIndex = index),
            onExit: (_) => setState(() => _hoveredIndex = -1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: _hoveredIndex == index
                    ? [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))]
                    : [BoxShadow(color: Colors.black12, blurRadius: 2, offset: const Offset(0, 2))],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _viewReceipt(r),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.receiptNumber,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                            if ((r.companyName ?? '').isNotEmpty)
                              Text(r.companyName!, style: const TextStyle(color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text("Created: $createdStr", style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("OMR ${r.amount.toStringAsFixed(3)}",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                          const SizedBox(height: 4),
                          Text("Outstanding after creation: ${snapshotOs.toStringAsFixed(3)}",
                              style: const TextStyle(color: Colors.black54)),
                          Text("Outstanding now: ${currentOs.toStringAsFixed(3)}",
                              style: const TextStyle(color: Colors.black54)),
                        ],
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

  void _onSearchChanged(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) {
      setState(() => _filteredReceipts = List.from(_allReceipts));
      return;
    }
    final results = _allReceipts.where((r) {
      final rn = r.receiptNumber.toLowerCase();
      final cn = (r.companyName ?? '').toLowerCase();
      return rn.contains(lower) || cn.contains(lower);
    }).toList();
    setState(() => _filteredReceipts = results);
  }

  // ---------------------------------------------------------------------------
  // CREATE RECEIPT FLOW
  // ---------------------------------------------------------------------------
  void _startCreateReceipt() async {
    final number = await _getNextReceiptNumber();
    final r = Receipt(
      docId: '', // Will be assigned on save.
      receiptNumber: number,
      amount: 0.0,
    );
    // Initialize the amount controller and focus node.
    _amountController = TextEditingController(text: r.amount.toStringAsFixed(2));
    setState(() => _creatingReceipt = r);
  }

  Widget _buildCreateReceiptScaffold(Receipt r) {
    final overlay = _isLoading
        ? Container(
      color: Colors.black54,
      child: const Center(child: CircularProgressIndicator()),
    )
        : null;
    return Scaffold(
      backgroundColor: Colors.white, // white background for add receipt page.
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.black,
          onPressed: _handleCancelOrBack,
        ),
        title: const Text(
          'Add Receipt',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildCreateReceiptContent(r),
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: Container()),
                    // Wrap Save button in RawKeyboardListener to call save on Enter key press.
                    RawKeyboardListener(
                      focusNode: _saveButtonFocusNode,
                      onKey: (event) {
                        if (event is RawKeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          _saveNewReceipt(r); // Call save on Enter key press
                        }
                      },
                      child: HoverFocusButton(
                        onPressed: () => _saveNewReceipt(r),
                        child: const Text("Save", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Wrap Cancel button in RawKeyboardListener to call cancel on Enter key press.
                    RawKeyboardListener(
                      focusNode: _cancelButtonFocusNode,
                      onKey: (event) {
                        if (event is RawKeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          _handleCancelOrBack(); // Call cancel on Enter key press
                        }
                      },
                      child: OutlinedButton(
                        onPressed: _handleCancelOrBack,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                        child: const Text("Cancel"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (overlay != null) overlay,
        ],
      ),
    );
  }

  Future<void> _handleCancelOrBack() async {
    await _loadReceipts();
    _resetCreateReceiptState();
    setState(() {});
  }

  Widget _buildCreateReceiptContent(Receipt r) {
    final createdStr = r.createdAt != null ? _formatDateAndTime(r.createdAt!) : "--";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date Picker Section with a HoverFocusButton for "Change"
        _buildDatePickerSection(r),
        const SizedBox(height: 12),
        Text(
          "Receipt Number: ${r.receiptNumber}",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        const SizedBox(height: 8),
        Text("Created: $createdStr", style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        _buildCompanySearchField(r),
        const SizedBox(height: 12),
        if (r.companyDocId != null && r.companyDocId!.isNotEmpty)
          _buildOutstandingRow(r.companyDocId!),
        const SizedBox(height: 12),
        _buildAmountSection(r),
        const SizedBox(height: 12),
        _buildDescriptionField(r),
      ],
    );
  }

  Widget _buildOutstandingRow(String companyDocId) {
    final out = _companyOutMap[companyDocId] ?? 0.0;
    return Text(
      "Current Outstanding: OMR ${out.toStringAsFixed(3)}",
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE PICKER SECTION
  // ---------------------------------------------------------------------------
  Widget _buildDatePickerSection(Receipt r) {
    // Extract the onPressed action into a local function.
    final changeDateAction = () async {
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: r.date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (pickedDate != null) {
        setState(() {
          r.date = pickedDate;
          // Update createdAt to the selected date.
          r.createdAt = pickedDate;
        });
      }
    };

    return Row(
      children: [
        const Text("Select Date:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(width: 12),
        Text(
          "${r.date.day}/${r.date.month}/${r.date.year}",
          style: const TextStyle(color: Colors.black87),
        ),
        const SizedBox(width: 12),
        // Wrap the Change button with RawKeyboardListener for keyboard support.
        RawKeyboardListener(
          focusNode: _changeButtonFocusNode,
          onKey: (event) {
            if (event is RawKeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              changeDateAction();
            }
          },
          child: HoverFocusButton(
            onPressed: changeDateAction,
            child: const Text(
              "Change",
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COMPANY SEARCH (adapted from invoice page)
  // ---------------------------------------------------------------------------
  Widget _buildCompanySearchField(Receipt r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Select Company:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 8),
        RawKeyboardListener(
          focusNode: _companySearchFocusNode,
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
                if (_companySelectedIndex >= 0 && _companySelectedIndex < _filteredCompanies.length) {
                  _selectCompany(r, _filteredCompanies[_companySelectedIndex]);
                  // Unfocus the company search field first.
                  _companySearchFocusNode.unfocus();
                  // Delay the focus request for the amount field.
                  Future.delayed(Duration(milliseconds: 50), () {
                    FocusScope.of(context).requestFocus(_amountFocusNode);
                  });
                }
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                setState(() {
                  _showCompanySearchResults = false;
                });
              }
            }
          },
          child: TextField(
            controller: _companySearchController,
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
        if (_showCompanySearchResults) _buildCompanyResults(r),
        if (r.companyName != null && r.companyName!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text("Selected: ${r.companyName}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          ),
      ],
    );
  }

  Widget _buildCompanyResults(Receipt r) {
    if (_filteredCompanies.isEmpty) {
      return const Text("No matching companies.", style: TextStyle(color: Colors.black));
    }
    return Stack(
      children: [
        Container(
          height: COMPANY_CONTAINER_HEIGHT,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            controller: _companyScrollController,
            itemCount: _filteredCompanies.length,
            itemBuilder: (ctx, index) {
              final c = _filteredCompanies[index];
              final outstanding = (c['outstanding'] as num).toDouble();
              final isHighlighted = (index == _companySelectedIndex);
              return InkWell(
                onTap: () {
                  _selectCompany(r, c);
                  // After tap, unfocus and delay focus on the amount field.
                  _companySearchFocusNode.unfocus();
                  Future.delayed(Duration(milliseconds: 50), () {
                    FocusScope.of(context).requestFocus(_amountFocusNode);
                  });
                },
                child: Container(
                  height: COMPANY_ITEM_HEIGHT,
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
                        "Outstanding: OMR ${outstanding.toStringAsFixed(3)}",
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Center highlight.
        Positioned(
          left: 0,
          right: 0,
          top: (COMPANY_CONTAINER_HEIGHT - COMPANY_ITEM_HEIGHT) / 2,
          height: COMPANY_ITEM_HEIGHT,
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
    final listSize = _filteredCompanies.length * COMPANY_ITEM_HEIGHT;
    final halfContainer = COMPANY_CONTAINER_HEIGHT / 2;
    final itemCenter = index * COMPANY_ITEM_HEIGHT + (COMPANY_ITEM_HEIGHT / 2);
    double targetOffset = itemCenter - halfContainer;
    if (targetOffset < 0) targetOffset = 0;
    final double maxScroll = (listSize - COMPANY_CONTAINER_HEIGHT).clamp(0, double.infinity).toDouble();
    if (targetOffset > maxScroll) targetOffset = maxScroll;
    _companyScrollController.jumpTo(targetOffset);
  }

  void _selectCompany(Receipt r, Map<String, dynamic> c) {
    setState(() {
      r.companyDocId = c['docId'];
      r.companyName = c['name'];
      _companySearchController.text = c['name'];
      _showCompanySearchResults = false;
      _companySelectedIndex = -1;
    });
  }

  // ---------------------------------------------------------------------------
  // AMOUNT & DESCRIPTION (with amount focus and navigation)
  // ---------------------------------------------------------------------------
  Widget _buildAmountSection(Receipt r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Amount:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.black),
              onPressed: () {
                setState(() {
                  if (r.amount > 1) {
                    r.amount -= 1;
                  } else if (r.amount > 0) {
                    r.amount -= 0.1;
                    if (r.amount < 0) r.amount = 0;
                  }
                  _amountController?.text = r.amount.toStringAsFixed(2);
                });
              },
            ),
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                focusNode: _amountFocusNode,
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "0.000",
                  isDense: true,
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  setState(() {
                    r.amount = parsed ?? 0.0;
                    if (r.amount < 0) r.amount = 0;
                  });
                },
                onSubmitted: (_) {
                  // Move focus to the description field after editing amount.
                  FocusScope.of(context).requestFocus(_descriptionFocusNode);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.black),
              onPressed: () {
                setState(() {
                  r.amount += 1;
                  _amountController?.text = r.amount.toStringAsFixed(2);
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDescriptionField(Receipt r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Description:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            focusNode: _descriptionFocusNode,
            maxLines: 3,
            style: const TextStyle(color: Colors.black),
            cursorColor: Colors.black,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: "Enter any notes or details for this receipt...",
            ),
            onChanged: (val) {
              r.description = val.trim();
            },
            onSubmitted: (_) {
              // Move focus to the Save button when description is submitted.
              FocusScope.of(context).requestFocus(_saveButtonFocusNode);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _saveNewReceipt(Receipt r) async {
    if (r.companyDocId == null || r.companyDocId!.isEmpty) {
      _showError("No company selected.");
      return;
    }
    final out = _companyOutMap[r.companyDocId] ?? 0.0;
    if (r.amount <= 0.00001) {
      _showError("Receipt amount must be > 0.");
      return;
    }
    if (r.amount > out) {
      _showError("Receipt amount cannot exceed the company's outstanding balance (OMR ${out.toStringAsFixed(3)}).");
      return;
    }
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      // Only override createdAt if not already set (via date picker)
      r.createdAt ??= now;
      r.updatedAt = now;
      final newOs = out - r.amount;
      r.osAfterThisReceipt = newOs;
      final dataMap = {
        'receiptNumber': r.receiptNumber,
        'companyName': r.companyName,
        'amount': r.amount,
        'description': r.description ?? '',
        'createdAt': r.createdAt!.toIso8601String(),
        'updatedAt': r.updatedAt!.toIso8601String(),
        'osAfterThisReceipt': newOs,
      };
      final extraJson = jsonEncode(dataMap);
      final newDocId = _uuid.v4();
      await widget.companiesRepo.addBillForCompany(r.companyDocId!, -r.amount);
      final rm = ReceiptModel(
        docId: newDocId,
        companyDocId: r.companyDocId!,
        amount: r.amount,
        date: r.date.toIso8601String(),
        extraJson: extraJson,
      );
      await widget.receiptsRepo.createReceipt(rm);
      _showMessage("Receipt '${r.receiptNumber}' saved.");
      await _loadReceipts();
      _resetCreateReceiptState();
      setState(() {});
    } catch (e) {
      _showError("Error saving receipt: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // VIEW RECEIPT DETAILS (read-only)
  // ---------------------------------------------------------------------------
  void _viewReceipt(Receipt r) {
    setState(() => _viewingReceipt = r);
  }

  Widget _buildViewReceiptScaffold(Receipt r) {
    final overlay = _isLoading
        ? Container(
      color: Colors.black54,
      child: const Center(child: CircularProgressIndicator()),
    )
        : null;
    return WillPopScope(
      onWillPop: () async {
        await _handleCloseView();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            color: Colors.black,
            onPressed: _handleCloseView,
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          title: const Text(
            'Receipt Details',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildViewReceiptContent(r),
              ),
            ),
            if (overlay != null) overlay,
          ],
        ),
        // New red rounded delete button on the bottom right.
        floatingActionButton: FloatingActionButton(
          onPressed: () => _deleteReceipt(r),
          backgroundColor: Colors.red,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _handleCloseView() async {
    _viewingReceipt = null;
    await _loadReceipts();
    setState(() {});
  }

  Widget _buildViewReceiptContent(Receipt r) {
    final createdStr = r.createdAt != null ? _formatDateAndTime(r.createdAt!) : "--";
    final currentOs = _companyOutMap[r.companyDocId] ?? 0.0;
    final snapshotOs = r.osAfterThisReceipt ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Receipt header
        Row(
          children: const [
            Icon(Icons.receipt_long, color: Colors.black, size: 30),
            SizedBox(width: 8),
            Text(
              "Receipt Information",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Receipt Number: ${r.receiptNumber}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 8),
              Text("Created: $createdStr", style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Company Details
        Row(
          children: const [
            Icon(Icons.business, color: Colors.black, size: 30),
            SizedBox(width: 8),
            Text("Company Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.companyName != null && r.companyName!.isNotEmpty)
                Text("Company: ${r.companyName}",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 8),
              Text("Outstanding after this receipt: ${snapshotOs.toStringAsFixed(3)}",
                  style: const TextStyle(color: Colors.black54)),
              Text("Outstanding now: ${currentOs.toStringAsFixed(3)}",
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Payment Details
        Row(
          children: const [
            Icon(Icons.attach_money, color: Colors.black, size: 30),
            SizedBox(width: 8),
            Text("Payment Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Amount: OMR ${r.amount.toStringAsFixed(3)}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 12),
              if (r.description != null && r.description!.isNotEmpty) ...[
                const Text("Description:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 4),
                Text(r.description!, style: const TextStyle(color: Colors.black)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // RESET CREATION VARIABLES AFTER SAVE OR CANCEL
  // ---------------------------------------------------------------------------
  void _resetCreateReceiptState() {
    _creatingReceipt = null;
    _companySearchController.clear();
    _filteredCompanies = List.from(_allCompanies);
    _showCompanySearchResults = false;
    _companySelectedIndex = -1;
    _amountController?.dispose();
    _amountController = null;
  }

  // ---------------------------------------------------------------------------
  // NEW DELETE RECEIPT FUNCTION
  // ---------------------------------------------------------------------------
  Future<void> _deleteReceipt(Receipt r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Receipt'),
        content: const Text('Are you sure you want to delete this receipt?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        // 1) Delete from local DB
        await widget.receiptsRepo.deleteReceipt(r.docId);

        // 2) Increase company's outstanding by the receipt amount,
        //    because removing a payment means the outstanding goes up.
        if (r.companyDocId != null && r.companyDocId!.isNotEmpty) {
          await widget.companiesRepo.addBillForCompany(r.companyDocId!, r.amount);
        }

        _showMessage("Receipt '${r.receiptNumber}' deleted.");
        await _loadReceipts();
        _handleCloseView();
      } catch (e) {
        _showError("Error deleting receipt: $e");
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // HELPER FUNCTIONS
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

  String _formatDateAndTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final mName = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    int hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) hour = 12;
    if (hour > 12) hour -= 12;
    return "$mName $day, $year  $hour:$minute $ampm";
  }
}
