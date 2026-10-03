import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A deliberately small .xlsx (Office Open XML) writer: one worksheet, a
/// fixed set of cell styles, real numbers/dates, formulas with cached values,
/// merged cells, column widths, a frozen header and an autofilter.
///
/// Why not an Excel package: the only thing this portal exports is one
/// report sheet, and the popular pure-Dart Excel packages either cannot
/// freeze panes or carry licensing terms. An .xlsx is just a zip of a few
/// XML parts, and `archive` (already pulled in by `pdf`) does the zipping.
///
/// Strings are written inline (`t="inlineStr"`), so there is no shared
/// string table to keep in sync.

/// The cell styles this writer knows. The order here IS the order of the
/// `cellXfs` records in [_stylesXml] -- a cell's `s` attribute is its
/// style's [index] -- so add new styles at the end of both.
enum XlsxStyle {
  normal,
  title,
  metaLabel,
  metaValue,
  metaDateTime,
  header,
  text,
  dateTime,
  currency,
  summaryLabel,
  summaryNumber,
  summaryCurrency,
  note,
}

class XlsxCell {
  /// A [String], [num] or [DateTime] (written as a real Excel date, using
  /// the DateTime's own wall-clock fields -- pass local time for local
  /// display). Null leaves the cell empty but still styled.
  final Object? value;
  final XlsxStyle style;

  /// Optional formula, without the leading "=". [value] is stored as its
  /// cached result so the sheet shows correct figures even in viewers that
  /// do not recalculate.
  final String? formula;

  const XlsxCell(this.value, {this.style = XlsxStyle.normal, this.formula});
}

class XlsxSheet {
  /// Worksheet tab name. Excel limits this to 31 characters and forbids
  /// `[]:*?/\`; [build] sanitises it.
  final String name;

  /// Rows from the top of the sheet; a null row or null cell is left empty.
  final List<List<XlsxCell?>?> rows;

  /// Column widths in Excel's character units, from column A.
  final List<double> columnWidths;

  /// Number of rows kept visible at the top while scrolling (0 = none).
  final int frozenRows;

  /// 1-based row repeated at the top of every printed page, if any.
  final int? printTitleRow;

  /// Ranges such as "A1:H1".
  final List<String> merges;

  /// Range such as "A6:H40" to put filter drop-downs on.
  final String? autoFilterRef;

  /// Per-row heights in points, keyed by 1-based row number.
  final Map<int, double> rowHeights;

  const XlsxSheet({
    required this.name,
    required this.rows,
    this.columnWidths = const [],
    this.frozenRows = 0,
    this.printTitleRow,
    this.merges = const [],
    this.autoFilterRef,
    this.rowHeights = const {},
  });
}

class XlsxWriter {
  const XlsxWriter._();

  static const String mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Excel cells hold at most this many characters.
  static const int _maxCellText = 32767;

  /// Encodes [sheet] as the bytes of a complete .xlsx file.
  static Uint8List build(
    XlsxSheet sheet, {
    String title = '',
    String creator = 'CureNurture',
    DateTime? created,
  }) {
    final sheetName = safeSheetName(sheet.name);
    final parts = <String, String>{
      '[Content_Types].xml': _contentTypesXml,
      '_rels/.rels': _rootRelsXml,
      'docProps/core.xml': _coreXml(title, creator, created ?? DateTime.now()),
      'xl/workbook.xml': _workbookXml(sheet, sheetName),
      'xl/_rels/workbook.xml.rels': _workbookRelsXml,
      'xl/styles.xml': _stylesXml,
      'xl/worksheets/sheet1.xml': _sheetXml(sheet),
    };

    final archive = Archive();
    parts.forEach((path, xml) {
      archive.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));
    });

    return ZipEncoder().encodeBytes(archive);
  }

  /// 0 -> "A", 25 -> "Z", 26 -> "AA".
  static String columnLetter(int index) {
    var n = index + 1;
    final buffer = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      buffer.write(String.fromCharCode(65 + rem));
      n = (n - 1) ~/ 26;
    }
    return buffer.toString().split('').reversed.join();
  }

  /// Excel's serial date: days since 1899-12-30, the fraction being the time
  /// of day. Built from the wall-clock fields so no timezone shift sneaks in.
  static double excelSerial(DateTime value) {
    final asUtc = DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
    );
    final ms = asUtc.difference(DateTime.utc(1899, 12, 30)).inMilliseconds;
    return ms / Duration.millisecondsPerDay;
  }

  static String safeSheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    final nonEmpty = cleaned.isEmpty ? 'Sheet1' : cleaned;
    return nonEmpty.length > 31 ? nonEmpty.substring(0, 31) : nonEmpty;
  }

  /// Escapes XML special characters and drops the control characters XML
  /// 1.0 cannot carry at all (a stray one would make Excel refuse the file).
  static String _esc(String value) {
    final safe = value.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]'),
      '',
    );
    return safe
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _num(num value) {
    if (value is int) return value.toString();
    final d = value.toDouble();
    if (d.isNaN || d.isInfinite) return '0';
    return d.toString();
  }

  static String _cellXml(String ref, XlsxCell cell) {
    final s = cell.style.index;
    final value = cell.value;
    final formula =
        cell.formula == null ? '' : '<f>${_esc(cell.formula!)}</f>';

    if (value == null) {
      return formula.isEmpty
          ? '<c r="$ref" s="$s"/>'
          : '<c r="$ref" s="$s">$formula</c>';
    }

    if (value is num) {
      return '<c r="$ref" s="$s">$formula<v>${_num(value)}</v></c>';
    }

    if (value is DateTime) {
      return '<c r="$ref" s="$s">$formula'
          '<v>${_num(excelSerial(value))}</v></c>';
    }

    var text = value.toString();
    if (text.length > _maxCellText) text = text.substring(0, _maxCellText);
    return '<c r="$ref" s="$s" t="inlineStr">'
        '<is><t xml:space="preserve">${_esc(text)}</t></is></c>';
  }

  static String _sheetXml(XlsxSheet sheet) {
    final rowCount = sheet.rows.length;
    var colCount = sheet.columnWidths.length;
    for (final row in sheet.rows) {
      if (row != null && row.length > colCount) colCount = row.length;
    }
    if (colCount == 0) colCount = 1;

    final lastRef = '${columnLetter(colCount - 1)}${rowCount == 0 ? 1 : rowCount}';
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
      )
      // Fit the report to one page wide when printed.
      ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
      ..write('<dimension ref="A1:$lastRef"/>');

    b.write('<sheetViews><sheetView workbookViewId="0">');
    if (sheet.frozenRows > 0) {
      final topLeft = 'A${sheet.frozenRows + 1}';
      b
        ..write(
          '<pane ySplit="${sheet.frozenRows}" topLeftCell="$topLeft" '
          'activePane="bottomLeft" state="frozen"/>',
        )
        ..write(
          '<selection pane="bottomLeft" activeCell="$topLeft" sqref="$topLeft"/>',
        );
    }
    b.write('</sheetView></sheetViews>');

    b.write('<sheetFormatPr defaultRowHeight="15"/>');

    if (sheet.columnWidths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < sheet.columnWidths.length; i++) {
        b.write(
          '<col min="${i + 1}" max="${i + 1}" '
          'width="${sheet.columnWidths[i]}" customWidth="1"/>',
        );
      }
      b.write('</cols>');
    }

    b.write('<sheetData>');
    for (var r = 0; r < rowCount; r++) {
      final row = sheet.rows[r];
      final rowNumber = r + 1;
      final height = sheet.rowHeights[rowNumber];
      final heightAttr =
          height == null ? '' : ' ht="$height" customHeight="1"';

      if (row == null || row.isEmpty) {
        if (heightAttr.isNotEmpty) b.write('<row r="$rowNumber"$heightAttr/>');
        continue;
      }

      b.write('<row r="$rowNumber"$heightAttr>');
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell == null) continue;
        b.write(_cellXml('${columnLetter(c)}$rowNumber', cell));
      }
      b.write('</row>');
    }
    b.write('</sheetData>');

    if (sheet.autoFilterRef != null) {
      b.write('<autoFilter ref="${sheet.autoFilterRef}"/>');
    }

    if (sheet.merges.isNotEmpty) {
      b.write('<mergeCells count="${sheet.merges.length}">');
      for (final ref in sheet.merges) {
        b.write('<mergeCell ref="$ref"/>');
      }
      b.write('</mergeCells>');
    }

    b
      ..write(
        '<pageMargins left="0.4" right="0.4" top="0.6" bottom="0.6" '
        'header="0.3" footer="0.3"/>',
      )
      ..write(
        '<pageSetup paperSize="9" orientation="landscape" '
        'fitToWidth="1" fitToHeight="0"/>',
      )
      ..write('</worksheet>');

    return b.toString();
  }

  static String _absoluteRange(String ref) {
    // "A6:H40" -> "$A$6:$H$40"
    return ref
        .split(':')
        .map((part) => part.replaceAllMapped(
              RegExp(r'^([A-Z]+)(\d+)$'),
              (m) => '\$${m[1]}\$${m[2]}',
            ))
        .join(':');
  }

  static String _workbookXml(XlsxSheet sheet, String sheetName) {
    final quoted = "'${sheetName.replaceAll("'", "''")}'";
    final names = <String>[
      if (sheet.autoFilterRef != null)
        '<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">'
            '${_esc('$quoted!${_absoluteRange(sheet.autoFilterRef!)}')}'
            '</definedName>',
      if (sheet.printTitleRow != null)
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">'
            '${_esc('$quoted!\$${sheet.printTitleRow}:\$${sheet.printTitleRow}')}'
            '</definedName>',
    ];

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView/></bookViews>'
        '<sheets><sheet name="${_esc(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
        '${names.isEmpty ? '' : '<definedNames>${names.join()}</definedNames>'}'
        '</workbook>';
  }

  static String _coreXml(String title, String creator, DateTime created) {
    final stamp = '${created.toUtc().toIso8601String().split('.').first}Z';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>${_esc(title)}</dc:title>'
        '<dc:creator>${_esc(creator)}</dc:creator>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$stamp</dcterms:created>'
        '</cp:coreProperties>';
  }

  static const String _contentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '</Types>';

  static const String _rootRelsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '</Relationships>';

  static const String _workbookRelsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  // Number formats: 164 = date + time, 165 = peso currency.
  // Fonts: 0 body, 1 bold, 2 title, 3 header (bold white), 4 note (grey
  // italic). Fills: 0/1 are Excel's required defaults, 2 = header brand
  // blue, 3 = soft summary tint. Borders: 0 none, 1 thin light grey.
  //
  // cellXfs MUST stay in XlsxStyle order.
  static const String _stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="2">'
      '<numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm"/>'
      '<numFmt numFmtId="165" formatCode="&quot;₱&quot;#,##0.00"/>'
      '</numFmts>'
      '<fonts count="5">'
      '<font><sz val="11"/><color rgb="FF1F2D3D"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="11"/><color rgb="FF17435C"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="16"/><color rgb="FF17435C"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>'
      '<font><i/><sz val="10"/><color rgb="FF7C8B9B"/><name val="Calibri"/><family val="2"/></font>'
      '</fonts>'
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF2A5F7E"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFEDF3F8"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border>'
      '<left style="thin"><color rgb="FFD6E0E8"/></left>'
      '<right style="thin"><color rgb="FFD6E0E8"/></right>'
      '<top style="thin"><color rgb="FFD6E0E8"/></top>'
      '<bottom style="thin"><color rgb="FFD6E0E8"/></bottom>'
      '<diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="13">'
      // normal
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      // title
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"><alignment vertical="center"/></xf>'
      // metaLabel
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      // metaValue
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      // metaDateTime
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="left"/></xf>'
      // header
      '<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      // text
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>'
      // dateTime
      '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top"/></xf>'
      // currency
      '<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>'
      // summaryLabel
      '<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
      // summaryNumber
      '<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
      // summaryCurrency
      '<xf numFmtId="165" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>'
      // note
      '<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>'
      '</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}
