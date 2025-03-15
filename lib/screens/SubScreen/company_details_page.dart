import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:billing_pro/models/company.dart';
import 'package:billing_pro/services/companies_repository.dart';

// Retaining the Receipt model as defined in your receipts code.
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

class CompanyDetailsPage extends StatefulWidget {
  final CompaniesRepository repo;
  final Company company;

  const CompanyDetailsPage({
    Key? key,
    required this.repo,
    required this.company,
  }) : super(key: key);

  @override
  State<CompanyDetailsPage> createState() => _CompanyDetailsPageState();
}

class _CompanyDetailsPageState extends State<CompanyDetailsPage> {
  bool _isDeleting = false;
  int _hoveredIndex = -1;

  // For editing/updating company details
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _outstandingController = TextEditingController();

  // For showing a list of bills in the "Bills" tab
  bool _isLoadingBills = false;
  List<Map<String, dynamic>> _bills = [];

  // For showing a list of receipts in the "Receipts" tab
  bool _isLoadingReceipts = false;
  List<Map<String, dynamic>> _receipts = [];

  // (Unused now) For viewing a selected receipt overlay
  Receipt? _viewingReceipt;

  // Hardcoded admin password
  static const String _adminPassword = "praisethelord";

  @override
  void initState() {
    super.initState();
    // Initialize text fields from the passed-in company
    _nameController.text = widget.company.name;
    _phoneController.text = widget.company.phone;
    _addressController.text = widget.company.address ?? '';
    _descController.text = widget.company.description ?? '';
    _outstandingController.text =
        widget.company.outstanding.toStringAsFixed(3);

    // Load actual bills for this company
    _loadBillsForCompany();
    // Load receipts for this company
    _loadReceiptsForCompany();
  }

  /// Reload the single company data from DB (to refresh the outstanding)
  /// and also reload the bills and receipts.
  Future<void> _reloadData() async {
    // 1) Re‐fetch the single company row from DB
    final allCompanies = await widget.repo.loadLocalCompanies();
    final updated = allCompanies.firstWhere(
          (c) => c.docId == widget.company.docId,
      orElse: () => widget.company, // fallback if not found
    );

    // 2) Update the in-memory object so UI sees changes
    setState(() {
      widget.company.name = updated.name;
      widget.company.phone = updated.phone;
      widget.company.address = updated.address;
      widget.company.description = updated.description;
      widget.company.outstanding = updated.outstanding;
      // If your Company model has crNumber/vatNumber, refresh them:
      widget.company.crNumber = updated.crNumber;
      widget.company.vatNumber = updated.vatNumber;
    });

    // 3) Reload bills
    await _loadBillsForCompany();
    // Reload receipts
    await _loadReceiptsForCompany();
  }

  Future<void> _loadBillsForCompany() async {
    setState(() => _isLoadingBills = true);
    try {
      // Load all bills from local DB
      final dbBills = await widget.repo.localDb.getAllBills();

      // Filter only bills for this company
      final relevant = dbBills
          .where((b) => b['companyDocId'] == widget.company.docId)
          .toList();

      // Sort bills in descending order (newest first)
      relevant.sort((a, b) {
        final dateA = DateTime.parse(a['date']);
        final dateB = DateTime.parse(b['date']);
        return dateB.compareTo(dateA);
      });

      setState(() {
        _bills = relevant;
      });
    } catch (e) {
      _showError("Error loading bills: $e");
    } finally {
      setState(() => _isLoadingBills = false);
    }
  }

  Future<void> _loadReceiptsForCompany() async {
    setState(() => _isLoadingReceipts = true);
    try {
      final dbReceipts = await widget.repo.localDb.getAllReceipts();
      final relevant = dbReceipts
          .where((r) => r['companyDocId'] == widget.company.docId)
          .toList();

      // Sort receipts descending: newest first
      relevant.sort((a, b) {
        final dateA = DateTime.parse(a['date']);
        final dateB = DateTime.parse(b['date']);
        return dateB.compareTo(dateA);
      });

      setState(() {
        _receipts = relevant;
      });
    } catch (e) {
      _showError("Error loading receipts: $e");
    } finally {
      setState(() => _isLoadingReceipts = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _descController.dispose();
    _outstandingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Instead of showing a receipt overlay inside this page,
    // we navigate to the ReceiptsPage with the selected receipt details.
    // (If _viewingReceipt is set, we still show it, but it will remain null if we navigate.)
    if (_viewingReceipt != null) {
      return _buildViewReceiptScaffold(_viewingReceipt!);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        // No default AppBar; we build a custom header row
        body: SafeArea(
          child: Column(
            children: [
              // Custom header row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.company.name,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              // Divider
              Container(
                height: 1,
                color: Colors.black12,
                margin: const EdgeInsets.symmetric(horizontal: 8),
              ),
              // Company details + tab view
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Company info
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Phone: ${widget.company.phone}',
                            style: const TextStyle(color: Colors.black),
                          ),
                          if (widget.company.address != null &&
                              widget.company.address!.isNotEmpty)
                            Text(
                              'Address: ${widget.company.address}',
                              style: const TextStyle(color: Colors.black),
                            ),
                          if (widget.company.description != null &&
                              widget.company.description!.isNotEmpty)
                            Text(
                              'Description: ${widget.company.description}',
                              style: const TextStyle(color: Colors.black),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Outstanding: OMR ${widget.company.outstanding.toStringAsFixed(3)}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Buttons row: Update & Delete
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Row(
                        children: [
                          ElevatedButton(
                            onPressed: _onUpdateClicked,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                            ),
                            child: const Text(
                              'Update',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: _isDeleting ? null : _onDeleteClicked,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: _isDeleting
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                                : const Text(
                              'Delete',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Tab bar
                    Theme(
                      data: Theme.of(context).copyWith(
                        splashColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.black12, width: 1),
                          ),
                        ),
                        child: const TabBar(
                          labelColor: Colors.black,
                          unselectedLabelColor: Colors.black54,
                          indicatorColor: Colors.black,
                          overlayColor: MaterialStatePropertyAll(Colors.transparent),
                          tabs: [
                            Tab(text: 'Bills'),
                            Tab(text: 'Receipts'),
                          ],
                        ),
                      ),
                    ),
                    // Tab bar view
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Bills tab
                          Container(
                            color: Colors.white,
                            child: _buildBillsTab(),
                          ),
                          // Receipts tab
                          Container(
                            color: Colors.white,
                            child: _buildReceiptsTab(),
                          ),
                        ],
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

  // ---------------------------------------------------------------------------
  // Admin Password Check Flow for Update
  // ---------------------------------------------------------------------------
  Future<void> _onUpdateClicked() async {
    final passOk = await _askForAdminPassword(
      title: 'Password Required',
      message: 'Enter the admin password to Update',
    );
    if (!passOk) {
      _showError("Incorrect password. Update cancelled.");
      return;
    }
    await _showUpdateDialog();
  }

  // ---------------------------------------------------------------------------
  // Admin Password Check Flow for Delete
  // ---------------------------------------------------------------------------
  Future<void> _onDeleteClicked() async {
    setState(() => _isDeleting = true);
    try {
      final passOk = await _askForAdminPassword(
        title: 'Password Required',
        message: 'Enter the admin password to Delete',
      );
      if (!passOk) {
        _showError("Incorrect password. Delete cancelled.");
        return;
      }
      await widget.repo.deleteCompany(widget.company.docId);
      _showMessage("Company deleted.");
      Navigator.pop(context);
    } catch (e) {
      _showError("Error deleting: $e");
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  /// A helper that shows a modern dialog for the admin password.
  Future<bool> _askForAdminPassword({
    required String title,
    required String message,
  }) async {
    final passController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.black),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(message, style: const TextStyle(color: Colors.black87)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.black54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.black45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () {
                          final entered = passController.text.trim();
                          final ok = (entered == _adminPassword);
                          Navigator.pop(ctx, ok);
                        },
                        child: const Text('OK', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  /// The normal update flow (dialog to update name/phone/etc.) including CR & VAT fields.
  Future<void> _showUpdateDialog() async {
    _nameController.text = widget.company.name;
    _phoneController.text = widget.company.phone;
    _addressController.text = widget.company.address ?? '';
    _descController.text = widget.company.description ?? '';
    _outstandingController.text = widget.company.outstanding.toStringAsFixed(3);

    final crController = TextEditingController(text: widget.company.crNumber ?? '');
    final vatController = TextEditingController(text: widget.company.vatNumber ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit, color: Colors.black),
                      const SizedBox(width: 8),
                      const Text(
                        'Update Company',
                        style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(label: 'Name', controller: _nameController),
                  const SizedBox(height: 12),
                  _buildTextField(label: 'Phone', controller: _phoneController),
                  const SizedBox(height: 12),
                  _buildTextField(label: 'Address', controller: _addressController),
                  const SizedBox(height: 12),
                  _buildTextField(label: 'Description', controller: _descController),
                  const SizedBox(height: 12),
                  _buildTextField(label: 'Outstanding', controller: _outstandingController, keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _buildTextField(label: 'CR Number', controller: crController),
                  const SizedBox(height: 12),
                  _buildTextField(label: 'VAT Number', controller: vatController),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        onPressed: () {
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Update', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final newName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim();
      final newAddress = _addressController.text.trim();
      final newDesc = _descController.text.trim();
      final newOutText = _outstandingController.text.trim();
      final newOutstanding = double.tryParse(newOutText) ?? widget.company.outstanding;
      final newCr = crController.text.trim();
      final newVat = vatController.text.trim();

      try {
        await widget.repo.updateCompanyDetails(
          docId: widget.company.docId,
          name: newName,
          phone: newPhone,
          address: newAddress.isNotEmpty ? newAddress : null,
          description: newDesc.isNotEmpty ? newDesc : null,
          crNumber: newCr,
          vatNumber: newVat,
        );

        await widget.repo.updateCompanyOutstanding(widget.company.docId, newOutstanding);

        setState(() {
          widget.company.name = newName;
          widget.company.phone = newPhone;
          widget.company.address = newAddress;
          widget.company.description = newDesc;
          widget.company.outstanding = newOutstanding;
          widget.company.crNumber = newCr;
          widget.company.vatNumber = newVat;
        });

        _showMessage("Company updated.");
      } catch (e) {
        _showError("Error updating: $e");
      }
    }
  }

  /// Build the Bills tab
  Widget _buildBillsTab() {
    if (_isLoadingBills) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_bills.isEmpty) {
      return Center(
        child: Text(
          'No Bills Found for ${widget.company.name}',
          style: const TextStyle(color: Colors.black),
        ),
      );
    }
    return ListView.builder(
      itemCount: _bills.length,
      itemBuilder: (context, i) {
        final b = _bills[i];
        final docId = b['docId'] as String;
        final total = (b['total'] as num).toDouble();
        final isoDate = b['date'] ?? '--';
        final dateStr = _formatDateAndTime(DateTime.parse(isoDate));

        String invoiceNumber = docId;
        String payMode = 'Unknown';
        final lineJson = b['lineItemsJson'] as String?;
        if (lineJson != null && lineJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(lineJson) as Map<String, dynamic>;
            invoiceNumber = decoded['invoiceNumber'] ?? docId;
            final isCredit = decoded['isCredit'] ?? false;
            payMode = isCredit ? 'Credit' : 'Cash';
          } catch (_) {}
        }

        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = i),
          onExit: (_) => setState(() => _hoveredIndex = -1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: _hoveredIndex == i
                  ? [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))]
                  : [BoxShadow(color: Colors.black12, blurRadius: 2, offset: const Offset(0, 2))],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _onBillTap(docId),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice: $invoiceNumber ($payMode)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Text('Time: $dateStr', style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(dateStr, style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 4),
                        Text('OMR ${total.toStringAsFixed(3)}',
                            style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Build the Receipts tab.
  /// Now, instead of displaying a receipt overlay, tapping a receipt navigates
  /// to the ReceiptsPage with the details of the tapped receipt open.
  Widget _buildReceiptsTab() {
    if (_isLoadingReceipts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_receipts.isEmpty) {
      return Center(
        child: Text(
          'No Receipts Found for ${widget.company.name}',
          style: const TextStyle(color: Colors.black),
        ),
      );
    }
    return ListView.builder(
      itemCount: _receipts.length,
      itemBuilder: (context, i) {
        final r = _receipts[i];
        final docId = r['docId'] as String;
        final amount = (r['amount'] as num).toDouble();
        final isoDate = r['date'] ?? '--';
        final dateStr = _formatDateAndTime(DateTime.parse(isoDate));
        String receiptNumber = docId;
        final extraJson = r['extraJson'] as String?;
        if (extraJson != null && extraJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(extraJson) as Map<String, dynamic>;
            receiptNumber = decoded['receiptNumber'] ?? docId;
          } catch (_) {}
        }
        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredIndex = i),
          onExit: (_) => setState(() => _hoveredIndex = -1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: _hoveredIndex == i
                  ? [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))]
                  : [BoxShadow(color: Colors.black12, blurRadius: 2, offset: const Offset(0, 2))],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                // Instead of opening an overlay here, navigate to the ReceiptsPage
                // with an argument (e.g., viewReceiptDocId) so that page displays that receipt's details.
                await Navigator.pushNamed(
                  context,
                  '/receipts',
                  arguments: {"viewReceiptDocId": docId},
                );
                await _reloadData();
                setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Receipt: $receiptNumber',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 4),
                          Text('Time: $dateStr', style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(dateStr, style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 4),
                        Text('OMR ${amount.toStringAsFixed(3)}',
                            style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// (Unused now) Old method for viewing a receipt overlay.
  void _viewReceipt(Receipt r) {
    setState(() {
      _viewingReceipt = r;
    });
  }

  /// (Unused now) Old receipt details scaffold.
  Widget _buildViewReceiptScaffold(Receipt r) {
    final overlay = (_isLoadingBills || _isLoadingReceipts)
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
      ),
    );
  }

  /// (Unused now) Old method for building receipt details content.
  Widget _buildViewReceiptContent(Receipt r) {
    final createdStr = r.createdAt != null ? _formatDateAndTime(r.createdAt!) : "--";
    final updatedStr = r.updatedAt != null ? _formatDateAndTime(r.updatedAt!) : "--";
    final currentOs = widget.company.outstanding;
    final snapshotOs = r.osAfterThisReceipt ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              Text(
                "Receipt Number: ${r.receiptNumber}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              const SizedBox(height: 8),
              Text("Created: $createdStr", style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: const [
            Icon(Icons.business, color: Colors.black, size: 30),
            SizedBox(width: 8),
            Text(
              "Company Details",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
            ),
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
                Text(
                  "Company: ${r.companyName}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              const SizedBox(height: 8),
              Text(
                "Outstanding after this receipt: ${snapshotOs.toStringAsFixed(3)}",
                style: const TextStyle(color: Colors.black54),
              ),
              Text(
                "Outstanding now:                ${currentOs.toStringAsFixed(3)}",
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: const [
            Icon(Icons.attach_money, color: Colors.black, size: 30),
            SizedBox(width: 8),
            Text(
              "Payment Details",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
            ),
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
              Text(
                "Amount: OMR ${r.amount.toStringAsFixed(3)}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
              ),
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

  /// (Unused now) Old method for closing receipt overlay view.
  Future<void> _handleCloseView() async {
    setState(() {
      _viewingReceipt = null;
    });
    await _loadReceiptsForCompany();
    setState(() {});
  }

  /// A helper to build a black-outlined text field.
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.black45),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // Modern snackbars
  void _showMessage(String msg) {
    if (!mounted) return;
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
    if (!mounted) return;
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

  /// Format the date/time in "12 hour" style but also show date.
  String _formatDateAndTime(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
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

  Future<void> _onBillTap(String docId) async {
    await Navigator.pushNamed(
      context,
      '/invoices', // or your actual route
      arguments: docId,
    );
    await _reloadData();
    setState(() {});
  }
}
