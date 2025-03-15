import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/local_db_helper.dart';
import 'package:firebase_core/firebase_core.dart'; // if needed

class PricesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalDbHelper _localDb;

  PricesRepository(this._localDb);

  Future<void> init() async {
    await _localDb.initDb();
  }

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Load local DB only, returning { docId, itemName, price }
  Future<List<Map<String, dynamic>>> loadLocalPrices() async {
    final localData = await _localDb.getAllPrices();
    return localData.map((row) {
      return {
        'docId': row['docId'],
        'itemName': row['itemName'],
        'price': row['price'],
      };
    }).toList();
  }

  /// Pull from Firestore => local DB (overwrite).
  /// If Firestore is empty => local DB becomes empty.
  Future<void> pullFromCloud() async {
    if (!await isOnline()) {
      throw Exception("No internet. Cannot pull from cloud.");
    }
    // 1) Get all docs
    final snapshot = await _firestore.collection('prices').get();
    // 2) Clear local
    await _localDb.clearAllPrices();
    // 3) Insert docs into local
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final docId = doc.id;
      final itemName = data['itemName'] ?? 'Unknown';
      final price = (data['price'] ?? 0.0).toDouble();

      await _localDb.insertOrUpdatePrice(docId, itemName, price);
    }
  }

  /// Create a new item (docId, itemName, price) in Firestore & local DB
  Future<void> createPrice(String docId, String itemName, double price) async {
    if (!await isOnline()) {
      throw Exception("No internet. Cannot create item.");
    }
    try {
      // Firestore
      await _firestore.collection('prices').doc(docId).set({
        'itemName': itemName,
        'price': price,
      });
      // Local
      await _localDb.insertOrUpdatePrice(docId, itemName, price);
    } catch (e) {
      throw Exception("Firestore creation failed: $e");
    }
  }

  /// Update an item in Firestore & local DB by docId
  Future<void> updatePrice(String docId, String newName, double newPrice) async {
    if (!await isOnline()) {
      throw Exception("No internet. Cannot update price.");
    }
    try {
      await _firestore.collection('prices').doc(docId).set({
        'itemName': newName,
        'price': newPrice,
      }, SetOptions(merge: true));

      await _localDb.insertOrUpdatePrice(docId, newName, newPrice);
    } catch (e) {
      throw Exception("Firestore update failed: $e");
    }
  }

  /// NEW: Delete an item from Firestore & local DB by docId
  Future<void> deletePrice(String docId) async {
    if (!await isOnline()) {
      throw Exception("No internet. Cannot delete item.");
    }
    try {
      // 1) Remove from Firestore
      await _firestore.collection('prices').doc(docId).delete();
      // 2) Remove from local DB
      await _localDb.deletePrice(docId);
    } catch (e) {
      throw Exception("Firestore delete failed: $e");
    }
  }
}
