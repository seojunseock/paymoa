// lib/export/payroll_excel_service.dart
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/store.dart';
import '../models/store_worker.dart';
import '../models/store_schedule.dart';
import '../models/ui_calendar_models.dart';

import '../policies/policies.dart';
import '../policies/policy_mapper.dart' as pm;

import '../payroll/payroll_engine.dart';
import '../payroll/payroll_policy.dart';
import '../payroll/pay_calculator.dart';

/// 인건비(P/T) 지급명세서 엑셀
/// 구성: 수신인 / 표제 / 직원별 내역(성명·주민번호·근무기간·근무일수·총근무시간·시급·지급액·공제액·실지급액)
///       / 월별 합계 / 분기별 총계
// ─────────────────────────────────────────────────────────────────────────────
// ⚠️ const 생성자 사용 불가 — NumberFormat 이 non-const 이므로 제거
// ─────────────────────────────────────────────────────────────────────────────
class PayrollExcelService {
  final PayrollEngine _engine;
  final _fmt = NumberFormat('#,###');

  PayrollExcelService({PayrollEngine? engine})
      : _engine = engine ?? PayrollEngine();

  // ── 공개 API ───────────────────────────────────────────────────────────────
  Future<void> generateAndSharePayroll({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
  }) async {
    final now = DateTime.now();
    final preview = _engine
        .previewNext(policy: store.payrollPolicy, from: now, count: 1)
        .first;
    await _gen(
        store: store,
        workers: workers,
        schedules: schedules,
        period: preview.period,
        payDate: preview.payDate);
  }

  Future<void> generatePayrollForMonth({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required int year,
    required int month,
  }) async {
    final preview = _engine
        .previewNext(
            policy: store.payrollPolicy,
            from: DateTime(year, month, 15),
            count: 1)
        .first;
    await _gen(
        store: store,
        workers: workers,
        schedules: schedules,
        period: preview.period,
        payDate: preview.payDate);
  }

  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _gen({
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required PayPeriod period,
    required DateTime payDate,
  }) async {
    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    _buildSheet(
      excel: excel,
      store: store,
      workers: workers,
      schedules: schedules,
      period: period,
      payDate: payDate,
    );

    final bytes = excel.encode();
    if (bytes == null) throw Exception('엑셀 생성 실패');

    final dir = await getTemporaryDirectory();
    final fileName =
        '인건비지급명세서_${store.name}_${payDate.year}년${payDate.month}월.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: fileName,
      text: '${store.name} ${payDate.year}년 ${payDate.month}월 인건비 지급명세서입니다.',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 시트 구성
  // ══════════════════════════════════════════════════════════════════════════
  void _buildSheet({
    required Excel excel,
    required Store store,
    required List<StoreWorker> workers,
    required List<StoreSchedule> schedules,
    required PayPeriod period,
    required DateTime payDate,
  }) {
    final sheet = excel['지급명세서'];

    // 컬럼 정의 (0~8)
    // No | 성명 | 주민등록번호 | 근무기간 | 근무일수 | 총근무시간 | 시급 | 지급액 | 공제액 | 실지급액
    const C = 10; // 총 컬럼 수
    const cNo = 0;
    const cName = 1;
    const cRrn = 2; // 주민등록번호 (사장님이 직접 기입)
    const cPeriod = 3;
    const cDays = 4;
    const cHours = 5;
    const cWage = 6;
    const cGross = 7;
    const cDeduct = 8;
    const cNet = 9;

    int row = 0;
    final today = DateTime.now();

    // ─────────────────────────────────────────────────────────────────────
    // 1. 수신인 & 발신인 블록 (사장님이 직접 기입)
    // ─────────────────────────────────────────────────────────────────────
    _c(sheet, row, 0, '수 신:', bold: true, fs: 10, rh: 20);
    _mg(sheet, row, 1, row, C - 1);
    _c(sheet, row, 1, '                                    (세무사 / 담당자명)',
        fs: 10, fc: 'FF999999');
    row++;

    _c(sheet, row, 0, '발 신:', bold: true, fs: 10, rh: 20);
    _mg(sheet, row, 1, row, C - 1);
    _c(sheet, row, 1, store.name, fs: 10);
    row++;

    _c(sheet, row, 0, '날 짜:', bold: true, fs: 10, rh: 20);
    _mg(sheet, row, 1, row, C - 1);
    _c(sheet, row, 1, '${today.year}년 ${today.month}월 ${today.day}일', fs: 10);
    row++;

    sheet.setRowHeight(row, 10);
    row++; // 간격

    // ─────────────────────────────────────────────────────────────────────
    // 2. 제목
    // ─────────────────────────────────────────────────────────────────────
    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '인건비 (P/T) 지급명세서',
        bold: true, fs: 16, ha: HorizontalAlign.Center, rh: 38);
    row++;

    // 점포명 + 급여기간 한 줄
    _mg(sheet, row, 0, row, 4);
    _c(sheet, row, 0, '점포명: ${store.name}', bold: true, fs: 10, rh: 20);
    _mg(sheet, row, 5, row, C - 1);
    _c(
        sheet,
        row,
        5,
        '급여기간: ${_ymd(period.start)} ~ ${_ymd(period.end)}'
        '   지급일: ${_ymd(payDate)}',
        fs: 10);
    row++;

    sheet.setRowHeight(row, 8);
    row++; // 간격

    // ─────────────────────────────────────────────────────────────────────
    // 3. 헤더
    // ─────────────────────────────────────────────────────────────────────
    const hdrs = [
      'No',
      '성  명',
      '주민등록번호\n(사장님 기입)',
      '근무기간',
      '근무\n일수',
      '총근무\n시간',
      '시급(원)',
      '지급액',
      '공제액',
      '실지급액',
    ];
    for (int i = 0; i < hdrs.length; i++) {
      _c(sheet, row, i, hdrs[i],
          bold: true,
          fs: 9,
          bg: 'FFD9E1F2',
          ha: HorizontalAlign.Center,
          rh: 30,
          wrap: true,
          border: true);
    }
    final dataStartRow = row + 1;
    row++;

    // ─────────────────────────────────────────────────────────────────────
    // 4. 직원별 데이터
    // ─────────────────────────────────────────────────────────────────────
    final Map<String, List<StoreSchedule>> byWorker = {};
    for (final s in schedules) {
      final d = DateTime(s.year, s.month, s.day);
      if (!d.isBefore(period.start) && !d.isAfter(period.end)) {
        (byWorker[s.workerUid] ??= []).add(s);
      }
    }

    // 월별 누적용 (월별 합계 섹션에서 사용)
    final Map<String, _MonthTotals> monthTotals = {}; // key: 'YYYY-MM'

    int tDays = 0, tMins = 0, tGross = 0, tDeduct = 0, tNet = 0;
    int no = 1;

    for (final w in workers) {
      if (w.status == 'ended') continue;
      final ws = byWorker[w.workerUid] ?? const [];
      if (ws.isEmpty) continue;

      final wage = _wage(store, w);
      final name = (w.displayName ?? w.workerUid).trim();
      final bg = (no % 2 == 0) ? 'FFF5F8FF' : 'FFFFFFFF';

      if (wage == null) {
        _c(sheet, row, cNo, '$no',
            bg: bg, ha: HorizontalAlign.Center, rh: 20, border: true);
        _c(sheet, row, cName, name, bg: bg, border: true);
        for (int i = 2; i < C; i++) {
          _c(sheet, row, i, '-',
              bg: bg, ha: HorizontalAlign.Center, border: true);
        }
        row++;
        no++;
        continue;
      }

      final tax = _tax(store, w);
      final ins = _ins(store, w);
      final uis = ws.map(_toUI).toList();
      final alba = UICalendarAlba(
        id: w.workerUid,
        storeId: store.id,
        name: name,
        hourlyWage: wage,
        colorHex: '3B82F6',
        payDay: _payDay(store, w),
      );
      final policy = store.payrollPolicy
          .copyWith(payRule: PayDateRule.nextMonthlyDay(_payDay(store, w)));
      final summary = _engine.summaryForDate(
        policy: policy,
        alba: alba,
        schedules: uis,
        tax: tax,
        insurance: ins,
        surchargePolicy: _sur(store, w),
        anyDateInPeriod: period.start,
      );

      final days =
          ws.map((s) => '${s.year}-${s.month}-${s.day}').toSet().length;
      final mins = _sumMins(ws);
      final deduct = summary.gross - summary.net;

      // 근무기간: 첫날 ~ 마지막날
      final sortedDates =
          ws.map((s) => DateTime(s.year, s.month, s.day)).toList()..sort();
      final first = sortedDates.first;
      final last = sortedDates.last;
      final periodStr = '${_md(first)} ~ ${_md(last)}';
      final hoursStr = _hm(mins);

      _c(sheet, row, cNo, '$no',
          bg: bg, ha: HorizontalAlign.Center, rh: 20, border: true);
      _c(sheet, row, cName, name, bg: bg, border: true);
      _c(sheet, row, cRrn, '', bg: 'FFFFFDE7', border: true); // 노란 배경: 기입 필요
      _c(sheet, row, cPeriod, periodStr,
          bg: bg, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, cDays, '$days일',
          bg: bg, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, cHours, hoursStr,
          bg: bg, ha: HorizontalAlign.Center, border: true);
      _c(sheet, row, cWage, _fmt.format(wage),
          bg: bg, ha: HorizontalAlign.Right, border: true);
      _c(sheet, row, cGross, _fmt.format(summary.gross),
          bg: bg, ha: HorizontalAlign.Right, border: true);
      _c(sheet, row, cDeduct, deduct > 0 ? _fmt.format(deduct) : '-',
          bg: bg, ha: HorizontalAlign.Right, border: true);
      _c(sheet, row, cNet, _fmt.format(summary.net),
          bg: bg, ha: HorizontalAlign.Right, bold: true, border: true);

      // 월별 누적
      final monthKey = '${period.start.year}-${_p(period.start.month)}';
      final mt = monthTotals[monthKey] ??=
          _MonthTotals(year: period.start.year, month: period.start.month);
      mt.days += days;
      mt.mins += mins;
      mt.gross += summary.gross;
      mt.deduct += deduct;
      mt.net += summary.net;

      tDays += days;
      tMins += mins;
      tGross += summary.gross;
      tDeduct += deduct;
      tNet += summary.net;

      row++;
      no++;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 5. 이달 합계
    // ─────────────────────────────────────────────────────────────────────
    sheet.setRowHeight(row, 22);
    _c(sheet, row, cNo, '합계',
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Center, border: true);
    _c(sheet, row, cName, '${no - 1}명',
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Center, border: true);
    _c(sheet, row, cRrn, '', bold: true, fs: 10, bg: 'FFD9E1F2', border: true);
    _c(sheet, row, cPeriod, '', bold: true, fs: 10, bg: 'FFD9E1F2', border: true);
    _c(sheet, row, cDays, '$tDays일',
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Center, border: true);
    _c(sheet, row, cHours, _hm(tMins),
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Center, border: true);
    _c(sheet, row, cWage, '', bold: true, fs: 10, bg: 'FFD9E1F2', border: true);
    _c(sheet, row, cGross, _fmt.format(tGross),
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Right, border: true);
    _c(sheet, row, cDeduct, tDeduct > 0 ? _fmt.format(tDeduct) : '-',
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Right, border: true);
    _c(sheet, row, cNet, _fmt.format(tNet),
        bold: true, fs: 10, bg: 'FFD9E1F2', ha: HorizontalAlign.Right, border: true);
    row += 2;

    // ─────────────────────────────────────────────────────────────────────
    // 6. 주민번호 안내 문구
    // ─────────────────────────────────────────────────────────────────────
    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0,
        '※ 주민등록번호 칸(노란색)은 세무 신고 시 직접 기입해 주세요. 앱에서는 개인정보 보호를 위해 수집하지 않습니다.',
        fs: 8, fc: 'FF666666', wrap: true, rh: 28);
    row++;

    // 공제 기준 안내
    final note = _taxNote(workers: workers, store: store, byWorker: byWorker);
    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '※ 공제 기준: $note',
        fs: 8, fc: 'FF666666', wrap: true, rh: 28);
    row += 2;

    // ─────────────────────────────────────────────────────────────────────
    // 7. 월별 합계 섹션
    // ─────────────────────────────────────────────────────────────────────
    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '월별 합계',
        bold: true,
        fs: 11,
        bg: 'FF1C3557',
        fc: 'FFFFFFFF',
        ha: HorizontalAlign.Center,
        rh: 26);
    row++;

    // 월별 헤더
    const mHdrs = ['월', '근무일수', '총근무시간', '', '', '', '지급액', '공제액', '실지급액', ''];
    for (int i = 0; i < mHdrs.length; i++) {
      _c(sheet, row, i, mHdrs[i],
          bold: true,
          fs: 9,
          bg: 'FFD9E1F2',
          ha: HorizontalAlign.Center,
          rh: 20);
    }
    row++;

    // 현재 달 데이터만 있으므로 한 줄 표시
    // (앱에서 한 달씩 불러오므로 월별 합계 = 이달 합계와 동일)
    for (final mt in monthTotals.values.toList()
      ..sort(
          (a, b) => a.year != b.year ? a.year - b.year : a.month - b.month)) {
      _c(sheet, row, 0, '${mt.month}월',
          ha: HorizontalAlign.Center, rh: 20, fs: 9);
      _c(sheet, row, 1, '${mt.days}일', ha: HorizontalAlign.Center, fs: 9);
      _c(sheet, row, 2, _hm(mt.mins), ha: HorizontalAlign.Center, fs: 9);
      _c(sheet, row, 3, '', fs: 9);
      _c(sheet, row, 4, '', fs: 9);
      _c(sheet, row, 5, '', fs: 9);
      _c(sheet, row, 6, _fmt.format(mt.gross),
          ha: HorizontalAlign.Right, fs: 9);
      _c(sheet, row, 7, mt.deduct > 0 ? _fmt.format(mt.deduct) : '-',
          ha: HorizontalAlign.Right, fs: 9);
      _c(sheet, row, 8, _fmt.format(mt.net),
          ha: HorizontalAlign.Right, bold: true, fs: 9);
      _c(sheet, row, 9, '', fs: 9);
      row++;
    }
    row++;

    // ─────────────────────────────────────────────────────────────────────
    // 8. 분기별 총계 섹션
    // ─────────────────────────────────────────────────────────────────────
    _mg(sheet, row, 0, row, C - 1);
    _c(sheet, row, 0, '분기별 총계',
        bold: true,
        fs: 11,
        bg: 'FF1C3557',
        fc: 'FFFFFFFF',
        ha: HorizontalAlign.Center,
        rh: 26);
    row++;

    const qHdrs = [
      '분기',
      '해당 월',
      '근무일수',
      '총근무시간',
      '',
      '',
      '지급액',
      '공제액',
      '실지급액',
      ''
    ];
    for (int i = 0; i < qHdrs.length; i++) {
      _c(sheet, row, i, qHdrs[i],
          bold: true,
          fs: 9,
          bg: 'FFD9E1F2',
          ha: HorizontalAlign.Center,
          rh: 20);
    }
    row++;

    // 분기별로 그룹핑 (현재 데이터 기준)
    final Map<int, _MonthTotals> quarterTotals = {};
    for (final mt in monthTotals.values) {
      final q = ((mt.month - 1) ~/ 3) + 1;
      final qt = quarterTotals[q] ??=
          _MonthTotals(year: mt.year, month: q); // month 필드를 분기 번호로 재활용
      qt.days += mt.days;
      qt.mins += mt.mins;
      qt.gross += mt.gross;
      qt.deduct += mt.deduct;
      qt.net += mt.net;
    }

    final qMonths = {1: '1월~3월', 2: '4월~6월', 3: '7월~9월', 4: '10월~12월'};
    for (int q = 1; q <= 4; q++) {
      final qt = quarterTotals[q];
      final label = '${period.start.year}년 ${q}분기';
      final months = qMonths[q] ?? '';
      if (qt == null) {
        _c(sheet, row, 0, label,
            ha: HorizontalAlign.Center, fs: 9, fc: 'FFAAAAAA', rh: 20);
        _c(sheet, row, 1, months,
            ha: HorizontalAlign.Center, fs: 9, fc: 'FFAAAAAA');
        _c(sheet, row, 2, '-',
            ha: HorizontalAlign.Center, fs: 9, fc: 'FFAAAAAA');
        _c(sheet, row, 3, '-',
            ha: HorizontalAlign.Center, fs: 9, fc: 'FFAAAAAA');
        _c(sheet, row, 4, '', fs: 9);
        _c(sheet, row, 5, '', fs: 9);
        _c(sheet, row, 6, '-',
            ha: HorizontalAlign.Right, fs: 9, fc: 'FFAAAAAA');
        _c(sheet, row, 7, '-',
            ha: HorizontalAlign.Right, fs: 9, fc: 'FFAAAAAA');
        _c(sheet, row, 8, '-',
            ha: HorizontalAlign.Right, fs: 9, fc: 'FFAAAAAA');
        _c(sheet, row, 9, '', fs: 9);
      } else {
        _c(sheet, row, 0, label,
            ha: HorizontalAlign.Center, fs: 9, bold: true, rh: 20);
        _c(sheet, row, 1, months, ha: HorizontalAlign.Center, fs: 9);
        _c(sheet, row, 2, '${qt.days}일', ha: HorizontalAlign.Center, fs: 9);
        _c(sheet, row, 3, _hm(qt.mins), ha: HorizontalAlign.Center, fs: 9);
        _c(sheet, row, 4, '', fs: 9);
        _c(sheet, row, 5, '', fs: 9);
        _c(sheet, row, 6, _fmt.format(qt.gross),
            ha: HorizontalAlign.Right, bold: true, fs: 9);
        _c(sheet, row, 7, qt.deduct > 0 ? _fmt.format(qt.deduct) : '-',
            ha: HorizontalAlign.Right, fs: 9);
        _c(sheet, row, 8, _fmt.format(qt.net),
            ha: HorizontalAlign.Right, bold: true, fs: 9);
        _c(sheet, row, 9, '', fs: 9);
      }
      row++;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 9. 서명란
    // ─────────────────────────────────────────────────────────────────────
    row++;
    _c(sheet, row, 0, '위와 같이 인건비를 지급하였음을 확인합니다.', fs: 10, rh: 20);
    row += 2;
    _c(sheet, row, 0, '사업주:');
    _mg(sheet, row, 1, row, 3);
    _c(sheet, row, 1, '', fs: 10);
    _c(sheet, row, 4, '(인/서명)', fs: 10);
    sheet.setRowHeight(row, 22);
    row++;
    _c(sheet, row, 0, '담당자:');
    _mg(sheet, row, 1, row, 3);
    _c(sheet, row, 1, '', fs: 10);
    _c(sheet, row, 4, '(인/서명)', fs: 10);
    sheet.setRowHeight(row, 22);

    // ─────────────────────────────────────────────────────────────────────
    // 컬럼 너비
    // ─────────────────────────────────────────────────────────────────────
    const widths = [5.0, 10.0, 17.0, 14.0, 7.0, 10.0, 11.0, 12.0, 10.0, 12.0];
    for (int i = 0; i < widths.length; i++) sheet.setColumnWidth(i, widths[i]);

    // 데이터 행 높이
    for (int r = dataStartRow; r < dataStartRow + (no - 1); r++) {
      sheet.setRowHeight(r, 20);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 셀 헬퍼
  // ══════════════════════════════════════════════════════════════════════════
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
    final thin =
        border ? Border(borderStyle: BorderStyle.Thin) : null;
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

  String _p(int n) => n.toString().padLeft(2, '0');
  String _ymd(DateTime d) => '${d.year}.${_p(d.month)}.${_p(d.day)}';
  String _md(DateTime d) => '${d.month}.${d.day}';
  String _hm(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}시간' : '${h}시간 ${m}분';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 계산 헬퍼
  // ══════════════════════════════════════════════════════════════════════════
  String _taxNote(
      {required List<StoreWorker> workers,
      required Store store,
      required Map<String, List<StoreSchedule>> byWorker}) {
    final notes = <String>{};
    for (final w in workers) {
      if (w.status == 'ended') continue;
      if ((byWorker[w.workerUid] ?? []).isEmpty) continue;
      final t = _tax(store, w);
      final i = _ins(store, w);
      if (t == TaxConfig.biz33) notes.add('소득세 3.3%');
      if (t == TaxConfig.day66) notes.add('소득세 6.6%');
      if (i is InsuranceEmploymentOnly) notes.add('고용보험 0.9%');
      if (i is InsuranceFour) notes.add('4대보험 9.4%');
    }
    if (notes.isEmpty) return '공제 없음';
    return notes.join(' / ');
  }

  int? _wage(Store s, StoreWorker w) {
    if (w.inheritFromStore) return s.defaultHourlyWage ?? w.hourlyWage;
    return w.hourlyWage ?? s.defaultHourlyWage;
  }

  int _payDay(Store s, StoreWorker w) => w.payDay ?? s.payDay ?? 25;
  TaxConfig _tax(Store s, StoreWorker w) {
    if (w.policyOverride != null)
      return pm.taxConfigFromPolicy(w.policyOverride!);
    return pm.taxConfigFromPolicy(s.policy ?? {});
  }

  InsuranceConfig _ins(Store s, StoreWorker w) {
    if (w.policyOverride != null)
      return pm.insuranceConfigFromPolicy(w.policyOverride!);
    return pm.insuranceConfigFromPolicy(s.policy ?? {});
  }

  SurchargePolicy _sur(Store s, StoreWorker w) {
    if (w.policyOverride != null)
      return pm.surchargePolicyFromPolicy(w.policyOverride!);
    return pm.surchargePolicyFromPolicy(s.policy ?? {});
  }

  /// ✅ 에러 수정: StoreSchedule.workType 은 String → WorkType enum 으로 변환
  UICalendarSchedule _toUI(StoreSchedule s) {
    WorkType wt;
    switch (s.workType) {
      case 'substitute':
        wt = WorkType.substitute;
        break;
      case 'night':
        wt = WorkType.night;
        break;
      case 'overtime':
        wt = WorkType.overtime;
        break;
      case 'holiday':
        wt = WorkType.holiday;
        break;
      default:
        wt = WorkType.basic;
    }
    return UICalendarSchedule(
      id: s.id,
      albaId: s.workerUid,
      year: s.year,
      month: s.month,
      day: s.day,
      startHour: s.startHour,
      startMinute: s.startMinute,
      endHour: s.endHour,
      endMinute: s.endMinute,
      breakMinutes: s.breakMinutes,
      workType: wt,
      overrideHourlyWage: s.overrideHourlyWage,
    );
  }

  int _sumMins(List<StoreSchedule> schedules) {
    int total = 0;
    for (final s in schedules) {
      final start =
          DateTime(s.year, s.month, s.day, s.startHour, s.startMinute);
      var end = DateTime(s.year, s.month, s.day, s.endHour, s.endMinute);
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      total += (end.difference(start).inMinutes - s.breakMinutes.clamp(0, 1440))
          .clamp(0, 24 * 60);
    }
    return total;
  }
}

// 월별/분기별 합계 누적 데이터 클래스
class _MonthTotals {
  final int year;
  final int month;
  int days = 0, mins = 0, gross = 0, deduct = 0, net = 0;
  _MonthTotals({required this.year, required this.month});
}
