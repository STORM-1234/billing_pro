import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/prices_repository.dart';

/// A separate stateful widget for the Add Item dialog.
/// It creates and disposes its own FocusNodes and TextEditingControllers,
/// and returns a Map containing the item details when the user taps "Add".
class AddItemDialog extends StatefulWidget {
  const AddItemDialog({Key? key}) : super(key: key);

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();
  final FocusNode _addButtonFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _nameFocusNode.dispose();
    _priceFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                children: const [
                  Icon(Icons.add, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'Add Item',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                label: 'Item Name *',
                controller: _nameController,
                focusNode: _nameFocusNode,
                onSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_priceFocusNode);
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Price *',
                controller: _priceController,
                keyboardType: TextInputType.number,
                focusNode: _priceFocusNode,
                onSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_addButtonFocusNode);
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel button
                  ElevatedButton(
                    focusNode: _cancelButtonFocusNode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      // Clear controllers before closing.
                      _nameController.clear();
                      _priceController.clear();
                      Navigator.of(context).pop(null);
                    },
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  // Add button
                  ElevatedButton(
                    focusNode: _addButtonFocusNode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final name = _nameController.text.trim();
                      final priceText = _priceController.text.trim();
                      if (name.isEmpty || priceText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Name & Price required.')),
                        );
                        return;
                      }
                      Navigator.of(context).pop({
                        'name': name,
                        'price': double.tryParse(priceText) ?? 0.0,
                      });
                    },
                    child: const Text('Add',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Helper to build a text field with outlined borders.
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

class PricesPage extends StatefulWidget {
  final PricesRepository repo;
  const PricesPage({Key? key, required this.repo}) : super(key: key);

  @override
  State<PricesPage> createState() => _PricesPageState();
}

class _PricesPageState extends State<PricesPage> {
  bool _isLoading = false;
  bool _isUploading = false;

  bool _isOnline = false;

  /// Full list of items from local DB: each is { docId, itemName, price }
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];

  String _searchQuery = '';

  /// Currently selected item
  Map<String, dynamic>? _selectedItem;

  /// For editing the selected item
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  /// Focus nodes for editing the selected item
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();
  final FocusNode _saveButtonFocusNode = FocusNode();

  /// Whether the selected item is in 'edit' mode
  bool _selectedItemIsEditing = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _checkOnlineStatus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _priceController.dispose();
    _nameFocusNode.dispose();
    _priceFocusNode.dispose();
    _saveButtonFocusNode.dispose();
    super.dispose();
  }

  /// Check if online
  Future<void> _checkOnlineStatus() async {
    final online = await widget.repo.isOnline();
    if (!mounted) return;
    setState(() {
      _isOnline = online;
    });
  }

  /// Load from local DB => _allItems => _filteredItems
  Future<void> _loadLocalData() async {
    setState(() => _isLoading = true);
    try {
      final data = await widget.repo.loadLocalPrices();
      _allItems = data; // each is { docId, itemName, price }
      setState(() {
        _filteredItems = List.from(_allItems);
      });
    } catch (e) {
      _showError("Error loading local data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Debounced search by itemName
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final lower = query.toLowerCase();
      List<Map<String, dynamic>> matches;
      if (lower.isEmpty) {
        matches = List.from(_allItems);
      } else {
        matches = _allItems.where((item) {
          final name = (item['itemName'] ?? '').toString().toLowerCase();
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
        _searchQuery = query;
        _filteredItems = matches;
      });
    });
  }

  /// Pull from Firestore => local => refresh
  Future<void> _pullFromCloud() async {
    setState(() => _isLoading = true);
    try {
      await _checkOnlineStatus();
      if (!_isOnline) {
        throw Exception("Cannot pull from Cloud: Offline.");
      }
      await widget.repo.pullFromCloud();
      await _loadLocalData();
      _showMessage("Pulled data from Cloud.");
    } catch (e) {
      _showError("Error pulling from Cloud: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Upload Excel => triggers Cloud Function => writes to Firestore
  Future<void> _uploadExcelToCloud() async {
    try {
      setState(() => _isUploading = true);

      await _checkOnlineStatus();
      if (!_isOnline) {
        throw Exception("Cannot upload: Offline.");
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final file = File(filePath);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('price_uploads/my_prices_file.xlsx');

      await storageRef.putFile(file);
      _showMessage("Excel uploaded! Wait for Cloud Function, then sync from cloud.");
    } catch (e) {
      _showError("Error uploading Excel: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// Called when user taps a row => select item
  void _selectItem(Map<String, dynamic> item) {
    setState(() {
      _selectedItem = item;
      _selectedItemIsEditing = false;
      _nameController.text = item['itemName'].toString();
      // Format the price with OMR and 3 digits after decimal
      final price = double.tryParse(item['price'].toString()) ?? 0.0;
      _priceController.text = price.toStringAsFixed(3);
      _nameFocusNode.requestFocus();
    });
  }

  /// Clear selection => show list again
  void _clearSelection() {
    setState(() {
      _selectedItem = null;
      _selectedItemIsEditing = false;
      _nameController.clear();
      _priceController.clear();
    });
  }

  /// Toggle between edit/save for the selected item.
  Future<void> _toggleEditSelectedItem() async {
    if (_selectedItem == null) return;

    if (!_selectedItemIsEditing) {
      await _checkOnlineStatus();
      if (!_isOnline) {
        _showError("Cannot edit offline.");
        return;
      }
      setState(() {
        _selectedItemIsEditing = true;
      });
      _nameFocusNode.requestFocus();
    } else {
      await _checkOnlineStatus();
      if (!_isOnline) {
        _showError("Cannot save offline.");
        return;
      }
      await _saveSelectedItem();
      setState(() {
        _selectedItemIsEditing = false;
      });
    }
  }

  /// Save changes to Firestore and update local lists.
  Future<void> _saveSelectedItem() async {
    if (_selectedItem == null) return;

    final docId = _selectedItem!['docId'] as String;
    final newName = _nameController.text.trim();
    final newPrice = double.tryParse(_priceController.text.trim()) ??
        (_selectedItem!['price'] as double);

    try {
      await widget.repo.updatePrice(docId, newName, newPrice);

      final masterIndex = _allItems.indexWhere((i) => i['docId'] == docId);
      if (masterIndex != -1) {
        _allItems[masterIndex]['itemName'] = newName;
        _allItems[masterIndex]['price'] = newPrice;
      }
      final filteredIndex = _filteredItems.indexWhere((i) => i['docId'] == docId);
      if (filteredIndex != -1) {
        _filteredItems[filteredIndex]['itemName'] = newName;
        _filteredItems[filteredIndex]['price'] = newPrice;
      }

      _selectedItem!['itemName'] = newName;
      _selectedItem!['price'] = newPrice;

      _onSearchChanged(_searchQuery);
      _showMessage("Item updated successfully.");
    } catch (e) {
      _showError("Error updating item: $e");
    }
  }

  /// Delete the selected item
  Future<void> _deleteSelectedItem() async {
    if (_selectedItem == null) return;
    final docId = _selectedItem!['docId'] as String;

    await _checkOnlineStatus();
    if (!_isOnline) {
      _showError("Cannot delete offline.");
      return;
    }

    try {
      await widget.repo.deletePrice(docId);

      _allItems.removeWhere((i) => i['docId'] == docId);
      _filteredItems.removeWhere((i) => i['docId'] == docId);

      _showMessage("Item deleted.");
      _clearSelection();
    } catch (e) {
      _showError("Error deleting item: $e");
    }
  }

  /// Show a dialog to add a new item.
  /// The dialog now returns a Map with 'name' and 'price' if the user taps "Add",
  /// or null if canceled.
  Future<void> _showAddItemDialog() async {
    final result = await showDialog<Map<String, dynamic>?>(context: context, barrierDismissible: false, builder: (ctx) => const AddItemDialog(),);

    if (result != null) {
      final docRef = FirebaseFirestore.instance.collection('prices').doc();
      final docId = docRef.id;
      final name = result['name'] as String;
      final price = result['price'] as double;
      await _createItem(docId, name, price);
    }
  }

  /// Actually create the item in Firestore + local
  Future<void> _createItem(String docId, String itemName, double price) async {
    setState(() => _isLoading = true);
    try {
      await _checkOnlineStatus();
      if (!_isOnline) {
        throw Exception("Cannot create item offline.");
      }
      await widget.repo.createPrice(docId, itemName, price);
      await _loadLocalData();
      _showMessage("Item created successfully.");
    } catch (e) {
      _showError("Error creating item: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Helper: black-outlined text field with optional focus and onSubmitted
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

  @override
  Widget build(BuildContext context) {
    final overlay = _isUploading
        ? Container(
      color: Colors.black54,
      child: const Center(child: CircularProgressIndicator()),
    )
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        titleSpacing: 0,
        title: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            style: const TextStyle(color: Colors.black),
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search for an item...',
              hintStyle: TextStyle(color: Colors.black54),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Colors.black),
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _uploadExcelToCloud,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _pullFromCloud,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            _selectedItem == null
                ? _buildSearchResultsList()
                : _buildSelectedItemCard(),
          if (overlay != null) overlay,
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isOnline
            ? _showAddItemDialog
            : () => _showError("Cannot add item offline."),
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  /// Shows the list of filtered items
  Widget _buildSearchResultsList() {
    if (_filteredItems.isEmpty && _searchQuery.isNotEmpty) {
      return const Center(
        child: Text(
          'No Results Found',
          style: TextStyle(color: Colors.black, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        final backgroundColor = index % 2 == 0
            ? Colors.grey.shade200
            : Colors.grey.shade300;
        // Format the price to 3 decimal places and prefix with OMR.
        final price = double.tryParse(item['price'].toString()) ?? 0.0;
        final formattedPrice = 'OMR ${price.toStringAsFixed(3)}';
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: InkWell(
              onTap: () => _selectItem(item),
              child: Container(
                margin:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Item Name (left)
                    Expanded(
                      child: Text(
                        item['itemName'].toString(),
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Price (right) with OMR formatting
                    Text(
                      'Price: $formattedPrice',
                      style: const TextStyle(color: Colors.black, fontSize: 16),
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

  /// Shows the single item card with Edit/Save, Clear, and Delete buttons.
  Widget _buildSelectedItemCard() {
    final editing = _selectedItemIsEditing;
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Card(
          color: Colors.grey.shade100,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  enabled: editing,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    labelStyle: TextStyle(color: Colors.black54),
                  ),
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_priceFocusNode);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceController,
                  focusNode: _priceFocusNode,
                  enabled: editing,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    labelStyle: TextStyle(color: Colors.black54),
                  ),
                  onSubmitted: (_) {
                    FocusScope.of(context).requestFocus(_saveButtonFocusNode);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Focus(
                    focusNode: _saveButtonFocusNode,
                    child: ElevatedButton(
                      onPressed: _isOnline
                          ? _toggleEditSelectedItem
                          : () => _showError("Cannot edit offline."),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        editing ? Colors.green : Colors.black,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        editing ? 'Save' : 'Edit',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _clearSelection,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: Colors.black26),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Clear Selection'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isOnline
                        ? _deleteSelectedItem
                        : () => _showError("Cannot delete offline."),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(color: Colors.white)),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _showError(String err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err)),
    );
  }
}
