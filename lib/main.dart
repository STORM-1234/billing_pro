// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

// If using sqflite for Windows/macOS/Linux:
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:sqflite/sqflite.dart';

import 'firebase_options.dart';

// Import your local DB & repositories
import 'database/local_db_helper.dart';
import 'services/companies_repository.dart';
import 'services/prices_repository.dart';
import 'services/invoices_repository.dart';
import 'services/receipts_repository.dart';

// Import your screens
import 'screens/home_page.dart';
import 'screens/receipts_page.dart';
import 'screens/prices_page.dart';
import 'screens/company_page.dart';
import 'screens/invoices_page.dart';
import 'screens/ledger_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If on desktop (Windows/macOS/Linux):
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Create local DB
  final localDb = LocalDbHelper();
  await localDb.initDb();

  // Create repositories
  final pricesRepo = PricesRepository(localDb);
  await pricesRepo.init();

  final companiesRepo = CompaniesRepository(localDb);
  await companiesRepo.init();

  final invoicesRepo = InvoicesRepository(localDb);

  // Create your ReceiptsRepository
  final receiptsRepo = ReceiptsRepository(localDb);

  // Run the app
  runApp(MyApp(
    pricesRepo: pricesRepo,
    companiesRepo: companiesRepo,
    invoicesRepo: invoicesRepo,
    receiptsRepo: receiptsRepo,
  ));
}

class MyApp extends StatelessWidget {
  final PricesRepository pricesRepo;
  final CompaniesRepository companiesRepo;
  final InvoicesRepository invoicesRepo;
  final ReceiptsRepository receiptsRepo;

  const MyApp({
    Key? key,
    required this.pricesRepo,
    required this.companiesRepo,
    required this.invoicesRepo,
    required this.receiptsRepo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Billing Pro',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
      routes: {
        // Existing routes
        '/invoices': (context) => InvoicesPage(
          invoicesRepo: invoicesRepo,
          companiesRepo: companiesRepo,
          pricesRepo: pricesRepo,
        ),
        '/receipts': (context) => ReceiptsPage(
          receiptsRepo: receiptsRepo,
          companiesRepo: companiesRepo,
        ),
        '/prices': (context) => PricesPage(repo: pricesRepo),
        '/company': (context) => CompanyPage(repo: companiesRepo),

        // NEW: Add the ledger route
        '/ledger': (context) => LedgerPage(
          companiesRepo: companiesRepo,
          invoicesRepo: invoicesRepo,
          receiptsRepo: receiptsRepo,
        ),
      },
    );
  }
}
