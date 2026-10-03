import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:super_admin_app/models/received_donation_record.dart';
import 'package:super_admin_app/utils/donation_history_export.dart';
import 'package:super_admin_app/utils/xlsx_writer.dart';

DonationExportRow _row({
  DateTime? date,
  String donor = 'Juan Dela Cruz',
  String? email = 'juan@example.com',
  String center = 'Center A',
  String allocation = 'Specific Center',
  double amount = 100,
  bool manual = false,
}) {
  return DonationExportRow(
    date: date ?? DateTime(2026, 9, 1, 9, 30),
    donor: donor,
    donorEmail: email,
    center: center,
    allocation: allocation,
    amount: amount,
    isManualDistribution: manual,
  );
}

DonationExportRow _manual({double amount = 500, String center = 'Center A'}) =>
    _row(
      donor: 'Super Admin distribution',
      email: null,
      center: center,
      allocation: 'Manual Distribution',
      amount: amount,
      manual: true,
    );

DonationPdfAssets _assets() => DonationPdfAssets(
      regular: pw.Font.ttf(
        ByteData.sublistView(
          File('assets/fonts/Montserrat-Regular.ttf').readAsBytesSync(),
        ),
      ),
      bold: pw.Font.ttf(
        ByteData.sublistView(
          File('assets/fonts/Montserrat-Bold.ttf').readAsBytesSync(),
        ),
      ),
      logo: pw.MemoryImage(
        File('assets/images/CureNurture_CircleLogo.png').readAsBytesSync(),
      ),
    );

/// Writes a generated file for manual/external inspection when
/// EXPORT_SAMPLE_DIR is set; a no-op otherwise.
void _sample(String name, Uint8List bytes) {
  final dir = Platform.environment['EXPORT_SAMPLE_DIR'];
  if (dir == null || dir.isEmpty) return;
  File('$dir/$name').writeAsBytesSync(bytes);
}

String _sheetXml(Uint8List xlsx) {
  final archive = ZipDecoder().decodeBytes(xlsx);
  final file = archive.findFile('xl/worksheets/sheet1.xml')!;
  return utf8.decode(file.content as List<int>);
}

void main() {
  group('ReceivedDonationRecord', () {
    ReceivedDonationRecord record({
      ReceivedDonationSource source = ReceivedDonationSource.direct,
      String? allocationType = 'specific_center',
      String? name = 'Ana',
      bool anonymous = false,
    }) =>
        ReceivedDonationRecord(
          sourceId: 'x',
          source: source,
          date: DateTime(2026),
          amount: 1,
          centerName: 'Center A',
          allocationType: allocationType,
          donorName: name,
          donorEmail: 'ana@example.com',
          isAnonymous: anonymous,
        );

    test('allocation labels follow the source', () {
      expect(record().allocationLabel, 'Specific Center');
      expect(record(allocationType: 'random_center').allocationLabel, 'Random');
      expect(record(allocationType: null).allocationLabel, 'Not recorded');
      expect(
        record(source: ReceivedDonationSource.equalShare).allocationLabel,
        'Equal Share',
      );
      expect(
        record(source: ReceivedDonationSource.manualDistribution)
            .allocationLabel,
        'Manual Distribution',
      );
    });

    test('anonymous donors never expose a name or email', () {
      final anon = record(anonymous: true);
      expect(anon.donorLabel, 'Anonymous');
      final row = DonationExportRow.fromReceived(anon);
      expect(row.donor, 'Anonymous');
      expect(row.donorEmail, isNull);
    });

    test('manual distributions are labelled and flagged', () {
      final row = DonationExportRow.fromReceived(
        record(source: ReceivedDonationSource.manualDistribution, name: null),
      );
      expect(row.donor, 'Super Admin distribution');
      expect(row.isManualDistribution, isTrue);
    });
  });

  group('file names', () {
    test('All Centers', () {
      final report = DonationHistoryReport(
        scopeLabel: 'All Centers',
        isAllCenters: true,
        rows: [_row()],
      );
      expect(
        report.fileName(DonationExportFormat.pdf),
        'CureNurture_Donation_History_All_Centers.pdf',
      );
      expect(
        report.fileName(DonationExportFormat.excel),
        'CureNurture_Donation_History_All_Centers.xlsx',
      );
    });

    test('specific center names are made file-safe', () {
      String name(String center) => DonationHistoryReport(
            scopeLabel: center,
            isAllCenters: false,
            rows: [_row()],
          ).fileName(DonationExportFormat.pdf);

      expect(
        name('St. Luke\'s Dialysis Center – Parañaque / Unit #2'),
        'CureNurture_Donation_History_St_Lukes_Dialysis_Center_Paranaque_Unit_2.pdf',
      );
      expect(name('  ***  '), 'CureNurture_Donation_History_Center.pdf');
      expect(name(r'a<b>c:d"e|f?g*h\i'), 'CureNurture_Donation_History_a_b_c_d_e_f_g_h_i.pdf');
    });

    test('long center names are capped', () {
      final slug = DonationHistoryReport.safeFileSegment('Very Long Name ' * 20);
      expect(slug.length, lessThanOrEqualTo(60));
      expect(slug.endsWith('_'), isFalse);
    });
  });

  group('totals', () {
    test('total = donor donations + manual distributions (dashboard formula)',
        () {
      final report = DonationHistoryReport(
        scopeLabel: 'Center A',
        isAllCenters: false,
        rows: [
          _row(amount: 100.10),
          _row(amount: 200.20, allocation: 'Equal Share'),
          _manual(amount: 50),
          _manual(amount: 25.25),
        ],
      );

      expect(report.count, 4);
      expect(report.totalAmount, 375.55);
      expect(report.donorCount, 2);
      expect(report.donorAmount, 300.30);
      expect(report.manualCount, 2);
      expect(report.manualAmount, 75.25);
    });

    test('many small amounts do not drift', () {
      final report = DonationHistoryReport(
        scopeLabel: 'X',
        isAllCenters: false,
        rows: [for (var i = 0; i < 1000; i++) _row(amount: 0.1)],
      );
      expect(report.totalAmount, 100.0);
    });
  });

  group('empty data', () {
    final empty = DonationHistoryReport(
      scopeLabel: 'Center A',
      isAllCenters: false,
      rows: const [],
    );

    test('Excel refuses an empty report', () {
      expect(
        () => DonationHistoryExporter.buildXlsx(empty),
        throwsArgumentError,
      );
    });

    test('PDF refuses an empty report', () async {
      await expectLater(
        DonationHistoryExporter.buildPdf(empty, assets: _assets()),
        throwsArgumentError,
      );
    });
  });

  group('Excel', () {
    test('no ID or status columns; real dates and amounts; frozen header', () {
      final report = DonationHistoryReport(
        scopeLabel: 'Center <A> & "B"',
        isAllCenters: false,
        rows: [
          _row(amount: 1500.5, date: DateTime(2026, 9, 25, 14, 5)),
          _row(donor: 'Anonymous', email: null, amount: 250),
          _manual(amount: 75),
        ],
        filters: const ['Date range: Last 30 Days'],
        generatedAt: DateTime(2026, 9, 30, 10),
      );

      final bytes = DonationHistoryExporter.buildXlsx(report);
      _sample('center_small.xlsx', bytes);
      final xml = _sheetXml(bytes);

      expect(xml, contains('<pane ySplit="7" topLeftCell="A8"'));
      expect(xml.contains('Donation ID'), isFalse);
      expect(xml.contains('>Status<'), isFalse);
      // No Pending/Rejected cells (the note may mention them as excluded).
      expect(xml.contains('>Pending<'), isFalse);
      expect(xml.contains('>Rejected<'), isFalse);
      expect(xml, contains('Center - Center &lt;A&gt; &amp; &quot;B&quot;'));
      // Date in A, amount in F, both real numbers.
      final serial = XlsxWriter.excelSerial(DateTime(2026, 9, 25, 14, 5));
      expect(xml, contains('<c r="A8" s="${XlsxStyle.dateTime.index}"><v>$serial</v></c>'));
      expect(xml, contains('<c r="F8" s="${XlsxStyle.currency.index}"><v>1500.5</v></c>'));
      expect(xml.contains('<c r="G8"'), isFalse);
      expect(xml, contains('SUM(F8:F10)'));
      expect(xml, contains('SUMIF(E8:E10,&quot;Manual Distribution&quot;,F8:F10)'));
    });

    test('excelSerial matches Excel for a known date', () {
      expect(XlsxWriter.excelSerial(DateTime(2026, 1, 1)), 46023);
      expect(XlsxWriter.excelSerial(DateTime(2026, 1, 1, 12)), 46023.5);
    });

    test('column letters', () {
      expect(XlsxWriter.columnLetter(0), 'A');
      expect(XlsxWriter.columnLetter(5), 'F');
      expect(XlsxWriter.columnLetter(25), 'Z');
      expect(XlsxWriter.columnLetter(26), 'AA');
    });

    test('control characters in user text cannot corrupt the file', () {
      final report = DonationHistoryReport(
        scopeLabel: 'All Centers',
        isAllCenters: true,
        rows: [_row(donor: 'Bad\u0001Name\u0008')],
      );
      final xml = _sheetXml(DonationHistoryExporter.buildXlsx(report));
      expect(xml, contains('BadName'));
      expect(xml.contains('\u0001'), isFalse);
    });
  });

  group('PDF', () {
    test('single donation, anonymous donor', () async {
      final bytes = await DonationHistoryExporter.buildPdf(
        DonationHistoryReport(
          scopeLabel: 'All Centers',
          isAllCenters: true,
          rows: [_row(donor: 'Anonymous', email: null)],
          generatedAt: DateTime(2026, 9, 30, 10),
        ),
        assets: _assets(),
      );
      _sample('all_single.pdf', bytes);
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('All Centers: per-center shares and manual distributions', () async {
      final report = DonationHistoryReport(
        scopeLabel: 'All Centers',
        isAllCenters: true,
        generatedAt: DateTime(2026, 9, 30, 10),
        rows: [
          _row(center: 'Center A', amount: 500),
          _row(center: 'Center B', amount: 1200, allocation: 'Random'),
          // One 3,000 equal-distribution donation -> one share per center.
          for (final c in ['Center A', 'Center B', 'Center C'])
            _row(
              center: c,
              allocation: 'Equal Share',
              amount: 1000,
              donor: 'Anonymous',
              email: null,
            ),
          _manual(center: 'Center C', amount: 80),
        ],
      );

      final pdf = await DonationHistoryExporter.buildPdf(report, assets: _assets());
      _sample('all_multi.pdf', pdf);
      final xlsx = DonationHistoryExporter.buildXlsx(report);
      _sample('all_multi.xlsx', xlsx);

      final xml = _sheetXml(xlsx);
      for (final center in ['Center A', 'Center B', 'Center C']) {
        expect(xml, contains('>$center<'));
      }
      expect(report.totalAmount, 4780);
      expect(report.donorAmount, 4700);
      expect(report.manualAmount, 80);
    });

    test('many records and long text span pages without failing', () async {
      final longCenter =
          'Our Lady of Perpetual Help Medical Center Dialysis and Renal '
          'Care Unit – Parañaque City Extension Building';
      final rows = [
        for (var i = 0; i < 1200; i++)
          i % 9 == 0
              ? _manual(center: longCenter, amount: 2000)
              : _row(
                  date: DateTime(2026, 1, 1).add(Duration(hours: i * 5)),
                  donor: i.isEven
                      ? 'María José Dela Cruz-Santos y Magsaysay Ñiño III'
                      : 'Anonymous',
                  email:
                      i.isEven ? 'maria.jose.delacruz.santos@example.com' : null,
                  center: longCenter,
                  allocation: i % 3 == 0 ? 'Equal Share' : 'Specific Center',
                  amount: 1000 + i * 0.25,
                ),
      ];

      final report = DonationHistoryReport(
        scopeLabel: longCenter,
        isAllCenters: false,
        rows: rows,
        filters: const ['Date range: This Year', 'Search: "dela"'],
        generatedAt: DateTime(2026, 9, 30, 10),
      );

      final pdf = await DonationHistoryExporter.buildPdf(report, assets: _assets());
      _sample('center_large.pdf', pdf);
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');

      final xlsx = DonationHistoryExporter.buildXlsx(report);
      _sample('center_large.xlsx', xlsx);
      expect(_sheetXml(xlsx), contains('<c r="A1207"'));
    });
  });
}
