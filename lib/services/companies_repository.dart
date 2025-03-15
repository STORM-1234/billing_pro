import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../database/local_db_helper.dart';
import '../models/company.dart';

class CompaniesRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalDbHelper _localDb;
  LocalDbHelper get localDb => _localDb;

  CompaniesRepository(this._localDb);

  Future<void> init() async {
    await _localDb.initDb();
  }

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Load from local DB => returns List<Company>.
  /// (Make sure your Company model has crNumber, vatNumber fields.)
  Future<List<Company>> loadLocalCompanies() async {
    final rows = await _localDb.getAllCompanies();
    return rows.map((r) {
      return Company(
        docId: r['docId'],
        name: r['name'],
        phone: r['phone'],
        address: r['address'],
        description: r['description'],
        outstanding: (r['outstanding'] as num).toDouble(),
        isSynced: (r['isSynced'] == null || (r['isSynced'] as int) == 1),

        // NEW: read them if your table has these columns
        crNumber: r['crNumber'] ?? '',
        vatNumber: r['vatNumber'] ?? '',
      );
    }).toList();
  }

  /// Pull from Firestore => local DB (merge or overwrite).
  /// Now also read crNumber, vatNumber if present in Firestore.
  Future<void> pullFromCloud() async {
    if (!await isOnline()) {
      throw Exception("No internet. Cannot pull from cloud.");
    }
    final snapshot = await _firestore.collection('companies').get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final docId = doc.id;

      final name = data['name'] ?? 'Unknown';
      final phone = data['phone'] ?? '';
      final address = data['address'] ?? '';
      final description = data['description'] ?? '';
      final outstanding = (data['outstanding'] ?? 0.0).toDouble();

      // NEW: if you store them in Firestore
      final crNumber = data['crNumber'] ?? '';
      final vatNumber = data['vatNumber'] ?? '';

      // Insert or update local DB with docId
      await _localDb.insertOrUpdateCompany(
        docId: docId,
        name: name,
        phone: phone,
        address: address,
        description: description,
        outstanding: outstanding,
        isSynced: true, // we just synced from Firestore

        // NEW: pass them to local DB
        crNumber: crNumber,
        vatNumber: vatNumber,
      );
    }
  }

  /// Create a new company with docId, name, phone, address, description, crNumber, vatNumber.
  /// If offline, isSynced=false. If online, also push to Firestore.
  Future<void> createCompany({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,

    // NEW
    String? crNumber,
    String? vatNumber,
  }) async {
    final online = await isOnline();

    // Insert local DB first
    await _localDb.insertOrUpdateCompany(
      docId: docId,
      name: name,
      phone: phone,
      address: address,
      description: description,
      outstanding: 0.0,
      isSynced: online,

      // NEW
      crNumber: crNumber ?? '',
      vatNumber: vatNumber ?? '',
    );

    // If online, also create in Firestore
    if (online) {
      await _firestore.collection('companies').doc(docId).set({
        'name': name,
        'phone': phone,
        'address': address ?? '',
        'description': description ?? '',
        'outstanding': 0.0,

        // NEW
        'crNumber': crNumber ?? '',
        'vatNumber': vatNumber ?? '',
      });
    }
  }

  /// Increase a company's outstanding by [credit].
  /// Mark unsynced locally, then push if online.
  Future<void> addBillForCompany(String docId, double credit) async {
    final local = await loadLocalCompanies();
    final comp = local.firstWhere((c) => c.docId == docId,
        orElse: () => throw Exception("No local record for $docId"));

    final newOutstanding = comp.outstanding + credit;

    // Mark local as unsynced
    await _localDb.updateCompanyOutstanding(docId, newOutstanding, false);

    final online = await isOnline();
    if (online) {
      try {
        await _firestore.collection('companies').doc(docId).update({
          'outstanding': newOutstanding,
        });
        // Mark synced if success
        await _localDb.updateCompanyOutstanding(docId, newOutstanding, true);
      } catch (_) {
        // remain unsynced
      }
    }
  }

  /// Update a company's details (including CR & VAT).
  /// Mark unsynced locally, then push if online.
  Future<void> updateCompanyDetails({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,

    // NEW
    String? crNumber,
    String? vatNumber,
  }) async {
    // Mark local as unsynced
    await _localDb.updateCompanyDetails(
      docId: docId,
      name: name,
      phone: phone,
      address: address,
      description: description,
      isSynced: false,

      // NEW
      crNumber: crNumber,
      vatNumber: vatNumber,
    );

    final online = await isOnline();
    if (online) {
      try {
        await _firestore.collection('companies').doc(docId).update({
          'name': name,
          'phone': phone,
          'address': address ?? '',
          'description': description ?? '',

          // NEW
          'crNumber': crNumber ?? '',
          'vatNumber': vatNumber ?? '',
        });
        // Mark synced if success
        await _localDb.updateCompanyDetails(
          docId: docId,
          name: name,
          phone: phone,
          address: address,
          description: description,
          isSynced: true,

          crNumber: crNumber,
          vatNumber: vatNumber,
        );
      } catch (_) {
        // remain unsynced
      }
    }
  }

  /// Update only the outstanding field
  Future<void> updateCompanyOutstanding(String docId, double newValue) async {
    // Mark local as unsynced
    await _localDb.updateCompanyOutstanding(docId, newValue, false);

    final online = await isOnline();
    if (online) {
      try {
        await _firestore.collection('companies').doc(docId).update({
          'outstanding': newValue,
        });
        // Mark local as synced
        await _localDb.updateCompanyOutstanding(docId, newValue, true);
      } catch (_) {
        // remain unsynced
      }
    }
  }

  /// Delete a company from Firestore & local
  Future<void> deleteCompany(String docId) async {
    final online = await isOnline();
    if (online) {
      await _firestore.collection('companies').doc(docId).delete();
    }
    // remove local
    await _localDb.deleteCompany(docId);
  }

  /// Sync unsynced companies
  Future<void> syncAllUnsyncedCompanies() async {
    if (!await isOnline()) {
      throw Exception("Offline, cannot sync now.");
    }
    final all = await loadLocalCompanies();
    for (final c in all) {
      if (!c.isSynced) {
        // push to Firestore
        await _firestore.collection('companies').doc(c.docId).set({
          'name': c.name,
          'phone': c.phone,
          'address': c.address ?? '',
          'description': c.description ?? '',
          'outstanding': c.outstanding,

          // NEW
          'crNumber': c.crNumber ?? '',
          'vatNumber': c.vatNumber ?? '',
        });
        // mark synced
        await _localDb.updateCompanyDetails(
          docId: c.docId,
          name: c.name,
          phone: c.phone,
          address: c.address,
          description: c.description,
          isSynced: true,

          // also pass the new fields

        );
      }
    }
  }
}
