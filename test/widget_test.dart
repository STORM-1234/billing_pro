import 'package:billing_pro/models/company.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Import your actual app & repos
import 'package:billing_pro/main.dart';
import 'package:billing_pro/database/local_db_helper.dart';
import 'package:billing_pro/services/prices_repository.dart';
import 'package:billing_pro/services/companies_repository.dart';
import 'package:billing_pro/services/invoices_repository.dart';
import 'package:billing_pro/services/receipts_repository.dart';

// If you have a "Company" or "InvoiceModel" class, import them here
// import 'package:billing_pro/models/company.dart';
// import 'package:billing_pro/models/invoice_model.dart';

////////////////////////////////////////////////////////////////////////////////
// A minimal fake for PricesRepository
////////////////////////////////////////////////////////////////////////////////
class FakePricesRepository extends PricesRepository {
  FakePricesRepository() : super(LocalDbHelper());

  @override
  Future<void> init() async {}
  @override
  Future<bool> isOnline() async => false;
  @override
  Future<List<Map<String, dynamic>>> loadLocalPrices() async => [];
  @override
  Future<void> pullFromCloud() async {}
  @override
  Future<void> createPrice(String docId, String itemName, double price) async {}
  @override
  Future<void> updatePrice(String docId, String newName, double newPrice) async {}
  @override
  Future<void> deletePrice(String docId) async {}
}

////////////////////////////////////////////////////////////////////////////////
// A minimal fake for ReceiptsRepository
////////////////////////////////////////////////////////////////////////////////
class FakeReceiptsRepository extends ReceiptsRepository {
  FakeReceiptsRepository() : super(LocalDbHelper());

  @override
  Future<List<ReceiptModel>> loadAllReceipts() async => [];
  @override
  Future<void> createReceipt(ReceiptModel rc) async {}
  @override
  Future<void> updateReceipt(ReceiptModel rc) async {}
  @override
  Future<void> deleteReceipt(String docId) async {}
}

////////////////////////////////////////////////////////////////////////////////
// A minimal fake for CompaniesRepository
// (IMPORTANT: match param names exactly with real repository: crNumber, vatNumber)
////////////////////////////////////////////////////////////////////////////////
class FakeCompaniesRepository extends CompaniesRepository {
  FakeCompaniesRepository() : super(LocalDbHelper());

  @override
  Future<void> init() async {}

  @override
  Future<bool> isOnline() async => false;

  @override
  Future<List<Company>> loadLocalCompanies() async => [];

  @override
  Future<void> pullFromCloud() async {}

  // Make sure these named params match the real signature:
  @override
  Future<void> createCompany({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,
    String? crNumber,   // <-- match real param name
    String? vatNumber,  // <-- match real param name
  }) async {}

  @override
  Future<void> addBillForCompany(String docId, double amount) async {}

  // Also match param names here:
  @override
  Future<void> updateCompanyDetails({
    required String docId,
    required String name,
    required String phone,
    String? address,
    String? description,
    String? crNumber,   // <-- match real param name
    String? vatNumber,  // <-- match real param name
  }) async {}

  @override
  Future<void> deleteCompany(String docId) async {}

  @override
  Future<void> syncAllUnsyncedCompanies() async {}
}

////////////////////////////////////////////////////////////////////////////////
// A minimal fake for InvoicesRepository
////////////////////////////////////////////////////////////////////////////////
class FakeInvoicesRepository extends InvoicesRepository {
  FakeInvoicesRepository() : super(LocalDbHelper());

  @override
  Future<List<InvoiceModel>> loadAllInvoices() async => [];
  @override
  Future<void> createInvoice(InvoiceModel inv) async {}
  @override
  Future<void> updateInvoice(InvoiceModel inv) async {}
  @override
  Future<void> deleteInvoice(String docId) async {}
}

////////////////////////////////////////////////////////////////////////////////
// The actual test
////////////////////////////////////////////////////////////////////////////////
void main() {
  testWidgets('Smoke test for MyApp', (WidgetTester tester) async {
    // 1) Create fake repos
    final fakePricesRepo = FakePricesRepository();
    final fakeCompaniesRepo = FakeCompaniesRepository();
    final fakeInvoicesRepo = FakeInvoicesRepository();
    final fakeReceiptRepo = FakeReceiptsRepository();

    // 2) Pump MyApp with all required arguments
    await tester.pumpWidget(
      MyApp(
        receiptsRepo: fakeReceiptRepo,
        pricesRepo: fakePricesRepo,
        companiesRepo: fakeCompaniesRepo,
        invoicesRepo: fakeInvoicesRepo, // If your MyApp needs this
      ),
    );

    // 3) Basic smoke test: verify something on screen
    // For example, if your home screen has some text:
    expect(find.text('No invoices. Tap + to create one.'), findsOneWidget);

    // 4) Optionally, tap a button if your UI has it
    // final addButton = find.byIcon(Icons.add);
    // expect(addButton, findsOneWidget);
    // await tester.tap(addButton);
    // await tester.pump();
    // expect(...some result...);

    // If your actual UI is different, adapt these lines to match it
  });
}
