import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/received_donation_record.dart';
import 'xlsx_writer.dart';

/// The two download formats offered on the Super Admin Donations page.
enum DonationExportFormat {
  pdf('Download PDF', 'pdf', 'application/pdf'),
  excel('Download Excel', 'xlsx', XlsxWriter.mimeType);

  const DonationExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

/// One exported line: an amount a center actually received, as counted by
/// the Admin Dashboard's "Donation Funds" total. Only received records are
/// exported, so there is no status column and no donation ID.
class DonationExportRow {
  final DateTime date;

  /// Already privacy-resolved ("Anonymous" when the donor chose it).
  final String donor;

  /// Never present for anonymous donations or manual distributions.
  final String? donorEmail;
  final String center;
  final String allocation;
  final double amount;

  /// A Super Admin fund_distributions entry rather than a donor's donation.
  final bool isManualDistribution;

  const DonationExportRow({
    required this.date,
    required this.donor,
    required this.center,
    required this.allocation,
    required this.amount,
    this.donorEmail,
    this.isManualDistribution = false,
  });

  factory DonationExportRow.fromReceived(ReceivedDonationRecord record) {
    return DonationExportRow(
      date: record.date,
      donor: record.donorLabel,
      donorEmail: record.isAnonymous ? null : record.donorEmail,
      center: record.centerName,
      allocation: record.allocationLabel,
      amount: record.amount,
      isManualDistribution: record.isManualDistribution,
    );
  }
}

/// Everything one exported file contains: what it covers, which filters
/// were active, and the rows.
class DonationHistoryReport {
  static const String brand = 'CureNurture';
  static const String title = 'Donation History';

  /// "All Centers" or the selected center's name.
  final String scopeLabel;
  final bool isAllCenters;

  /// Human-readable active filters, e.g. `Date range: Last 30 Days`. Empty
  /// when the full history for the scope is exported.
  final List<String> filters;
  final List<DonationExportRow> rows;
  final DateTime generatedAt;

  DonationHistoryReport({
    required this.scopeLabel,
    required this.isAllCenters,
    required this.rows,
    this.filters = const [],
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  int get count => rows.length;

  /// Total received -- with no filters this equals the Admin Dashboard's
  /// "Donation Funds" total for the center (or the sum across centers).
  double get totalAmount => _sum(rows);

  int get donorCount => rows.where((r) => !r.isManualDistribution).length;
  double get donorAmount => _sum(rows.where((r) => !r.isManualDistribution));
  int get manualCount => rows.where((r) => r.isManualDistribution).length;
  double get manualAmount => _sum(rows.where((r) => r.isManualDistribution));

  /// Explains what the amounts are, so the file reads the same way as the
  /// Admin Dashboard it matches.
  String get amountNote => isAllCenters
      ? 'Received donations only (verified), listed per center exactly as '
          'each center\'s Admin Dashboard counts them: donations sent to the '
          'center, the center\'s share of equal-distribution donations, and '
          'Super Admin manual distributions. Pending and rejected donations '
          'are not included.'
      : 'Received donations only (verified), matching $scopeLabel\'s Admin '
          'Dashboard "Donation Funds": donations sent to this center, its '
          'share of equal-distribution donations, and Super Admin manual '
          'distributions. Pending and rejected donations are not included.';

  String get filtersText =>
      filters.isEmpty ? 'None (full history)' : filters.join('  ·  ');

  static double _sum(Iterable<DonationExportRow> rows) {
    // Summed in whole centavos so long lists do not drift from float error.
    var centavos = 0;
    for (final row in rows) {
      centavos += (row.amount * 100).round();
    }
    return centavos / 100;
  }

  /// `CureNurture_Donation_History_All_Centers.pdf` or
  /// `CureNurture_Donation_History_<Center_Name>.xlsx`.
  String fileName(DonationExportFormat format) {
    final scope = isAllCenters ? 'All_Centers' : safeFileSegment(scopeLabel);
    return '${brand}_Donation_History_$scope.${format.extension}';
  }

  /// Turns a center name into something every OS and browser accepts as
  /// part of a file name: accents folded to plain letters, apostrophes
  /// dropped, every other run of non-alphanumerics collapsed to one "_",
  /// and capped so a very long name cannot produce an unwieldy file name.
  static String safeFileSegment(String name, {int maxLength = 60}) {
    const folds = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ñ': 'n', 'ç': 'c',
      'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
      'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
      'Ñ': 'N', 'Ç': 'C',
    };

    final folded = name.split('').map((ch) => folds[ch] ?? ch).join();
    var slug = folded
        .replaceAll(RegExp("['’`]"), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (slug.length > maxLength) {
      slug = slug.substring(0, maxLength).replaceAll(RegExp(r'_+$'), '');
    }

    return slug.isEmpty ? 'Center' : slug;
  }
}

/// Fonts and logo embedded in the PDF. Montserrat is used because the PDF
/// standard fonts cannot draw "₱" or many accented donor names.
class DonationPdfAssets {
  final pw.Font regular;
  final pw.Font bold;
  final pw.ImageProvider? logo;

  const DonationPdfAssets({
    required this.regular,
    required this.bold,
    this.logo,
  });

  static Future<DonationPdfAssets> load() async {
    final regular = await rootBundle.load('assets/fonts/Montserrat-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Montserrat-Bold.ttf');

    pw.ImageProvider? logo;
    try {
      final bytes = await rootBundle.load(
        'assets/images/CureNurture_CircleLogo.png',
      );
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      // Branding only -- the report is still complete without the logo.
      logo = null;
    }

    return DonationPdfAssets(
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      logo: logo,
    );
  }
}

/// Builds the downloadable files for a [DonationHistoryReport].
class DonationHistoryExporter {
  const DonationHistoryExporter._();

  static final NumberFormat _money = NumberFormat('#,##0.00', 'en_US');
  static final DateFormat _dateTime = DateFormat('MMM d, yyyy h:mm a', 'en_US');
  static final DateFormat _date = DateFormat('MMM d, yyyy', 'en_US');
  static final DateFormat _time = DateFormat('h:mm a', 'en_US');

  static String peso(double amount) => '₱${_money.format(amount)}';

  // ---------------------------------------------------------------- PDF --

  static const PdfColor _brand = PdfColor.fromInt(0xFF2A5F7E);
  static const PdfColor _brandDark = PdfColor.fromInt(0xFF17435C);
  static const PdfColor _text = PdfColor.fromInt(0xFF1F2D3D);
  static const PdfColor _muted = PdfColor.fromInt(0xFF647583);
  static const PdfColor _border = PdfColor.fromInt(0xFFD6E0E8);
  static const PdfColor _zebra = PdfColor.fromInt(0xFFF4F8FA);
  static const PdfColor _soft = PdfColor.fromInt(0xFFEDF3F8);
  static const PdfColor _received = PdfColor.fromInt(0xFF2E7D32);

  /// Enough headroom for tens of thousands of rows; the pdf package's
  /// default of 20 pages would make any large history fail outright.
  static const int _maxPages = 5000;

  static Future<Uint8List> buildPdf(
    DonationHistoryReport report, {
    DonationPdfAssets? assets,
  }) async {
    if (report.rows.isEmpty) {
      throw ArgumentError('A donation history export needs at least one row.');
    }

    final a = assets ?? await DonationPdfAssets.load();

    final doc = pw.Document(
      title: '${DonationHistoryReport.brand} ${DonationHistoryReport.title} '
          '- ${report.scopeLabel}',
      author: DonationHistoryReport.brand,
      creator: '${DonationHistoryReport.brand} Super Admin',
      theme: pw.ThemeData.withFont(
        base: a.regular,
        bold: a.bold,
        // No Montserrat italics are bundled; mapping these keeps any
        // italic/bold-italic text on a font that can draw every character.
        italic: a.regular,
        boldItalic: a.bold,
      ),
    );

    doc.addPage(
      pw.MultiPage(
        maxPages: _maxPages,
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        ),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _pdfRunningHeader(report),
        footer: (context) => _pdfFooter(report, context),
        build: (context) => [
          _pdfTitleBlock(report, a.logo),
          pw.SizedBox(height: 12),
          _pdfSummary(report),
          pw.SizedBox(height: 8),
          pw.Text(
            report.amountNote,
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.SizedBox(height: 10),
          _pdfTable(report),
          pw.SizedBox(height: 10),
          _pdfTotals(report),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfTitleBlock(
    DonationHistoryReport report,
    pw.ImageProvider? logo,
  ) {
    pw.Widget meta(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: '$label  ',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandDark,
                ),
              ),
              pw.TextSpan(
                text: value,
                style: const pw.TextStyle(fontSize: 9, color: _text),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.SizedBox(width: 46, height: 46, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  DonationHistoryReport.brand.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: pw.FontWeight.bold,
                    color: _brand,
                  ),
                ),
                pw.Text(
                  DonationHistoryReport.title,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: _brandDark,
                  ),
                ),
                pw.SizedBox(height: 4),
                meta(
                  'Scope:',
                  report.isAllCenters
                      ? 'All Centers'
                      : 'Center - ${report.scopeLabel}',
                ),
                meta('Generated:', _dateTime.format(report.generatedAt)),
                meta('Filters:', report.filtersText),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfSummary(DonationHistoryReport report) {
    pw.Widget box(String label, String value, String? sub, PdfColor accent) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          // Square corners on purpose: the pdf package only allows a
          // borderRadius on a uniform border, and this one is left-only.
          decoration: pw.BoxDecoration(
            color: _soft,
            border: pw.Border(left: pw.BorderSide(color: accent, width: 3)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 7,
                  letterSpacing: 0.6,
                  fontWeight: pw.FontWeight.bold,
                  color: _muted,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _brandDark,
                ),
              ),
              if (sub != null)
                pw.Text(
                  sub,
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                ),
            ],
          ),
        ),
      );
    }

    String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

    return pw.Row(
      children: [
        box('Total received', peso(report.totalAmount),
            plural(report.count, 'record'), _received),
        pw.SizedBox(width: 8),
        box('From donors', peso(report.donorAmount),
            plural(report.donorCount, 'donation'), _brand),
        pw.SizedBox(width: 8),
        box('Manual distributions', peso(report.manualAmount),
            plural(report.manualCount, 'distribution'), _brand),
      ],
    );
  }

  /// PDF table columns as (header, flex width, right-aligned). The Center
  /// column is only included for "All Centers": in a single-center report
  /// every row is that center, which the title and running header already
  /// state, and dropping it roughly doubles the rows that fit on a page.
  static List<(String, double, bool)> _pdfColumns(bool showCenter) => [
        ('Date', 1.0, false),
        ('Donor', 2.3, false),
        if (showCenter) ('Center', 2.1, false),
        ('Allocation', 1.3, false),
        ('Amount', 1.1, true),
      ];

  static pw.Widget _cell(
    String text, {
    pw.TextStyle? style,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: style ?? const pw.TextStyle(fontSize: 8, color: _text),
      ),
    );
  }

  static pw.Widget _pdfTable(DonationHistoryReport report) {
    final headerStyle = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );

    final showCenter = report.isAllCenters;
    final columns = _pdfColumns(showCenter);

    return pw.Table(
      columnWidths: {
        for (var i = 0; i < columns.length; i++)
          i: pw.FlexColumnWidth(columns[i].$2),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _border, width: 0.5),
        bottom: pw.BorderSide(color: _border, width: 0.5),
      ),
      children: [
        // repeat: true -> redrawn at the top of every continuation page.
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _brand),
          children: [
            for (final (label, _, alignRight) in columns)
              _cell(
                label,
                style: headerStyle,
                align: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
              ),
          ],
        ),
        for (var i = 0; i < report.rows.length; i++)
          _pdfRow(report.rows[i], zebra: i.isOdd, showCenter: showCenter),
      ],
    );
  }

  static pw.TableRow _pdfRow(
    DonationExportRow row, {
    required bool zebra,
    required bool showCenter,
  }) {
    final local = row.date.toLocal();
    final email = row.donorEmail;

    return pw.TableRow(
      decoration: zebra ? const pw.BoxDecoration(color: _zebra) : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _date.format(local),
                style: const pw.TextStyle(fontSize: 8, color: _text),
              ),
              pw.Text(
                _time.format(local),
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                row.donor,
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _text,
                ),
              ),
              if (email != null && email.isNotEmpty)
                pw.Text(
                  email,
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
            ],
          ),
        ),
        if (showCenter) _cell(row.center),
        _cell(row.allocation),
        _cell(
          peso(row.amount),
          align: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _brandDark,
          ),
        ),
      ],
    );
  }

  static pw.Widget _pdfTotals(DonationHistoryReport report) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _soft,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Received records: ${report.count}   ·   '
              'From donors: ${peso(report.donorAmount)}   ·   '
              'Manual distributions: ${peso(report.manualAmount)}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _brandDark,
              ),
            ),
          ),
          pw.Text(
            'Total received: ${peso(report.totalAmount)}',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _brandDark,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfRunningHeader(DonationHistoryReport report) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${DonationHistoryReport.brand} ${DonationHistoryReport.title}'
              '  ·  ${report.scopeLabel}',
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _brandDark,
              ),
            ),
          ),
          pw.Text(
            'Generated ${_dateTime.format(report.generatedAt)}',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfFooter(
    DonationHistoryReport report,
    pw.Context context,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${DonationHistoryReport.brand} Super Admin  ·  '
              'Contains donor details -- handle according to donor privacy rules.',
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- EXCEL --

  static const List<String> _excelHeaders = [
    'Date',
    'Donor',
    'Donor Email',
    'Center',
    'Allocation',
    'Amount',
  ];

  /// 1-based sheet row that holds the column headers.
  static const int excelHeaderRow = 7;

  static Uint8List buildXlsx(DonationHistoryReport report) {
    if (report.rows.isEmpty) {
      throw ArgumentError('A donation history export needs at least one row.');
    }

    final rows = <List<XlsxCell?>?>[
      [
        XlsxCell(
          '${DonationHistoryReport.brand} ${DonationHistoryReport.title}',
          style: XlsxStyle.title,
        ),
      ],
      [
        const XlsxCell('Scope', style: XlsxStyle.metaLabel),
        XlsxCell(
          report.isAllCenters
              ? 'All Centers'
              : 'Center - ${report.scopeLabel}',
          style: XlsxStyle.metaValue,
        ),
      ],
      [
        const XlsxCell('Generated', style: XlsxStyle.metaLabel),
        XlsxCell(report.generatedAt, style: XlsxStyle.metaDateTime),
      ],
      [
        const XlsxCell('Filters', style: XlsxStyle.metaLabel),
        XlsxCell(report.filtersText, style: XlsxStyle.metaValue),
      ],
      [XlsxCell(report.amountNote, style: XlsxStyle.note)],
      null,
      [
        for (final h in _excelHeaders) XlsxCell(h, style: XlsxStyle.header),
      ],
    ];

    for (final row in report.rows) {
      rows.add([
        XlsxCell(row.date.toLocal(), style: XlsxStyle.dateTime),
        XlsxCell(row.donor, style: XlsxStyle.text),
        XlsxCell(row.donorEmail ?? '', style: XlsxStyle.text),
        XlsxCell(row.center, style: XlsxStyle.text),
        XlsxCell(row.allocation, style: XlsxStyle.text),
        XlsxCell(row.amount, style: XlsxStyle.currency),
      ]);
    }

    final firstData = excelHeaderRow + 1;
    final lastData = excelHeaderRow + report.rows.length;
    final amountRange = 'F$firstData:F$lastData';
    final allocationRange = 'E$firstData:E$lastData';
    const manual = 'Manual Distribution';

    // The breakdown formulas match on the Allocation column's own labels, so
    // filtering or editing the sheet keeps them honest; the computed values
    // are stored as each formula's cached result.
    rows
      ..add(null)
      ..add(const [
        XlsxCell('Summary', style: XlsxStyle.header),
        XlsxCell('Amount', style: XlsxStyle.header),
        XlsxCell('Records', style: XlsxStyle.header),
      ])
      ..add([
        const XlsxCell('Total received', style: XlsxStyle.summaryLabel),
        XlsxCell(
          report.totalAmount,
          style: XlsxStyle.summaryCurrency,
          formula: 'SUM($amountRange)',
        ),
        XlsxCell(
          report.count,
          style: XlsxStyle.summaryNumber,
          formula: 'ROWS($amountRange)',
        ),
      ])
      ..add([
        const XlsxCell('From donors', style: XlsxStyle.summaryLabel),
        XlsxCell(
          report.donorAmount,
          style: XlsxStyle.summaryCurrency,
          formula: 'SUMIF($allocationRange,"<>$manual",$amountRange)',
        ),
        XlsxCell(
          report.donorCount,
          style: XlsxStyle.summaryNumber,
          formula: 'COUNTIF($allocationRange,"<>$manual")',
        ),
      ])
      ..add([
        const XlsxCell('Manual distributions', style: XlsxStyle.summaryLabel),
        XlsxCell(
          report.manualAmount,
          style: XlsxStyle.summaryCurrency,
          formula: 'SUMIF($allocationRange,"$manual",$amountRange)',
        ),
        XlsxCell(
          report.manualCount,
          style: XlsxStyle.summaryNumber,
          formula: 'COUNTIF($allocationRange,"$manual")',
        ),
      ]);

    final lastCol = XlsxWriter.columnLetter(_excelHeaders.length - 1);

    return XlsxWriter.build(
      XlsxSheet(
        name: 'Donation History',
        rows: rows,
        columnWidths: const [22, 30, 34, 38, 22, 18],
        frozenRows: excelHeaderRow,
        printTitleRow: excelHeaderRow,
        merges: ['A1:${lastCol}1', 'B2:${lastCol}2', 'B4:${lastCol}4', 'A5:${lastCol}5'],
        autoFilterRef: 'A$excelHeaderRow:$lastCol$lastData',
        // Row 5 holds the wrapped explanatory note.
        rowHeights: const {1: 26, 5: 48, excelHeaderRow: 20},
      ),
      title: '${DonationHistoryReport.brand} ${DonationHistoryReport.title} '
          '- ${report.scopeLabel}',
      created: report.generatedAt,
    );
  }
}
