// lib/screens/ledger_page.dart

import 'dart:async';
import 'dart:convert'; // for jsonDecode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For RawKeyboardListener, LogicalKeyboardKey
import 'package:intl/intl.dart';
import 'package:printing/printing.dart'; // For PDF print/preview
import '../models/company.dart';
// Repositories
import '../services/companies_repository.dart';
import '../services/invoices_repository.dart';
import '../services/receipts_repository.dart';
// Ledger PDF builder
import 'package:billing_pro/services/_buildLedgerPdf.dart';

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
    // Invert colors when hovered or focused.
    final bool invert = _isHovered || _isFocused;
    return Focus(
      onKey: (node, event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
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

class LedgerPage extends StatefulWidget {
  final CompaniesRepository companiesRepo;
  final InvoicesRepository invoicesRepo;
  final ReceiptsRepository receiptsRepo;

  const LedgerPage({
    Key? key,
    required this.companiesRepo,
    required this.invoicesRepo,
    required this.receiptsRepo,
  }) : super(key: key);

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  // Company search variables (adapted from ReceiptsPage)
  final TextEditingController _companySearchController = TextEditingController();
  final FocusNode _companySearchFocusNode = FocusNode();
  bool _showCompanySearchResults = false;
  List<Company> _allCompanies = [];
  List<Company> _filteredCompanies = [];
  Company? _selectedCompany;
  int _companySelectedIndex = -1;
  final ScrollController _companyScrollController = ScrollController();

  // Date range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    try {
      final comps = await widget.companiesRepo.loadLocalCompanies();
      setState(() {
        _allCompanies = comps;
        _filteredCompanies = comps;
      });
    } catch (e) {
      debugPrint("Error loading companies: $e");
    }
  }

  @override
  void dispose() {
    _companySearchController.dispose();
    _companySearchFocusNode.dispose();
    _companyScrollController.dispose();
    super.dispose();
  }

  /// Filter the company list as the user types (and reset index)
  void _onCompanySearchChanged(String query) {
    final lower = query.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCompanies = _allCompanies;
      } else {
        _filteredCompanies = _allCompanies.where((c) {
          return c.name.toLowerCase().contains(lower);
        }).toList();
      }
      _showCompanySearchResults = _filteredCompanies.isNotEmpty;
      _companySelectedIndex = -1;
    });
  }

  /// Handle keyboard navigation for company search suggestions.
  void _handleCompanySearchKey(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
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
          _selectCompany(_filteredCompanies[_companySelectedIndex]);
          _companySearchFocusNode.unfocus();
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() {
          _showCompanySearchResults = false;
        });
      }
    }
  }

  void _centerScrollToCompany(int index) {
    if (!_companyScrollController.hasClients) return;
    const double COMPANY_ITEM_HEIGHT = 60.0;
    const double COMPANY_CONTAINER_HEIGHT = 240.0;
    final listSize = _filteredCompanies.length * COMPANY_ITEM_HEIGHT;
    final halfContainer = COMPANY_CONTAINER_HEIGHT / 2;
    final itemCenter = index * COMPANY_ITEM_HEIGHT + (COMPANY_ITEM_HEIGHT / 2);
    double targetOffset = itemCenter - halfContainer;
    if (targetOffset < 0) targetOffset = 0;
    final double maxScroll =
    (listSize - COMPANY_CONTAINER_HEIGHT).clamp(0, double.infinity).toDouble();
    if (targetOffset > maxScroll) targetOffset = maxScroll;
    _companyScrollController.jumpTo(targetOffset);
  }

  void _selectCompany(Company c) {
    setState(() {
      _selectedCompany = c;
      _companySearchController.text = c.name;
      _showCompanySearchResults = false;
      _companySelectedIndex = -1;
    });
  }

  /// Called when the user clicks "Print Ledger"
  Future<void> _onPrintLedger() async {
    if (_selectedCompany == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a company first.")),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 1) Load all invoices
      final allInvoices = await widget.invoicesRepo.loadAllInvoices();
      // Filter to selected company & date range
      final companyInvoices = allInvoices.where((inv) {
        if (inv.companyDocId != _selectedCompany!.docId) return false;
        final dt = DateTime.tryParse(inv.date) ?? DateTime.now();
        // End date inclusive => dt < endDate+1
        return dt.isAfter(_startDate) && dt.isBefore(_endDate.add(const Duration(days: 1)));
      }).toList();
      // 2) Load all receipts
      final allReceipts = await widget.receiptsRepo.loadAllReceipts();
      final companyReceipts = allReceipts.where((rc) {
        if (rc.companyDocId != _selectedCompany!.docId) return false;
        final dt = DateTime.tryParse(rc.date) ?? DateTime.now();
        return dt.isAfter(_startDate) && dt.isBefore(_endDate.add(const Duration(days: 1)));
      }).toList();
      // 3) Calculate opening balance
      final openingBalance =
      await _calculateOpeningBalance(_selectedCompany!.docId, _startDate);
      // 4) Build ledger rows
      final ledgerRows = <LedgerRow>[];
      // For each invoice => if isCredit => debit=total, else cash => no effect
      for (final inv in companyInvoices) {
        final dt = DateTime.tryParse(inv.date) ?? DateTime.now();
        final total = inv.total;
        // Extract invoiceNumber from JSON
        final invoiceNumber = _extractInvoiceNumber(inv.lineItemsJson) ?? "UNKNOWN";
        final isCredit = _isCreditInvoice(inv.lineItemsJson);
        final particulars = isCredit ? "By credit Sales" : "By cash Sales";
        final type = "Sales Invoice";
        double debitVal = 0.0;
        double creditVal = 0.0;
        if (isCredit) {
          debitVal = total;
        }
        ledgerRows.add(
          LedgerRow(
            date: dt,
            particulars: particulars,
            type: type,
            referenceNo: invoiceNumber,
            amount: total,
            debit: debitVal,
            credit: creditVal,
          ),
        );
      }
      // For each receipt => "By payment" => credit=total
      for (final rc in companyReceipts) {
        final dt = DateTime.tryParse(rc.date) ?? DateTime.now();
        final total = rc.amount;
        final receiptNumber = _extractReceiptNumber(rc.extraJson) ?? "UNKNOWN";
        ledgerRows.add(
          LedgerRow(
            date: dt,
            particulars: "By payment",
            type: "Receipt",
            referenceNo: receiptNumber,
            amount: total,
            debit: 0.0,
            credit: total,
          ),
        );
      }
      // 5) Build PDF
      final pdfData = await buildLedgerPdf(
        companyName: _selectedCompany!.name,
        startDate: _startDate,
        endDate: _endDate,
        openingBalance: openingBalance,
        ledgerRows: ledgerRows,
      );
      // 6) Show Print Preview
      await Printing.layoutPdf(
        onLayout: (_) async => pdfData,
        name: "Ledger_${_selectedCompany!.name}.pdf",
      );
    } catch (e) {
      debugPrint("Error building ledger PDF: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error building ledger PDF: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Calculate opening balance prior to startDate
  Future<double> _calculateOpeningBalance(String companyDocId, DateTime startDate) async {
    double balance = 0.0;
    // 1) Invoices
    final allInvoices = await widget.invoicesRepo.loadAllInvoices();
    final priorInvoices = allInvoices.where((inv) {
      if (inv.companyDocId != companyDocId) return false;
      final dt = DateTime.tryParse(inv.date) ?? DateTime.now();
      return dt.isBefore(startDate);
    });
    for (final inv in priorInvoices) {
      final total = inv.total;
      final isCredit = _isCreditInvoice(inv.lineItemsJson);
      if (isCredit) {
        balance += total;
      }
    }
    // 2) Receipts
    final allReceipts = await widget.receiptsRepo.loadAllReceipts();
    final priorReceipts = allReceipts.where((rc) {
      if (rc.companyDocId != companyDocId) return false;
      final dt = DateTime.tryParse(rc.date) ?? DateTime.now();
      return dt.isBefore(startDate);
    });
    for (final rc in priorReceipts) {
      balance -= rc.amount;
    }
    return balance;
  }

  /// Check if invoice is credit by parsing lineItemsJson
  bool _isCreditInvoice(String? lineItemsJson) {
    if (lineItemsJson == null) return false;
    return lineItemsJson.contains('"isCredit":true');
  }

  /// Extract invoiceNumber from lineItemsJson
  String? _extractInvoiceNumber(String? lineItemsJson) {
    if (lineItemsJson == null || lineItemsJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(lineItemsJson) as Map<String, dynamic>;
      return decoded['invoiceNumber'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Extract receiptNumber from extraJson
  String? _extractReceiptNumber(String? extraJson) {
    if (extraJson == null || extraJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(extraJson) as Map<String, dynamic>;
      return decoded['receiptNumber'] as String?;
    } catch (e) {
      return null;
    }
  }

  /// Custom date picker using a builder to allow keyboard navigation.
  Future<DateTime?> _pickDate(DateTime initialDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return RawKeyboardListener(
          focusNode: FocusNode(), // A temporary focus node for the date picker.
          onKey: (event) {
            // Simply ignore keyboard events.
          },
          child: child!,
        );
      },
    );
    return picked;
  }

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(_startDate);
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(_endDate);
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat("dd-MMM-yyyy");
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ledger", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Company selection with keyboard navigation
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Select Company:", style: TextStyle(fontSize: 16)),
                    RawKeyboardListener(
                      focusNode: _companySearchFocusNode,
                      onKey: _handleCompanySearchKey,
                      child: TextField(
                        controller: _companySearchController,
                        decoration: const InputDecoration(
                          hintText: "Search company...",
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(color: Colors.black),
                        onChanged: _onCompanySearchChanged,
                        onTap: () {
                          setState(() => _showCompanySearchResults = true);
                        },
                      ),
                    ),
                    if (_showCompanySearchResults)
                      Container(
                        height: 240,
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
                            final company = _filteredCompanies[index];
                            final isHighlighted = index == _companySelectedIndex;
                            return MouseRegion(
                              onEnter: (_) {
                                setState(() => _companySelectedIndex = index);
                              },
                              child: InkWell(
                                onTap: () => _selectCompany(company),
                                child: Container(
                                  height: 60,
                                  color: isHighlighted ? Colors.black12 : Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(company.name, style: const TextStyle(color: Colors.black)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              // Date range with HoverFocusButton for keyboard and mouse support
              Row(
                children: [
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Start Date", style: TextStyle(color: Colors.black)),
                      HoverFocusButton(
                        onPressed: _pickStartDate,
                        child: Text(
                          dateFormatter.format(_startDate),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("End Date", style: TextStyle(color: Colors.black)),
                      HoverFocusButton(
                        onPressed: _pickEndDate,
                        child: Text(
                          dateFormatter.format(_endDate),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Print Ledger button
              HoverFocusButton(
                onPressed: _onPrintLedger,
                child: const Text("Print Ledger", style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
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
