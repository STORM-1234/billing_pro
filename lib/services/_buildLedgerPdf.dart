// lib/services/buildLedgerPdf.dart

import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Data class for a ledger row
class LedgerRow {
  final DateTime date;
  final String particulars; // e.g., "By cash Sales", "By credit Sales", "By payment"
  final String type;        // e.g., "Sales Invoice", "Receipt"
  final String referenceNo; // the user-facing invoiceNumber or receiptNumber
  final double amount;
  final double debit;
  final double credit;

  LedgerRow({
    required this.date,
    required this.particulars,
    required this.type,
    required this.referenceNo,
    required this.amount,
    required this.debit,
    required this.credit,
  });
}

/// Build the Ledger PDF
Future<Uint8List> buildLedgerPdf({
  required String companyName,
  required DateTime startDate,
  required DateTime endDate,
  required double openingBalance,
  required List<LedgerRow> ledgerRows,
}) async {
  final pdf = pw.Document();
  const maxLinesPerPage = 25;

  // Sort by date ascending
  ledgerRows.sort((a, b) => a.date.compareTo(b.date));

  final pagesData = <List<LedgerRow>>[];
  for (int i = 0; i < ledgerRows.length; i += maxLinesPerPage) {
    final endIndex = (i + maxLinesPerPage < ledgerRows.length)
        ? i + maxLinesPerPage
        : ledgerRows.length;
    pagesData.add(ledgerRows.sublist(i, endIndex));
  }
  if (pagesData.isEmpty) {
    pagesData.add([]);
  }

  double runningBalance = openingBalance;

  for (int pageIndex = 0; pageIndex < pagesData.length; pageIndex++) {
    final chunk = pagesData[pageIndex];
    final isLastPage = (pageIndex == pagesData.length - 1);

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(16),
        build: (context) {
          return [
            _buildLedgerHeader(
              companyName: companyName,
              startDate: startDate,
              endDate: endDate,
            ),
            pw.SizedBox(height: 5),
            _buildCurrentDateLine(),
            pw.SizedBox(height: 10),

            _buildLedgerTable(
              chunk: chunk,
              pageIndex: pageIndex + 1,
              totalPages: pagesData.length,
              runningBalance: runningBalance,
              isLastPage: isLastPage,
              openingBalance: openingBalance,
            ),
          ];
        },
      ),
    );

    for (final row in chunk) {
      runningBalance = runningBalance + row.debit - row.credit;
    }
  }

  return pdf.save();
}

/// Header
pw.Widget _buildLedgerHeader({
  required String companyName,
  required DateTime startDate,
  required DateTime endDate,
}) {
  final dateFmt = DateFormat("dd-MMM-yyyy");
  final periodLine =
      "In report period: ${dateFmt.format(startDate)} 00:00:00 AM To ${dateFmt.format(endDate)} 11:59:59 PM";

  return pw.Column(
    children: [
      pw.Center(
        child: pw.Text(
          "Ledger Report",
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Center(
        child: pw.Text(
          companyName,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.Center(
        child: pw.Text(
          periodLine,
          style: pw.TextStyle(
            fontSize: 12,
            decoration: pw.TextDecoration.underline,
          ),
        ),
      ),
    ],
  );
}

/// Show today's date
pw.Widget _buildCurrentDateLine() {
  final now = DateTime.now();
  final dateStr = DateFormat("dd-MMM-yyyy").format(now);

  return pw.Align(
    alignment: pw.Alignment.centerLeft,
    child: pw.Text(dateStr, style: const pw.TextStyle(fontSize: 10)),
  );
}

/// Ledger table
pw.Widget _buildLedgerTable({
  required List<LedgerRow> chunk,
  required int pageIndex,
  required int totalPages,
  required double runningBalance,
  required bool isLastPage,
  required double openingBalance,
}) {
  final dateFmt = DateFormat("dd-MMM-yyyy");
  int itemNo = 1;

  final tableRows = <pw.TableRow>[];

  // Header row
  tableRows.add(
    pw.TableRow(
      decoration: pw.BoxDecoration(
        color: PdfColors.grey300,
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 1),
        ),
      ),
      children: [
        _tableHeaderCell("No"),
        _tableHeaderCell("Bill Date"),
        _tableHeaderCell("Particulars"),
        _tableHeaderCell("Type"),
        _tableHeaderCell("Invoice/Receipt No"),
        _tableHeaderCell("Amount"),
        _tableHeaderCell("Debit"),
        _tableHeaderCell("Credit"),
        _tableHeaderCell("Balance"),
      ],
    ),
  );

  // Opening Balance row
  tableRows.add(
    pw.TableRow(
      children: [
        _tableCell(""),
        _tableCell(""),
        _tableCell("Opening Balance", bold: true),
        _tableCell(""),
        _tableCell(""),
        _tableCell(""),
        _tableCell(""),
        _tableCell(""),
        _tableCell(openingBalance.toStringAsFixed(3), bold: true),
      ],
    ),
  );

  // Transactions
  double currentBalance = runningBalance;
  for (final row in chunk) {
    currentBalance = currentBalance + row.debit - row.credit;

    tableRows.add(
      pw.TableRow(
        children: [
          _tableCell(itemNo.toString()),
          _tableCell(dateFmt.format(row.date)),
          _tableCell(row.particulars),
          _tableCell(row.type),
          _tableCell(row.referenceNo),
          _tableCell(row.amount.toStringAsFixed(3)),
          _tableCell(row.debit == 0 ? "" : row.debit.toStringAsFixed(3)),
          _tableCell(row.credit == 0 ? "" : row.credit.toStringAsFixed(3)),
          _tableCell(currentBalance.toStringAsFixed(3)),
        ],
      ),
    );
    itemNo++;
  }

  // Ending Balance if last page
  if (isLastPage) {
    tableRows.add(
      pw.TableRow(
        children: [
          _tableCell(""),
          _tableCell(""),
          _tableCell("Ending Balance", bold: true),
          _tableCell(""),
          _tableCell(""),
          _tableCell(""),
          _tableCell(""),
          _tableCell(""),
          _tableCell(currentBalance.toStringAsFixed(3), bold: true),
        ],
      ),
    );
  }

  // Page indicator
  final pageIndicator = pw.Text(
    "Page $pageIndex of $totalPages",
    style: const pw.TextStyle(fontSize: 10),
  );

  return pw.Column(
    children: [
      pw.Table(
        border: pw.TableBorder(
          left: pw.BorderSide.none,
          right: pw.BorderSide.none,
          top: pw.BorderSide.none,
          bottom: pw.BorderSide.none,
          horizontalInside: pw.BorderSide.none,
          verticalInside: pw.BorderSide.none,
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(2.4),
          2: const pw.FlexColumnWidth(3),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(2),
          5: const pw.FlexColumnWidth(2),
          6: const pw.FlexColumnWidth(2),
          7: const pw.FlexColumnWidth(2),
          8: const pw.FlexColumnWidth(2),
        },
        children: tableRows,
      ),
      pw.SizedBox(height: 5),
      pw.Align(alignment: pw.Alignment.centerRight, child: pageIndicator),
    ],
  );
}

pw.Widget _tableHeaderCell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
    ),
  );
}

pw.Widget _tableCell(String text, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
