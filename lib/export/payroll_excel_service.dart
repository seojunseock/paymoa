// lib/export/payroll_excel_service.dart
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/store.dart';
import '../models/store_worker.dart';
import '../models/store_schedule.dart';
import '../policies/policies.dart';
import '../payroll/payroll_document_service.dart';

/// 급여 엑셀 3종 생성기
/// ① 임금명세서 (A4 1장 4분할)
/// ② 급여대장   (클래식+) — 전체 한눈에, 주민번호/사업자번호 입력칸 제공
/// ③ 간이지급명세서 (프로+) — 반기 국세청 제출용, 주민번호 빈칸(노란색)
class PayrollExcelService {
  final _fmt = NumberFormat('#,###');
  final _docSvc = const PayrollDocumentService();

  // ── 팔레트 ──────────────────────────────────────────
  static const _hdrBg = 'FF4B3FA0'; // 헤더 진보라
  static const _ltBg = 'FFF3EEFF'; // 연보라
  static const _altBg = 'FFF8F7FF'; // 교대행 배경
  static const _totBg = 'FFE9E4FF'; // 합계 행
  static const _rrnBg = 'FFFFF3CD'; // 입력칸 노란 배경
  static const _white = 'FFFFFFFF';
  static const _violet = 'FF7C3AED';

  // ══════════════════════════════════════════════════════
  // ① 임금명세서 (A4 1장 4분할)
  // ══════════════════════════════════════════════════════
  Future<void> generateWageStatements({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required int year,
    required int month,
  }) async {
    final now = DateTime.now();
    final untilDate = (year == now.year && month == now.month)
        ? DateTime(now.year, now.month, now.day)
        : null;

    final rows = _docSvc
        .buildCalendarMonthDocument(
          store: store,
          workers: workers,
          schedules: schedules,
          year: year,
          month: month,
          untilDate: untilDate,
        )
        .where((r) => r.scheduleCount > 0)
        .toList();

    if (rows.isEmpty) return;

    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    // ✅ A4 1장에 4개씩 들어가도록 2x2 배치
    for (int i = 0; i < rows.length; i += 4) {
      final pageRows = rows.skip(i).take(4).toList();
      final sheetName = '명세서_${(i ~/ 4) + 1}';
      final sheet = excel[sheetName];
      _buildWageQuarterSheet(sheet, pageRows, store.name);
    }

    final payDate = rows.first.payDate;

    await _share(
      excel: excel,
      fileName:
          '임금명세서_${store.name}_${payDate.year}년_${payDate.month}월_${payDate.day}일.xlsx',
      subject:
          '${store.name} ${payDate.year}년 ${payDate.month}월 ${payDate.day}일 급여일 임금명세서',
    );
  }

  void _buildWageQuarterSheet(
    Sheet sheet,
    List<PayrollDocumentRow> rows,
    String storeName,
  ) {
    // 왼쪽 블록: 0~4 / 오른쪽 블록: 6~10 (가운데 5는 여백)
    for (int c = 0; c <= 10; c++) {
      if (c == 5) {
        sheet.setColumnWidth(c, 2.5);
      } else if (c == 0 || c == 6) {
        sheet.setColumnWidth(c, 15.0);
      } else if (c == 1 || c == 7) {
        sheet.setColumnWidth(c, 14.0);
      } else if (c == 2 || c == 8) {
        sheet.setColumnWidth(c, 14.0);
      } else if (c == 3 || c == 9) {
        sheet.setColumnWidth(c, 14.0);
      } else {
        sheet.setColumnWidth(c, 16.0);
      }
    }

    // 2x2 배치
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final mergedNotes = _mergeChangeNotes(r.changeNotes);
      final hasNotes = mergedNotes.isNotEmpty;
      final top = (i ~/ 2) * (hasNotes ? 24 : 18); // ✅ 변경내역 있으면 카드 높이 확장
      final left = (i % 2 == 0) ? 0 : 6; // 좌/우
      _drawSingleWageCard(sheet, top, left, r, storeName);
    }
  }

  void _drawSingleWageCard(
    Sheet sheet,
    int top,
    int left,
    PayrollDocumentRow r,
    String storeName,
  ) {
    final deduct = r.gross - r.net;
    final basePay = (r.hourlyWage * r.workedMinutes / 60.0).round();
    final surchargePay = r.gross - basePay;

    final taxText = _taxLabel(r.tax) ?? '-';
    final insText = _insLabel(r.insurance) ?? '-';

    // 제목
    _mg(sheet, top + 0, left + 0, top + 0, left + 4);
    _c(
      sheet,
      top + 0,
      left + 0,
      '임금명세서',
      bold: true,
      fs: 14,
      ha: HorizontalAlign.Center,
      bg: _white,
      fc: 'FF1A1A2E',
      rh: 24,
    );

    // 매장명 / 이름 / 지급일
    _mg(sheet, top + 1, left + 0, top + 1, left + 4);
    _c(
      sheet,
      top + 1,
      left + 0,
      '$storeName  |  ${r.workerName}  |  지급일 ${_ymd(r.payDate)}',
      fs: 9,
      ha: HorizontalAlign.Center,
      fc: 'FF555577',
      rh: 20,
    );

    // 포인트 바
    _mg(sheet, top + 2, left + 0, top + 2, left + 4);
    _c(sheet, top + 2, left + 0, '', bg: _hdrBg, rh: 3);

    // 기본정보
    _cardLabelValue(sheet, top + 3, left, '근무기간',
        '${_ymd(r.periodStart)} ~ ${_ymd(r.periodEnd)}');
    _cardLabelValue(sheet, top + 4, left, '근무일수', '${r.scheduleCount}일');
    _cardLabelValue(sheet, top + 5, left, '총 근무시간', r.workedTimeText);
    _cardLabelValue(
        sheet, top + 6, left, '시급', '${_fmt.format(r.hourlyWage)}원');

    // 지급 항목
    _cardSectionHead(sheet, top + 7, left, '지급 항목');
    _cardLabelValue(sheet, top + 8, left, '기본급', '${_fmt.format(basePay)}원');
    _cardLabelValue(
      sheet,
      top + 9,
      left,
      '가산수당',
      surchargePay > 0 ? '+${_fmt.format(surchargePay)}원' : '-',
      valueColor: surchargePay > 0 ? 'FF0D6E3A' : 'FF111133',
    );
    _cardLabelValue(
      sheet,
      top + 10,
      left,
      '지급 합계',
      '${_fmt.format(r.gross)}원',
      bold: true,
      bgValue: _ltBg,
    );

    // 공제 항목
    _cardSectionHead(sheet, top + 11, left, '공제 항목');
    _cardLabelValue(sheet, top + 12, left, '세금', taxText);
    _cardLabelValue(sheet, top + 13, left, '보험', insText);
    _cardLabelValue(
      sheet,
      top + 14,
      left,
      '공제 합계',
      deduct > 0 ? '-${_fmt.format(deduct)}원' : '-',
      bold: true,
      valueColor: 'FFCC3300',
    );

    // 실지급액
    _mg(sheet, top + 15, left + 0, top + 15, left + 4);
    _c(sheet, top + 15, left + 0, '', bg: _hdrBg, rh: 3);

    _c(
      sheet,
      top + 16,
      left + 0,
      '실 지급액',
      bold: true,
      fs: 11,
      bg: _hdrBg,
      fc: _white,
      rh: 26,
      border: true,
    );
    _mg(sheet, top + 16, left + 1, top + 16, left + 4);
    _c(
      sheet,
      top + 16,
      left + 1,
      '${_fmt.format(r.net)}원',
      bold: true,
      fs: 12,
      ha: HorizontalAlign.Right,
      bg: _hdrBg,
      fc: _white,
      border: true,
    );

    final mergedNotes = _mergeChangeNotes(r.changeNotes);

    if (mergedNotes.isNotEmpty) {
      final notesText = mergedNotes.join('\n');
      final noteHeight = (mergedNotes.length * 14) < 18
          ? 18.0
          : (mergedNotes.length * 14).toDouble();

      _mg(sheet, top + 17, left + 0, top + 17, left + 4);
      _c(
        sheet,
        top + 17,
        left + 0,
        notesText,
        fs: 7,
        fc: 'FF555577',
        ha: HorizontalAlign.Left,
        wrap: true,
        rh: noteHeight,
        border: true,
      );

      // 하단 문구
      _mg(sheet, top + 18, left + 0, top + 18, left + 4);
      _c(
        sheet,
        top + 18,
        left + 0,
        '※ 본 명세서는 페이모아 앱에서 자동 생성되었습니다.',
        fs: 7,
        fc: 'FF999999',
        ha: HorizontalAlign.Center,
        wrap: true,
        rh: 16,
      );
    } else {
      // 하단 문구
      _mg(sheet, top + 17, left + 0, top + 17, left + 4);
      _c(
        sheet,
        top + 17,
        left + 0,
        '※ 본 명세서는 페이모아 앱에서 자동 생성되었습니다.',
        fs: 7,
        fc: 'FF999999',
        ha: HorizontalAlign.Center,
        wrap: true,
        rh: 16,
      );
    }
  }

  void _cardSectionHead(Sheet sheet, int row, int left, String text) {
    _mg(sheet, row, left + 0, row, left + 4);
    _c(
      sheet,
      row,
      left + 0,
      text,
      bold: true,
      fs: 9,
      bg: _ltBg,
      fc: _violet,
      rh: 20,
      border: true,
    );
  }

  void _cardLabelValue(
    Sheet sheet,
    int row,
    int left,
    String label,
    String value, {
    bool bold = false,
    String? valueColor,
    String? bgValue,
  }) {
    _mg(sheet, row, left + 0, row, left + 1);
    _c(
      sheet,
      row,
      left + 0,
      label,
      fs: 8,
      fc: 'FF444466',
      rh: 20,
      border: true,
    );

    _mg(sheet, row, left + 2, row, left + 4);
    _c(
      sheet,
      row,
      left + 2,
      value,
      fs: 8,
      bold: bold,
      fc: valueColor ?? 'FF111133',
      bg: bgValue ?? _white,
      ha: HorizontalAlign.Right,
      border: true,
    );
  }

  // ══════════════════════════════════════════════════════
  // ② 급여대장 (클래식+)
  // ══════════════════════════════════════════════════════
  Future<void> generatePayrollLedger({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required int year,
    required int month,
  }) async {
    final now = DateTime.now();
    final untilDate = (year == now.year && month == now.month)
        ? DateTime(now.year, now.month, now.day)
        : null;

    final rows = _docSvc
        .buildCalendarMonthDocument(
          store: store,
          workers: workers,
          schedules: schedules,
          year: year,
          month: month,
          untilDate: untilDate,
        )
        .where((r) => r.scheduleCount > 0)
        .toList();

    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    _buildLedgerSheet(excel, store, rows, year, month);

    final payDate =
        rows.isNotEmpty ? rows.first.payDate : DateTime(year, month, 15);

    await _share(
      excel: excel,
      fileName:
          '급여대장_${store.name}_${payDate.year}년_${payDate.month}월_${payDate.day}일.xlsx',
      subject:
          '${store.name} ${payDate.year}년 ${payDate.month}월 ${payDate.day}일 급여일 급여대장',
    );
  }

  void _buildLedgerSheet(
    Excel excel,
    Store store,
    List<PayrollDocumentRow> rows,
    int year,
    int month,
  ) {
    final sheet = excel['급여대장'];

    const C = 10;
    const widths = [
      16.0,
      20.0,
      10.0,
      14.0,
      12.0,
      14.0,
      10.0,
      12.0,
      14.0,
      15.0,
    ];
    for (int i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }

    final periodStart =
        rows.isNotEmpty ? rows.first.periodStart : DateTime(year, month, 1);
    final periodEnd =
        rows.isNotEmpty ? rows.first.periodEnd : DateTime(year, month + 1, 0);
    final payDate =
        rows.isNotEmpty ? rows.first.payDate : DateTime(year, month, 15);
    final printedAt = DateTime.now();

    int row = 0;
    _gap(sheet, row, 10);
    row++;

    _mg(sheet, row, 0, row, C - 1);
    _c(
      sheet,
      row,
      0,
      '급여대장',
      bold: true,
      fs: 20,
      ha: HorizontalAlign.Center,
      bg: _white,
      fc: 'FF1A1A2E',
      rh: 34,
    );
    row++;

    _mg(sheet, row, 0, row, C - 1);
    _c(
      sheet,
      row,
      0,
      store.name,
      bold: true,
      fs: 14,
      ha: HorizontalAlign.Center,
      fc: 'FF3B0764',
      rh: 24,
    );
    row++;

    _mg(sheet, row, 0, row, 4);
    _c(
      sheet,
      row,
      0,
      '사업자등록번호  ____________________',
      fs: 11,
      fc: 'FF555577',
      rh: 22,
    );
    _mg(sheet, row, 5, row, 9);
    _c(
      sheet,
      row,
      5,
      '출력일  ${_ymd(printedAt)}',
      fs: 11,
      ha: HorizontalAlign.Right,
      fc: 'FF555577',
    );
    row++;

    _mg(sheet, row, 0, row, 4);
    _c(
      sheet,
      row,
      0,
      '근무기간  ${_ymd(periodStart)} ~ ${_ymd(periodEnd)}',
      fs: 11,
      fc: 'FF555577',
      rh: 22,
    );
    _mg(sheet, row, 5, row, 9);
    _c(
      sheet,
      row,
      5,
      '급여일  ${_ymd(payDate)}',
      fs: 11,
      ha: HorizontalAlign.Right,
      fc: 'FF555577',
    );
    row++;

    _mgAccentBar(sheet, row, C);
    row++;
    _gap(sheet, row, 8);
    row++;

    const hdrs = [
      '이름',
      '주민등록번호\n(직접 기입)',
      '근무일수',
      '총 근무시간',
      '시급',
      '지급액',
      '세금',
      '보험',
      '공제액',
      '실지급액',
    ];
    for (int i = 0; i < hdrs.length; i++) {
      _c(
        sheet,
        row,
        i,
        hdrs[i],
        bold: true,
        fs: 12,
        bg: _hdrBg,
        fc: _white,
        ha: HorizontalAlign.Center,
        rh: 34,
        wrap: true,
        border: true,
      );
    }
    row++;

    int tDays = 0, tMins = 0, tGross = 0, tDeduct = 0, tNet = 0;

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final bg = (i % 2 == 0) ? _white : _altBg;
      final deduct = r.gross - r.net;

      _c(sheet, row, 0, r.workerName, bg: bg, fs: 12, border: true, rh: 30);
      _c(sheet, row, 1, '',
          bg: _rrnBg, fs: 11, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, 2, '${r.scheduleCount}일',
          bg: bg, fs: 12, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, 3, r.workedTimeText,
          bg: bg, fs: 12, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, 4, '${_fmt.format(r.hourlyWage)}원',
          bg: bg, fs: 12, ha: HorizontalAlign.Right, border: true);
      _c(sheet, row, 5, '${_fmt.format(r.gross)}원',
          bg: bg, fs: 12, ha: HorizontalAlign.Right, border: true);
      _c(sheet, row, 6, _taxShort(r.tax),
          bg: bg, fs: 11, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, 7, _insShort(r.insurance),
          bg: bg, fs: 11, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, 8, deduct > 0 ? '${_fmt.format(deduct)}원' : '-',
          bg: bg, fs: 12, ha: HorizontalAlign.Right, border: true);
      _c(sheet, row, 9, '${_fmt.format(r.net)}원',
          bg: bg, fs: 12, bold: true, ha: HorizontalAlign.Right, border: true);

      tDays += r.scheduleCount;
      tMins += r.workedMinutes;
      tGross += r.gross;
      tDeduct += deduct;
      tNet += r.net;
      row++;
    }

    _c(sheet, row, 0, '합계',
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Center,
        rh: 32,
        border: true);
    _c(sheet, row, 1, '${rows.length}명',
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Center,
        border: true);
    _c(sheet, row, 2, '$tDays일',
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Center,
        border: true);
    _c(sheet, row, 3, _hm(tMins),
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Center,
        border: true);
    _c(sheet, row, 4, '', bg: _totBg, border: true);
    _c(sheet, row, 5, '${_fmt.format(tGross)}원',
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Right,
        border: true);
    _c(sheet, row, 6, '', bg: _totBg, border: true);
    _c(sheet, row, 7, '', bg: _totBg, border: true);
    _c(sheet, row, 8, tDeduct > 0 ? '${_fmt.format(tDeduct)}원' : '-',
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Right,
        border: true);
    _c(sheet, row, 9, '${_fmt.format(tNet)}원',
        bold: true,
        fs: 12,
        bg: _totBg,
        ha: HorizontalAlign.Right,
        border: true);
    row += 2;

    // ✅ 월 문서 변경내역 한 줄씩
    final noteLines = _mergeChangeNotes([
      for (final r in rows) ...r.changeNotes,
    ]);
    for (final note in noteLines) {
      _mg(sheet, row, 0, row, C - 1);
      _c(
        sheet,
        row,
        0,
        note,
        fs: 9,
        fc: 'FF555577',
        wrap: true,
        rh: 20,
      );
      row++;
    }
    if (noteLines.isNotEmpty) {
      row++;
    }

    _mg(sheet, row, 0, row, C - 1);
    _c(
      sheet,
      row,
      0,
      '※ 주민등록번호와 사업자등록번호는 직접 기입해 주세요. 세금/보험 칸은 적용 기준 표시용이며, 실제 차감액은 공제액에 반영됩니다.',
      fs: 9,
      fc: 'FF777777',
      wrap: true,
      rh: 20,
    );
    row++;

    _mg(sheet, row, 0, row, C - 1);
    _c(
      sheet,
      row,
      0,
      '※ 가로 인쇄에 맞춘 파일입니다!',
      fs: 9,
      fc: 'FF999999',
      ha: HorizontalAlign.Center,
      wrap: true,
      rh: 18,
    );
  }

  // ══════════════════════════════════════════════════════
  // ③ 간이지급명세서 (프로+)
  // ══════════════════════════════════════════════════════
  Future<void> generateSimplifiedStatement({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required int year,
    required int halfYear,
  }) async {
    final startM = halfYear == 1 ? 1 : 7;
    final now = DateTime.now();
    final allRows = <PayrollDocumentRow>[];
    for (int m = startM; m < startM + 6; m++) {
      final untilDate = (year == now.year && m == now.month)
          ? DateTime(now.year, now.month, now.day)
          : null;
      allRows.addAll(_docSvc
          .buildCalendarMonthDocument(
            store: store,
            workers: workers,
            schedules: schedules,
            year: year,
            month: m,
            untilDate: untilDate,
          )
          .where((r) => r.scheduleCount > 0));
    }

    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');
    _buildSimplifiedSheet(excel, store.name, allRows, year, halfYear);

    final half = halfYear == 1 ? '상반기' : '하반기';
    final latestPayDate = allRows.isNotEmpty
        ? (allRows.map((e) => e.payDate).toList()
              ..sort((a, b) => a.compareTo(b)))
            .last
        : null;

    await _share(
      excel: excel,
      fileName: latestPayDate == null
          ? '간이지급명세서_${store.name}_${year}년$half.xlsx'
          : '간이지급명세서_${store.name}_${latestPayDate.year}년_${latestPayDate.month}월_${latestPayDate.day}일_$half.xlsx',
      subject: latestPayDate == null
          ? '${store.name} $year년 $half 간이지급명세서'
          : '${store.name} ${latestPayDate.year}년 ${latestPayDate.month}월 ${latestPayDate.day}일 급여일 $half 간이지급명세서',
    );
  }

  void _buildSimplifiedSheet(Excel excel, String storeName,
      List<PayrollDocumentRow> rows, int year, int halfYear) {
    final sheet = excel['간이지급명세서'];
    final startM = halfYear == 1 ? 1 : 7;
    final months = List.generate(6, (i) => startM + i);
    final half = halfYear == 1 ? '상반기 (1~6월)' : '하반기 (7~12월)';

    const C = 10;
    const widths = [5.0, 14.0, 20.0, 11.0, 11.0, 11.0, 11.0, 11.0, 11.0, 14.0];
    for (int i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }

    int row = 0;
    _gap(sheet, row, 14);
    row++;

    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '간이지급명세서 (근로소득)',
        bold: true,
        fs: 16,
        ha: HorizontalAlign.Center,
        bg: _white,
        fc: 'FF1A1A2E',
        rh: 42);
    row++;

    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '$storeName  |  $year년 $half',
        fs: 11, ha: HorizontalAlign.Center, fc: 'FF555577', rh: 26);
    row++;
    _mgAccentBar(sheet, row, C);
    row++;
    _gap(sheet, row, 8);
    row++;

    final mHdrs = [
      'No',
      '성  명',
      '주민등록번호\n(직접 기입)',
      ...months.map((m) => '$m월'),
      '합  계',
    ];
    for (int i = 0; i < mHdrs.length; i++) {
      _c(sheet, row, i, mHdrs[i],
          bold: true,
          fs: 11,
          bg: _hdrBg,
          fc: _white,
          ha: HorizontalAlign.Center,
          rh: 36,
          wrap: true,
          border: true);
    }
    row++;

    final Map<String, List<PayrollDocumentRow>> byWorker = {};
    for (final r in rows) {
      (byWorker[r.workerUid] ??= []).add(r);
    }

    int no = 1;
    final Map<int, int> colTotals = {for (final m in months) m: 0};
    int grandTotal = 0;

    for (final entry in byWorker.entries) {
      final wRows = entry.value;
      final wName = wRows.first.workerName;
      final bg = (no % 2 == 0) ? _altBg : _white;

      final Map<int, int> netByMonth = {};
      for (final r in wRows) {
        final m = r.payDate.month;
        netByMonth[m] = (netByMonth[m] ?? 0) + r.net;
      }

      final wTotal = months.fold(0, (s, m) => s + (netByMonth[m] ?? 0));
      grandTotal += wTotal;
      for (final m in months) {
        colTotals[m] = (colTotals[m] ?? 0) + (netByMonth[m] ?? 0);
      }

      _c(sheet, row, 0, '$no',
          bg: bg, ha: HorizontalAlign.Center, fs: 11, rh: 28, border: true);
      _c(sheet, row, 1, wName, bg: bg, fs: 11, border: true);
      _c(sheet, row, 2, '', bg: _rrnBg, border: true);
      for (int i = 0; i < months.length; i++) {
        final v = netByMonth[months[i]] ?? 0;
        _c(sheet, row, 3 + i, v > 0 ? _fmt.format(v) : '-',
            bg: bg, ha: HorizontalAlign.Right, fs: 11, border: true);
      }
      _c(sheet, row, 9, _fmt.format(wTotal),
          bold: true, bg: bg, ha: HorizontalAlign.Right, fs: 11, border: true);
      no++;
      row++;
    }

    _c(sheet, row, 0, '합계',
        bold: true,
        fs: 11,
        bg: _totBg,
        ha: HorizontalAlign.Center,
        rh: 30,
        border: true);
    _c(sheet, row, 1, '${no - 1}명',
        bold: true,
        fs: 11,
        bg: _totBg,
        ha: HorizontalAlign.Center,
        border: true);
    _c(sheet, row, 2, '', bg: _totBg, border: true);
    for (int i = 0; i < months.length; i++) {
      final v = colTotals[months[i]] ?? 0;
      _c(sheet, row, 3 + i, v > 0 ? _fmt.format(v) : '-',
          bold: true,
          bg: _totBg,
          ha: HorizontalAlign.Right,
          fs: 11,
          border: true);
    }
    _c(sheet, row, 9, _fmt.format(grandTotal),
        bold: true,
        bg: _totBg,
        ha: HorizontalAlign.Right,
        fs: 11,
        border: true);
    row += 2;

    // ✅ 반기 전체 변경내역 한 줄씩
    final noteLines = _mergeChangeNotes([
      for (final r in rows) ...r.changeNotes,
    ]);
    for (final note in noteLines) {
      _mg(sheet, row, 0, row, C - 1);
      _c(sheet, row, 0, note, fs: 9, fc: 'FF555577', wrap: true, rh: 20);
      row++;
    }
    if (noteLines.isNotEmpty) {
      row++;
    }

    for (final note in [
      '※ 주민등록번호(노란 칸)는 홈택스 제출 전 직접 기입해 주세요.',
      '※ 제출 기한: 상반기(1~6월) → 7월 10일  /  하반기(7~12월) → 다음해 1월 10일',
      '※ 금액은 실지급액(공제 후) 기준입니다. 앱은 개인정보 보호를 위해 주민등록번호를 수집하지 않습니다.',
    ]) {
      _mg(sheet, row, 0, row, C - 1);
      _c(sheet, row, 0, note, fs: 9, fc: 'FF777777', wrap: true, rh: 22);
      row++;
    }
  }

  // ══════════════════════════════════════════════════════
  // 공용 레이아웃 헬퍼
  // ══════════════════════════════════════════════════════

  void _secHead(Sheet sheet, int row, String label) {
    _mg(sheet, row, 0, row, 1);
    _c(sheet, row, 0, label,
        bold: true, fs: 11, bg: _ltBg, fc: _violet, rh: 28);
  }

  void _lv(Sheet sheet, int row, String label, String value,
      {bool bold = false, String? fc2, String? bg2}) {
    _c(sheet, row, 0, label, fs: 11, fc: 'FF444466', rh: 26);
    _c(sheet, row, 1, value,
        bold: bold,
        fs: 11,
        fc: fc2 ?? 'FF111133',
        bg: bg2 ?? _white,
        ha: HorizontalAlign.Right);
  }

  void _accentBar2(Sheet sheet, int row) {
    _mg(sheet, row, 0, row, 1);
    _c(sheet, row, 0, '', bg: _hdrBg, rh: 3);
  }

  void _mgAccentBar(Sheet sheet, int row, int C) {
    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '', bg: _hdrBg, rh: 4);
  }

  void _gap(Sheet sheet, int row, double h) => sheet.setRowHeight(row, h);

  // ══════════════════════════════════════════════════════
  // 셀 기본 헬퍼
  // ══════════════════════════════════════════════════════
  void _c(
    Sheet sheet,
    int row,
    int col,
    String value, {
    bool bold = false,
    int fs = 10,
    String bg = 'FFFFFFFF',
    String fc = 'FF000000',
    HorizontalAlign ha = HorizontalAlign.Left,
    bool wrap = false,
    double? rh,
    bool border = false,
  }) {
    final cell =
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
    final thin = border ? Border(borderStyle: BorderStyle.Thin) : null;
    cell.cellStyle = CellStyle(
      bold: bold,
      fontSize: fs,
      fontFamily: 'Malgun Gothic',
      backgroundColorHex: ExcelColor.fromHexString(bg),
      fontColorHex: ExcelColor.fromHexString(fc),
      horizontalAlign: ha,
      verticalAlign: VerticalAlign.Center,
      textWrapping: wrap ? TextWrapping.WrapText : TextWrapping.Clip,
      leftBorder: thin,
      rightBorder: thin,
      topBorder: thin,
      bottomBorder: thin,
    );
    if (rh != null) sheet.setRowHeight(row, rh);
  }

  void _mg(Sheet sheet, int r1, int c1, int r2, int c2) {
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: c1, rowIndex: r1),
      CellIndex.indexByColumnRow(columnIndex: c2, rowIndex: r2),
    );
  }

  Future<void> _share({
    required Excel excel,
    required String fileName,
    required String subject,
  }) async {
    final bytes = excel.encode();
    if (bytes == null) throw Exception('엑셀 생성 실패');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: subject,
    );
  }

  List<String> _mergeChangeNotes(List<String> notes) {
    final result = <String>[];
    final map = <String, int>{};

    final dateRegex =
        RegExp(r'^\s*(.+?)\s+(\d{4}[./]\d{1,2}[./]\d{1,2})\s+(.*)$');

    for (final raw in notes) {
      final text = raw.trim();
      if (text.isEmpty) continue;

      final m = dateRegex.firstMatch(text);
      if (m == null) {
        if (!map.containsKey(text)) {
          map[text] = result.length;
          result.add(text);
        }
        continue;
      }

      final name = m.group(1)!.trim();
      final date = m.group(2)!.trim();
      final change = m.group(3)!.trim();

      final key = '$name|$date';

      if (!map.containsKey(key)) {
        map[key] = result.length;
        result.add('$name $date $change');
      } else {
        final idx = map[key]!;
        if (change.isNotEmpty) {
          result[idx] = '${result[idx]}, $change';
        }
      }
    }

    return result;
  }

  // ══════════════════════════════════════════════════════
  // 계산 / 표시 헬퍼
  // ══════════════════════════════════════════════════════
  String _p(int n) => n.toString().padLeft(2, '0');
  String _ymd(DateTime d) => '${d.year}.${_p(d.month)}.${_p(d.day)}';

  String _hm(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h시간' : '$h시간 $m분';
  }

  String? _taxLabel(TaxConfig tax) {
    if (tax == TaxConfig.none) return null;
    if (tax == TaxConfig.biz33) return '소득세 (3.3%)';
    if (tax == TaxConfig.day66) return '소득세 (6.6%)';
    if (tax is TaxConfigCustomPercent) return '소득세 (${tax.percent}%)';
    return '소득세';
  }

  String? _insLabel(InsuranceConfig ins) {
    if (ins is InsuranceNone) return null;
    if (ins is InsuranceEmploymentOnly) return '고용보험 (0.9%)';
    if (ins is InsuranceFour) return '4대보험';
    return null;
  }

  String _taxShort(TaxConfig tax) {
    if (tax == TaxConfig.none) return '-';
    if (tax == TaxConfig.biz33) return '3.3%';
    if (tax == TaxConfig.day66) return '6.6%';
    if (tax is TaxConfigCustomPercent) return '${tax.percent}%';
    return '직접입력';
  }

  String _insShort(InsuranceConfig ins) {
    if (ins is InsuranceNone) return '-';
    if (ins is InsuranceEmploymentOnly) return '고용보험';
    if (ins is InsuranceFour) return '4대보험';
    return '직접입력';
  }

  int _taxAmt(PayrollDocumentRow r) {
    final deduct = r.gross - r.net;
    if (r.insurance is InsuranceNone) return deduct;
    if (r.insurance is InsuranceEmploymentOnly) {
      return (deduct - (r.gross * 0.009).round()).clamp(0, deduct);
    }
    if (r.insurance is InsuranceFour) {
      return (deduct - (r.gross * 0.047).round()).clamp(0, deduct);
    }
    return deduct;
  }

  int _insAmt(PayrollDocumentRow r) =>
      (r.gross - r.net - _taxAmt(r)).clamp(0, r.gross);
}
