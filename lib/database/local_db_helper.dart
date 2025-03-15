import 'dart:io'; // for Directory
import 'package:flutter/cupertino.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalDbHelper {
  static const _dbName = 'prices_db.db';

  // Table names
  static const _tablePrices = 'prices';
  static const _tableCompanies = 'companies';
  static const _tableBills = 'bills';
  static const _tableReceipts = 'receipts';
  static const _tableSettings = 'app_settings'; // For key-value pairs
  static const _tableNotes = 'notes'; // New table for storing notes

  Database? _db;

  Future<void> initDb() async {
    // 1) Get the base "Application Support" directory
    final baseDir = await getApplicationSupportDirectory();

    // 2) Create a subfolder named "Crown Plastic" if it doesn't exist
    final crownPlasticFolder = p.join(baseDir.path, 'Crown Plastic');
    await Directory(crownPlasticFolder).create(recursive: true);

    // 3) Build the final DB path => e.g. ".../Crown Plastic/prices_db.db"
    final dbPath = p.join(crownPlasticFolder, _dbName);

    debugPrint('DB Path: $dbPath');

    // 4) Open the database (version bumped from 7 to 8)
    _db = await openDatabase(
      dbPath,
      version: 8,
      onCreate: (db, version) async {
        // 1) prices
        await db.execute('''
          CREATE TABLE $_tablePrices (
            docId TEXT PRIMARY KEY,
            itemName TEXT NOT NULL,
            price REAL NOT NULL
          )
        ''');

        // 2) companies
        await db.execute('''
          CREATE TABLE $_tableCompanies (
            docId TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            address TEXT,
            description TEXT,
            outstanding REAL NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 1,
            crNumber TEXT,
            vatNumber TEXT
          )
        ''');

        // 3) bills (invoices)
        await db.execute('''
          CREATE TABLE $_tableBills (
            docId TEXT PRIMARY KEY,
            companyDocId TEXT NOT NULL,
            total REAL NOT NULL,
            date TEXT NOT NULL,
            lineItemsJson TEXT
          )
        ''');

        // 4) receipts (with extraJson)
        await db.execute('''
          CREATE TABLE $_tableReceipts (
            docId TEXT PRIMARY KEY,
            companyDocId TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            extraJson TEXT
          )
        ''');

        // 5) app_settings table for key-value pairs
        await db.execute('''
          CREATE TABLE $_tableSettings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        // 6) New notes table for storing calendar notes
        await db.execute('''
          CREATE TABLE $_tableNotes (
            date TEXT PRIMARY KEY,
            note TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // If user had version < 2, create new tables for companies/bills/receipts
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE $_tableCompanies (
              docId TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              address TEXT,
              description TEXT,
              outstanding REAL NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE $_tableBills (
              docId TEXT PRIMARY KEY,
              companyDocId TEXT NOT NULL,
              total REAL NOT NULL,
              date TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE $_tableReceipts (
              docId TEXT PRIMARY KEY,
              companyDocId TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL
            )
          ''');
        }
        // If user had version < 3, add isSynced column to companies
        if (oldVersion < 3) {
          await db.execute('''
            ALTER TABLE $_tableCompanies
            ADD COLUMN isSynced INTEGER NOT NULL DEFAULT 1
          ''');
        }
        // If user had version < 4, add lineItemsJson to bills
        if (oldVersion < 4) {
          await db.execute('''
            ALTER TABLE $_tableBills
            ADD COLUMN lineItemsJson TEXT
          ''');
        }
        // If user had version < 5, create the app_settings table
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE $_tableSettings (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
        // If user had version < 6, add extraJson to receipts
        if (oldVersion < 6) {
          await db.execute('''
            ALTER TABLE $_tableReceipts
            ADD COLUMN extraJson TEXT
          ''');
        }
        // If user had version < 7, add crNumber & vatNumber columns to companies
        if (oldVersion < 7) {
          await db.execute('''
            ALTER TABLE $_tableCompanies
            ADD COLUMN crNumber TEXT
          ''');
          await db.execute('''
            ALTER TABLE $_tableCompanies
            ADD COLUMN vatNumber TEXT
          ''');
        }
        // New upgrade: If user had version < 8, create the notes table.
        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE $_tableNotes (
              date TEXT PRIMARY KEY,
              note TEXT
            )
          ''');
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Prices Table
  // ---------------------------------------------------------------------------
  Future<void> insertOrUpdatePrice(String docId, String itemName, double price) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tablePrices,
      where: 'docId = ?',
      whereArgs: [docId],
    );

    final row = {
      'docId': docId,
      'itemName': itemName,
      'price': price,
    };

    if (existing.isEmpty) {
      await _db!.insert(_tablePrices, row);
    } else {
      await _db!.update(
        _tablePrices,
        row,
        where: 'docId = ?',
        whereArgs: [docId],
      );
    }
  }

  Future<void> createPrice(String docId, String itemName, double price) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tablePrices,
      where: 'docId = ?',
      whereArgs: [docId],
    );

    final row = {
      'docId': docId,
      'itemName': itemName,
      'price': price,
    };

    if (existing.isEmpty) {
      await _db!.insert(_tablePrices, row);
    } else {
      await _db!.update(
        _tablePrices,
        row,
        where: 'docId = ?',
        whereArgs: [docId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllPrices() async {
    if (_db == null) return [];
    return await _db!.query(_tablePrices);
  }

  Future<void> deletePrice(String docId) async {
    if (_db == null) return;
    await _db!.delete(
      _tablePrices,
      where: 'docId = ?',
      whereArgs: [docId],
    );
  }

  Future<void> clearAllPrices() async {
    if (_db == null) return;
    await _db!.delete(_tablePrices);
  }

  // ---------------------------------------------------------------------------
  // Companies Table
  // ---------------------------------------------------------------------------
  Future<void> insertOrUpdateCompany({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,
    double outstanding = 0.0,
    bool isSynced = true,
    String? crNumber,
    String? vatNumber,
  }) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tableCompanies,
      where: 'docId = ?',
      whereArgs: [docId],
    );

    final row = {
      'docId': docId,
      'name': name,
      'phone': phone,
      'address': address ?? '',
      'description': description ?? '',
      'outstanding': outstanding,
      'isSynced': isSynced ? 1 : 0,
      'crNumber': crNumber ?? '',
      'vatNumber': vatNumber ?? '',
    };

    if (existing.isEmpty) {
      await _db!.insert(_tableCompanies, row);
    } else {
      await _db!.update(
        _tableCompanies,
        row,
        where: 'docId = ?',
        whereArgs: [docId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllCompanies() async {
    if (_db == null) return [];
    return await _db!.query(_tableCompanies);
  }

  Future<void> updateCompanyOutstanding(String docId, double newVal, bool isSynced) async {
    if (_db == null) return;
    await _db!.update(
      _tableCompanies,
      {
        'outstanding': newVal,
        'isSynced': isSynced ? 1 : 0,
      },
      where: 'docId = ?',
      whereArgs: [docId],
    );
  }

  Future<void> updateCompanyDetails({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,
    bool isSynced = false,
    String? crNumber,
    String? vatNumber,
  }) async {
    if (_db == null) return;
    await _db!.update(
      _tableCompanies,
      {
        'name': name,
        'phone': phone,
        'address': address ?? '',
        'description': description ?? '',
        'isSynced': isSynced ? 1 : 0,
        if (crNumber != null) 'crNumber': crNumber,
        if (vatNumber != null) 'vatNumber': vatNumber,
      },
      where: 'docId = ?',
      whereArgs: [docId],
    );
  }

  Future<void> deleteCompany(String docId) async {
    if (_db == null) return;
    await _db!.delete(
      _tableCompanies,
      where: 'docId = ?',
      whereArgs: [docId],
    );
  }

  Future<void> clearAllCompanies() async {
    if (_db == null) return;
    await _db!.delete(_tableCompanies);
  }

  // ---------------------------------------------------------------------------
  // Bills Table (invoices)
  // ---------------------------------------------------------------------------
  Future<void> insertOrUpdateBill({
    required String docId,
    required String companyDocId,
    required double total,
    required String date,
    String? lineItemsJson,
  }) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tableBills,
      where: 'docId = ?',
      whereArgs: [docId],
    );

    final row = {
      'docId': docId,
      'companyDocId': companyDocId,
      'total': total,
      'date': date,
      'lineItemsJson': lineItemsJson,
    };

    if (existing.isEmpty) {
      await _db!.insert(_tableBills, row);
    } else {
      await _db!.update(
        _tableBills,
        row,
        where: 'docId = ?',
        whereArgs: [docId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllBills() async {
    if (_db == null) return [];
    return await _db!.query(_tableBills);
  }

  Future<void> deleteBill(String docId) async {
    if (_db == null) return;
    await _db!.delete(
      _tableBills,
      where: 'docId = ?',
      whereArgs: [docId],
    );
  }

  Future<void> clearAllBills() async {
    if (_db == null) return;
    await _db!.delete(_tableBills);
  }

  // ---------------------------------------------------------------------------
  // Receipts Table
  // ---------------------------------------------------------------------------
  Future<void> insertOrUpdateReceipt({
    required String docId,
    required String companyDocId,
    required double amount,
    required String date,
    String? extraJson,
  }) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tableReceipts,
      where: 'docId = ?',
      whereArgs: [docId],
    );

    final row = {
      'docId': docId,
      'companyDocId': companyDocId,
      'amount': amount,
      'date': date,
      'extraJson': extraJson,
    };

    if (existing.isEmpty) {
      await _db!.insert(_tableReceipts, row);
    } else {
      await _db!.update(
        _tableReceipts,
        row,
        where: 'docId = ?',
        whereArgs: [docId],
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllReceipts() async {
    if (_db == null) return [];
    return await _db!.query(_tableReceipts);
  }

  Future<void> deleteReceipt(String docId) async {
    if (_db == null) return;
    await _db!.delete(
      _tableReceipts,
      where: 'docId = ?',
      whereArgs: [docId],
    );
  }

  Future<void> clearAllReceipts() async {
    if (_db == null) return;
    await _db!.delete(_tableReceipts);
  }

  // ---------------------------------------------------------------------------
  // app_settings table for storing key-value pairs (e.g. invoiceCounter)
  // ---------------------------------------------------------------------------
  Future<String?> getSetting(String key) async {
    if (_db == null) return null;
    final rows = await _db!.query(
      _tableSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tableSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    final row = {
      'key': key,
      'value': value,
    };

    if (existing.isEmpty) {
      await _db!.insert(_tableSettings, row);
    } else {
      await _db!.update(
        _tableSettings,
        row,
        where: 'key = ?',
        whereArgs: [key],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // New Notes Table Functions
  // ---------------------------------------------------------------------------
  Future<void> insertOrUpdateNote(String date, String note) async {
    if (_db == null) return;

    final existing = await _db!.query(
      _tableNotes,
      where: 'date = ?',
      whereArgs: [date],
    );

    final row = {
      'date': date,
      'note': note,
    };

    if (existing.isEmpty) {
      await _db!.insert(_tableNotes, row);
    } else {
      await _db!.update(
        _tableNotes,
        row,
        where: 'date = ?',
        whereArgs: [date],
      );
    }
  }

  Future<String?> getNote(String date) async {
    if (_db == null) return null;
    final rows = await _db!.query(
      _tableNotes,
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['note'] as String?;
  }

  Future<Map<String, String>> getAllNotes() async {
    if (_db == null) return {};
    final List<Map<String, dynamic>> results = await _db!.query(_tableNotes);
    final Map<String, String> notes = {};
    for (var row in results) {
      final date = row['date'] as String;
      final note = row['note'] as String? ?? "";
      notes[date] = note;
    }
    return notes;
  }
}