import '../database/local_db_helper.dart';

class InvoiceModel {
  final String docId;
  final String companyDocId;
  final double total;
  final String date; // ISO string, e.g. "2025-01-01T10:00:00Z"
  final String? lineItemsJson; // optional JSON field for line items

  InvoiceModel({
    required this.docId,
    required this.companyDocId,
    required this.total,
    required this.date,
    this.lineItemsJson, // default null if no line items
  });
}

class InvoicesRepository {
  /// We keep the same private field.
  final LocalDbHelper _localDb;

  /// NEW: Provide a public getter so other code can do `invoicesRepo.localDb.getAllBills()`
  LocalDbHelper get localDb => _localDb;

  InvoicesRepository(this._localDb);

  Future<List<InvoiceModel>> loadAllInvoices() async {
    final rows = await _localDb.getAllBills();
    return rows.map((r) {
      return InvoiceModel(
        docId: r['docId'],
        companyDocId: r['companyDocId'],
        total: (r['total'] as num).toDouble(),
        date: r['date'],
        // retrieve lineItemsJson if present
        lineItemsJson: r['lineItemsJson'],
      );
    }).toList();
  }

  Future<void> createInvoice(InvoiceModel inv) async {
    await _localDb.insertOrUpdateBill(
      docId: inv.docId,
      companyDocId: inv.companyDocId,
      total: inv.total,
      date: inv.date,
      // now passing lineItemsJson for local DB storage
      lineItemsJson: inv.lineItemsJson,
    );
  }

  Future<void> updateInvoice(InvoiceModel inv) async {
    await _localDb.insertOrUpdateBill(
      docId: inv.docId,
      companyDocId: inv.companyDocId,
      total: inv.total,
      date: inv.date,
      // pass lineItemsJson so DB can store or update it
      lineItemsJson: inv.lineItemsJson,
    );
  }

  Future<void> deleteInvoice(String docId) async {
    await _localDb.deleteBill(docId);
  }
}
