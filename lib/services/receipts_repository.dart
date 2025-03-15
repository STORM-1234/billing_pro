// lib/services/receipts_repository.dart

import '../database/local_db_helper.dart';

/// Simple data model for a receipt in local DB
class ReceiptModel {
  final String docId;
  final String companyDocId;
  final double amount;
  final String date; // ISO string, e.g. "2025-01-01T10:00:00Z"

  /// We'll store additional info (receiptNumber, etc.) in extraJson
  final String? extraJson;

  ReceiptModel({
    required this.docId,
    required this.companyDocId,
    required this.amount,
    required this.date,
    this.extraJson, // default null if no extra data
  });
}

class ReceiptsRepository {
  /// Expose localDb so UI code can call `widget.receiptsRepo.localDb` if needed
  final LocalDbHelper localDb;

  ReceiptsRepository(this.localDb);

  /// Load all receipts from local DB
  Future<List<ReceiptModel>> loadAllReceipts() async {
    final rows = await localDb.getAllReceipts();
    return rows.map((r) {
      return ReceiptModel(
        docId: r['docId'],
        companyDocId: r['companyDocId'],
        amount: (r['amount'] as num).toDouble(),
        date: r['date'],
        extraJson: r['extraJson'], // read extraJson if your DB has this column
      );
    }).toList();
  }

  /// Create a new receipt
  Future<void> createReceipt(ReceiptModel rc) async {
    await localDb.insertOrUpdateReceipt(
      docId: rc.docId,
      companyDocId: rc.companyDocId,
      amount: rc.amount,
      date: rc.date,
      extraJson: rc.extraJson, // store JSON data if present
    );
  }

  /// Update an existing receipt
  Future<void> updateReceipt(ReceiptModel rc) async {
    await localDb.insertOrUpdateReceipt(
      docId: rc.docId,
      companyDocId: rc.companyDocId,
      amount: rc.amount,
      date: rc.date,
      extraJson: rc.extraJson, // store JSON data if present
    );
  }

  /// Delete a receipt
  Future<void> deleteReceipt(String docId) async {
    await localDb.deleteReceipt(docId);
  }
}
