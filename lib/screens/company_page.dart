import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

import '../services/companies_repository.dart';
import '../models/company.dart';
import 'SubScreen/company_details_page.dart';

class CompanyPage extends StatefulWidget {
  final CompaniesRepository repo;
  const CompanyPage({Key? key, required this.repo}) : super(key: key);

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  bool _isLoading = false;

  /// Full list of companies from local DB
  final List<Company> _allCompanies = [];

  /// Filtered list after search
  final List<Company> _filteredCompanies = [];

  final TextEditingController _searchController = TextEditingController();

  /// Track which grid item is hovered/selected for keyboard navigation
  int _hoveredIndex = 0;

  /// Focus node for grid keyboard navigation
  final FocusNode _gridFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    // Request focus for grid navigation.
    _gridFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    setState(() => _isLoading = true);
    try {
      final companies = await widget.repo.loadLocalCompanies();
      setState(() {
        _allCompanies
          ..clear()
          ..addAll(companies);
        _filteredCompanies
          ..clear()
          ..addAll(companies);
      });
    } catch (e) {
      _showError("Error loading companies: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Pull from Firestore => local => refresh
  Future<void> _pullFromCloud() async {
    setState(() => _isLoading = true);
    try {
      await widget.repo.pullFromCloud();
      await _loadLocalData();
      _showMessage("Pulled data from Cloud.");
    } catch (e) {
      _showError("Error pulling from Cloud: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Sync unsynced changes
  Future<void> _syncDatabase() async {
    setState(() => _isLoading = true);
    try {
      await widget.repo.syncAllUnsyncedCompanies();
      await _loadLocalData();
      _showMessage("Synced unsynced changes.");
    } catch (e) {
      _showError("Error syncing: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Show a dialog to add a new company with Enter navigation between fields.
  Future<void> _showAddCompanyDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final descController = TextEditingController();
    // Controllers for CR and VAT numbers.
    final crController = TextEditingController();
    final vatController = TextEditingController();

    // Create local FocusNodes for each field.
    final companyNameFocusNode = FocusNode();
    final phoneFocusNode = FocusNode();
    final addressFocusNode = FocusNode();
    final descriptionFocusNode = FocusNode();
    final crFocusNode = FocusNode();
    final vatFocusNode = FocusNode();
    final addButtonFocusNode = FocusNode();

    final added = await showDialog<bool>(
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
                  // Title row
                  Row(
                    children: [
                      const Icon(Icons.add, color: Colors.black),
                      const SizedBox(width: 8),
                      const Text(
                        'Add Company',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Company Name *',
                    controller: nameController,
                    focusNode: companyNameFocusNode,
                    onSubmitted: (_) {
                      FocusScope.of(ctx).requestFocus(phoneFocusNode);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Phone *',
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    focusNode: phoneFocusNode,
                    onSubmitted: (_) {
                      FocusScope.of(ctx).requestFocus(addressFocusNode);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Address',
                    controller: addressController,
                    focusNode: addressFocusNode,
                    onSubmitted: (_) {
                      FocusScope.of(ctx).requestFocus(descriptionFocusNode);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'Description',
                    controller: descController,
                    focusNode: descriptionFocusNode,
                    onSubmitted: (_) {
                      FocusScope.of(ctx).requestFocus(crFocusNode);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'CR Number',
                    controller: crController,
                    focusNode: crFocusNode,
                    onSubmitted: (_) {
                      FocusScope.of(ctx).requestFocus(vatFocusNode);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    label: 'VAT Number',
                    controller: vatController,
                    focusNode: vatFocusNode,
                    onSubmitted: (_) {
                      FocusScope.of(ctx).requestFocus(addButtonFocusNode);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Buttons row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx, false);
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Focus(
                        focusNode: addButtonFocusNode,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            final name = nameController.text.trim();
                            final phone = phoneController.text.trim();
                            if (name.isEmpty || phone.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Name & Phone required.'),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                          child: const Text(
                            'Add',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
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

    if (added == true) {
      final docRef = FirebaseFirestore.instance.collection('companies').doc();
      final docId = docRef.id;
      final name = nameController.text.trim();
      final phone = phoneController.text.trim();
      final address = addressController.text.trim();
      final desc = descController.text.trim();
      final crNum = crController.text.trim();
      final vatNum = vatController.text.trim();

      await _createCompany(
        docId: docId,
        name: name,
        phone: phone,
        address: address,
        description: desc,
        crNumber: crNum,
        vatNumber: vatNum,
      );
    }
    // No need to manually dispose the local controllers and focus nodes here.
  }

  /// Helper that calls the repository to create a new company.
  Future<void> _createCompany({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,
    String? crNumber,
    String? vatNumber,
  }) async {
    setState(() => _isLoading = true);
    try {
      await widget.repo.createCompany(
        docId: docId,
        name: name,
        phone: phone,
        address: address,
        description: description,
        crNumber: crNumber,
        vatNumber: vatNumber,
      );
      await _loadLocalData();
      _showMessage("Company created successfully.");
    } catch (e) {
      _showError("Error creating company: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Filters companies by name.
  void _onSearchChanged(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) {
      setState(() {
        _filteredCompanies
          ..clear()
          ..addAll(_allCompanies);
      });
      return;
    }
    final results = _allCompanies.where((c) {
      return c.name.toLowerCase().contains(lower);
    }).toList();
    setState(() {
      _filteredCompanies
        ..clear()
        ..addAll(results);
    });
  }

  @override
  Widget build(BuildContext context) {
    final overlay = _isLoading
        ? Container(
      color: Colors.black54,
      child: const Center(child: CircularProgressIndicator()),
    )
        : null;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Colors.black),
          decoration: const InputDecoration(
            hintText: 'Search by company name...',
            hintStyle: TextStyle(color: Colors.black54),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search, color: Colors.black),
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _pullFromCloud,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncDatabase,
            tooltip: 'Sync Database',
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildGridBody(),
          if (overlay != null) overlay,
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCompanyDialog,
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  /// Grid body with keyboard navigation between company cards.
  Widget _buildGridBody() {
    if (_filteredCompanies.isEmpty && _searchController.text.isNotEmpty) {
      return const Center(child: Text('No matching companies'));
    }
    if (_filteredCompanies.isEmpty) {
      return const Center(child: Text('No companies found.'));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: RawKeyboardListener(
        focusNode: _gridFocusNode,
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent) {
            // Tab key: cycle to next card.
            if (event.logicalKey == LogicalKeyboardKey.tab) {
              setState(() {
                _hoveredIndex = (_hoveredIndex + 1) % _filteredCompanies.length;
              });
            }
            // Arrow keys navigation.
            else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (_hoveredIndex < _filteredCompanies.length - 1) {
                setState(() {
                  _hoveredIndex += 1;
                });
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (_hoveredIndex > 0) {
                setState(() {
                  _hoveredIndex -= 1;
                });
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              const int crossAxisCount = 3;
              int newIndex = _hoveredIndex + crossAxisCount;
              if (newIndex >= _filteredCompanies.length) {
                newIndex = _filteredCompanies.length - 1;
              }
              setState(() {
                _hoveredIndex = newIndex;
              });
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              const int crossAxisCount = 3;
              int newIndex = _hoveredIndex - crossAxisCount;
              if (newIndex < 0) {
                newIndex = 0;
              }
              setState(() {
                _hoveredIndex = newIndex;
              });
            }
            // Escape key acts as a back button.
            else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(context);
            }
          }
        },
        child: GridView.builder(
          itemCount: _filteredCompanies.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, // 3 columns
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.2,
          ),
          itemBuilder: (context, index) {
            final comp = _filteredCompanies[index];
            return _buildCompanyCard(comp, index);
          },
        ),
      ),
    );
  }

  Widget _buildCompanyCard(Company comp, int index) {
    // Use comp.isSynced if available; adjust accordingly.
    final syncColor = comp.isSynced ? Colors.green : Colors.red;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _hoveredIndex == index
              ? [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black12, blurRadius: 2, offset: const Offset(0, 2))],
        ),
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CompanyDetailsPage(
                  repo: widget.repo,
                  company: comp,
                ),
              ),
            );
            _loadLocalData();
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  comp.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Phone: ${comp.phone}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Text(
                  'Outstanding: OMR ${comp.outstanding.toStringAsFixed(3)}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: syncColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  /// Build a single black-outlined text field inline.
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      focusNode: focusNode,
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
      onSubmitted: onSubmitted,
    );
  }
}
