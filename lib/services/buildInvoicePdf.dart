import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Adjust if your Invoice classes live elsewhere
import 'package:billing_pro/screens/invoices_page.dart';

/// 31 total rows per page => 1 header row + 30 data rows
const int MAX_LINES_PER_PAGE = 31;

Future<Uint8List> buildInvoicePdf(Invoice invoice) async {
  final pdf = pw.Document();

  // 1) Break items into pages, each can have up to 30 data rows (+1 for header).
  final pagesData = _paginateItems(invoice.items, MAX_LINES_PER_PAGE);

  // 2) A single itemNumber counter that we keep incrementing across pages
  int itemNumber = 1;

  // 3) For each chunk => create a page
  for (int i = 0; i < pagesData.length; i++) {
    final chunk = pagesData[i];
    final isLastPage = (i == pagesData.length - 1);

    // Render this page. The page will read & update our itemNumber variable.
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 10,
          marginRight: 10,
          marginTop: 10,
          marginBottom: 10,
        ),
        build: (context) {
          return _buildSinglePage(
            invoice: invoice,
            itemsForThisPage: chunk,
            pageIndex: i + 1,
            totalPages: pagesData.length,
            isLastPage: isLastPage,

            // We pass itemNumber by reference so the code can update it
            itemNumberRef: () => itemNumber,         // read
            incrementItemNumber: () => itemNumber++, // increment
          );
        },
      ),
    );
  }

  return pdf.save();
}

/// Splits the [items] into sub-lists, each with up to 30 data rows (1 row for header).
List<List<InvoiceItem>> _paginateItems(List<InvoiceItem> items, int maxLinesPerPage) {
  if (items.isEmpty) {
    return [[]]; // at least one page if no items
  }
  final maxDataRows = maxLinesPerPage - 1;
  final pages = <List<InvoiceItem>>[];

  for (int i = 0; i < items.length; i += maxDataRows) {
    final end = (i + maxDataRows < items.length) ? i + maxDataRows : items.length;
    pages.add(items.sublist(i, end));
  }
  return pages;
}

/// Builds a single page of the invoice. Each item row calls [incrementItemNumber()]
/// and prints the current [itemNumberRef()] to get continuous numbering.
pw.Widget _buildSinglePage({
  required Invoice invoice,
  required List<InvoiceItem> itemsForThisPage,
  required int pageIndex,
  required int totalPages,
  required bool isLastPage,

  // We'll store itemNumber in the parent's scope. We read & increment via callbacks.
  required int Function() itemNumberRef,
  required void Function() incrementItemNumber,
}) {
  const tableHeight = 552.0;
  final blankCount = (MAX_LINES_PER_PAGE - 1) - itemsForThisPage.length;

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.black, width: 1),
    ),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // The top row: CR/VAT left, name center, blank right
        _buildHeader3Columns(),

        pw.SizedBox(height: 4),
        pw.Divider(thickness: 1, height: 1),

        // "TAX INVOICE" center
        pw.Center(
          child: pw.Text(
            "TAX INVOICE",
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 4),

        // Invoice info
        _buildInvoiceInfo(invoice),
        pw.Divider(thickness: 1, height: 1),

        // Customer info
        _buildCustomerInfo(invoice),
        pw.SizedBox(height: 6),

        // Table area
        pw.Container(
          height: tableHeight,
          child: _buildSingleTable(
            items: itemsForThisPage,
            blankCount: blankCount,
            itemNumberRef: itemNumberRef,
            incrementItemNumber: incrementItemNumber,
          ),
        ),

        pw.SizedBox(height: 5),

        // If last page => totals & signature, else page number
        if (isLastPage)
          _buildTotalsAndSignature(invoice)
        else
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              "Page $pageIndex / $totalPages",
              style: pw.TextStyle(fontSize: 9),
            ),
          ),
      ],
    ),
  );
}

/// The single table => 1 header + up to 30 data, each row prints the current itemNumberRef()
/// and then increments itemNumber.
pw.Widget _buildSingleTable({
  required List<InvoiceItem> items,
  required int blankCount,

  // references to parent's itemNumber
  required int Function() itemNumberRef,
  required void Function() incrementItemNumber,
}) {
  return pw.LayoutBuilder(
    builder: (context, constraints) {
      final tableHeight = constraints?.biggest?.y ?? 552;
      final rowHeight = tableHeight / MAX_LINES_PER_PAGE;

      return pw.Table(
        border: pw.TableBorder(
          top: pw.BorderSide(color: PdfColors.black),
          left: pw.BorderSide(color: PdfColors.black),
          right: pw.BorderSide(color: PdfColors.black),
          bottom: pw.BorderSide(color: PdfColors.black),
          verticalInside: pw.BorderSide(color: PdfColors.black),
          horizontalInside: pw.BorderSide.none,
        ),
        columnWidths: {
          0: pw.FixedColumnWidth(20),
          1: pw.FlexColumnWidth(3.0),
          2: pw.FixedColumnWidth(30),
          3: pw.FixedColumnWidth(40),
          4: pw.FixedColumnWidth(40),
          5: pw.FixedColumnWidth(40),
          6: pw.FixedColumnWidth(45),
        },
        children: [
          // Header row
          pw.TableRow(
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 1),
              ),
            ),
            children: [
              _rowContainer(rowHeight, _headerCell("No")),
              _rowContainer(rowHeight, _headerCell("Name of Product")),
              _rowContainer(rowHeight, _headerCell("Qty")),
              _rowContainer(rowHeight, _headerCell("Rate")),
              _rowContainer(rowHeight, _headerCell("Gross")),
              _rowContainer(rowHeight, _headerCell("VAT5%")),
              _rowContainer(rowHeight, _headerCell("Total")),
            ],
          ),

          // Data rows
          for (final item in items)
            _buildDataRow(rowHeight, itemNumberRef, incrementItemNumber, item),

          // Blank rows
          for (int i = 0; i < blankCount; i++)
            _buildBlankRow(rowHeight),
        ],
      );
    },
  );
}

/// A single data row. We do:
/// 1) read itemNumber = itemNumberRef()
/// 2) print itemNumber
/// 3) incrementItemNumber()
pw.TableRow _buildDataRow(
    double rowHeight,
    int Function() itemNumberRef,
    void Function() incrementItemNumber,
    InvoiceItem item,
    ) {
  final itemIndex = itemNumberRef(); // read
  incrementItemNumber();             // then increment for the next row

  final gross = item.unitPrice * item.quantity;
  final vat = item.vatApplied ? gross * 0.05 : 0;
  final total = gross + vat;

  return pw.TableRow(
    children: [
      _rowContainer(rowHeight, _dataCell("$itemIndex")),                 // No
      _rowContainer(rowHeight, _dataCell(item.name)),                    // Name
      _rowContainer(rowHeight, _dataCell("${item.quantity}")),           // Qty
      _rowContainer(rowHeight, _dataCell(item.unitPrice.toStringAsFixed(3))), // Rate (FIXED)
      _rowContainer(rowHeight, _dataCell(gross.toStringAsFixed(3))),     // Gross
      _rowContainer(rowHeight, _dataCell(vat.toStringAsFixed(3))),       // VAT
      _rowContainer(rowHeight, _dataCell(total.toStringAsFixed(3))),     // Total
    ],
  );
}

/// One blank row
pw.TableRow _buildBlankRow(double rowHeight) {
  return pw.TableRow(
    children: [
      for (int i = 0; i < 7; i++)
        _rowContainer(rowHeight, _dataCell("")),
    ],
  );
}

/// Totals + "For Maraya..." on same line, then a gap, then "Authorized Signature"
pw.Widget _buildTotalsAndSignature(Invoice invoice) {
  double totalNet = 0, totalVat = 0;
  for (final item in invoice.items) {
    final gross = item.unitPrice * item.quantity;
    final vat = item.vatApplied ? gross * 0.05 : 0;
    totalNet += gross;
    totalVat += vat;
  }
  final grandTotal = totalNet + totalVat;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "For Maraya Wudam Trad.(Asso)",
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text("Total Taxable: ${totalNet.toStringAsFixed(3)}",
                  style: pw.TextStyle(fontSize: 10)),
              pw.Text("Vat: ${totalVat.toStringAsFixed(3)}",
                  style: pw.TextStyle(fontSize: 10)),
              pw.Text(
                "Grand Total: ${grandTotal.toStringAsFixed(3)}",
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 15),
      pw.Text("Authorized Signature:", style: pw.TextStyle(fontSize: 10)),
    ],
  );
}

/// Each row is forced to a fixed [height]
pw.Widget _rowContainer(double height, pw.Widget child) {
  return pw.Container(
    height: height,
    child: child,
  );
}

// Table header cell
pw.Widget _headerCell(String text) {
  return pw.Center(
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      textAlign: pw.TextAlign.center,
    ),
  );
}

// Normal data cell
pw.Widget _dataCell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 9),
    ),
  );
}

/// Build the top row => 3 columns => CR/VAT left, name center, blank right
pw.Widget _buildHeader3Columns() {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      // Column 1: CR NO & VAT pinned left
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("CR NO: 1047445", style: pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 2),
          pw.Text("VATIN: OM1100080013", style: pw.TextStyle(fontSize: 10)),
        ],
      ),

      // Middle: company name/address centered
      pw.Expanded(
        child: pw.Center(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                "Maraya Wudam Trad. (Asso)",
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "Crown Plastic",
                style: pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "P.O.Box: 263, P.C: 315, AL Suwaiq,\nSultanate Of Oman",
                style: pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "GSM: 99027101, 96556573, 91191204,\nWhatsapp 93006061, 99796409",
                style: pw.TextStyle(fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      ),

      // Right column: blank for spacing
      pw.SizedBox(width: 100),
    ],
  );
}

/// Invoice date & paymode
pw.Widget _buildInvoiceInfo(Invoice invoice) {
  final dateStr = _formatDate(invoice.date);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text("Invoice No: ${invoice.invoiceNumber}",
              style: pw.TextStyle(fontSize: 10)),
          pw.Text("Date: $dateStr", style: pw.TextStyle(fontSize: 10)),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        "Paymode: ${invoice.isCredit ? 'Credit' : 'Cash'}",
        style: pw.TextStyle(fontSize: 10),
      ),
    ],
  );
}

/// Customer info
pw.Widget _buildCustomerInfo(Invoice invoice) {
  final cName = invoice.companyName ?? "";
  final cAddr = invoice.companyAddress ?? "";
  final cCr = invoice.companyCr ?? "";
  final cVat = invoice.companyVat ?? "";

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        "Customer: $cName",
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        "Address: $cAddr",
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      if (cCr.isNotEmpty)
        pw.Text("CR No: $cCr", style: pw.TextStyle(fontSize: 10)),
      if (cVat.isNotEmpty)
        pw.Text("VAT No: $cVat", style: pw.TextStyle(fontSize: 10)),
    ],
  );
}

/// Format date as yyyy-MM-dd
/// Format date as "dd/Mon/yyyy" e.g., "15/Mar/2025"
String _formatDate(DateTime dt) {
  final months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final day = dt.day.toString().padLeft(2, '0');
  final monthName = months[dt.month - 1];
  final year = dt.year;
  return "$day-$monthName-$year";
}
