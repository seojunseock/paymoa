import 'package:flutter/material.dart';

import '../models/ui_calendar_models.dart';
import '../common/common_pickers.dart' as cp;
import '../policies/policies.dart' as pol; // 네임스페이스만 필요
import 'date_assign_sheet.dart';
import 'work_editor_args.dart' as wargs;

/* ───────────────────────── 내부 모델(편집 묶음) ───────────────────────── */

class _WorkGroup {
  _WorkGroup({
    this.existingScheduleId, // null이면 신규
    required this.albaId,
    required this.selectedUtcDates,
    required this.startH,
    required this.startM,
    required this.endH,
    required this.endM,
    required this.breakMin,
  });

  String? existingScheduleId; // 수정 모드일 때 연결된 스케줄 id
  String albaId;

  /// 달력 선택: UTC 00:00 날짜들
  Set<DateTime> selectedUtcDates;

  int startH, startM, endH, endM;
  int breakMin;
}

/* ───────────────────────── 시간 병합용 작은 구조체 ───────────────────────── */

class _Seg {
  _Seg(this.startMin, this.endMin, this.breakMin);

  /// 기준 날짜 자정(로컬)부터의 분
  int startMin;
  /// end가 start보다 작거나 같으면 익일로 간주해 24*60을 더해 둔다.
  int endMin;
  int breakMin;
}

/* ───────────────────────── 화면 ───────────────────────── */

class WorkEditorScreen extends StatefulWidget {
  const WorkEditorScreen({
    super.key,
    required this.args,
    required this.albas,
    required this.schedules,
    required this.getSurchargePolicy,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
    required this.onBack,
  });

  final wargs.WorkEditorArgs args;
  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;

  final pol.SurchargePolicy? Function(String albaId) getSurchargePolicy;

  /// 저장 콜백들(Repo는 AppShell 쪽)
  final void Function(UICalendarSchedule s) onAdd;
  final void Function(UICalendarSchedule s) onUpdate;
  final void Function(String scheduleId) onDelete;

  final VoidCallback onBack;

  @override
  State<WorkEditorScreen> createState() => _WorkEditorScreenState();
}

class _WorkEditorScreenState extends State<WorkEditorScreen> {
  late final bool isEdit = widget.args.mode == wargs.WorkEditorArgsMode.edit;

  final List<_WorkGroup> _groups = [];
  String? _error;

  UICalendarSchedule? _findById(String id) {
    for (final s in widget.schedules) {
      if (s.id == id) return s;
    }
    return null;
  }

  DateTime? get _presetLocal => widget.args.presetDate;

  String get _title {
    final d = _presetLocal;
    if (d != null) return '${d.month}/${d.day} 근무 설정';
    return '근무 설정';
  }

  @override
  void initState() {
    super.initState();

    if (isEdit && widget.args.scheduleId != null) {
      // 편집 모드: 해당 스케줄 1개 카드
      final s = _findById(widget.args.scheduleId!);
      if (s != null) {
        _groups.add(_WorkGroup(
          existingScheduleId: s.id,
          albaId: s.albaId,
          selectedUtcDates: {DateTime.utc(s.year, s.month, s.day)},
          startH: s.startHour,
          startM: s.startMinute,
          endH: s.endHour,
          endM: s.endMinute,
          breakMin: s.breakMinutes,
        ));
      }
    } else {
      // 추가 모드
      final d = _presetLocal;
      if (d != null) {
        // 달력에서 빈 날짜를 눌러 들어온 경우에는 기본 카드 없이 시작
        final hasAny = widget.schedules.any(
          (s) => s.year == d.year && s.month == d.month && s.day == d.day,
        );
        if (!hasAny) {
          // 비어 있는 날짜 → 카드 생성 안 함(“근무 추가”만 보임)
        } else {
          _addGroup(initialDate: d); // 혹시라도 스케줄이 있으면 기본 1개
        }
      } else {
        // 프리셋 날짜가 없을 때만 1개 기본 카드 생성(기존 동작 유지)
        _addGroup(initialDate: DateTime.now());
      }
    }
  }

  /* ─────────────── 공용 유틸 ─────────────── */

  UICalendarAlba? _albaById(String id) {
    for (final a in widget.albas) {
      if (a.id == id) return a;
    }
    return null;
  }

  Color _albaColor(String albaId) {
    final a = _albaById(albaId);
    if (a == null) return Theme.of(context).colorScheme.outlineVariant;
    return cp.parseColor(a.colorHex);
  }

  String _ymd(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  /* ─────────────── 충돌 검사(기존+화면 내 다른 묶음 포함) ─────────────── */

  bool _conflictFor(int groupIndex, DateTime dLocal) {
    final g = _groups[groupIndex];

    final sMin0 = g.startH * 60 + g.startM;
    var eMin0 = g.endH * 60 + g.endM;
    final overnight = eMin0 <= sMin0;
    if (overnight) eMin0 += 24 * 60;

    bool _rangeOverlapListFromExisting(List<UICalendarSchedule> list, int dayOffset) {
      for (final sc in list) {
        if (g.existingScheduleId != null && sc.id == g.existingScheduleId) continue; // 자기 자신 제외
        var a = sc.startHour * 60 + sc.startMinute + dayOffset * 24 * 60;
        var b = sc.endHour * 60 + sc.endMinute + dayOffset * 24 * 60;
        if (b <= a) b += 24 * 60;
        if (sMin0 < b && a < eMin0) return true;
      }
      return false;
    }

    bool _rangeOverlapWithOtherGroups(DateTime base, int dayOffset) {
      final targetUtc = DateTime.utc(base.year, base.month, base.day + dayOffset);
      for (int j = 0; j < _groups.length; j++) {
        if (j == groupIndex) continue;
        final og = _groups[j];
        // 다른 묶음이 해당 날짜(또는 전/익일)에 선택돼 있을 때만 비교
        if (!og.selectedUtcDates.contains(targetUtc)) continue;

        var a = og.startH * 60 + og.startM + dayOffset * 24 * 60;
        var b = og.endH * 60 + og.endM + dayOffset * 24 * 60;
        if (b <= a) b += 24 * 60;
        if (sMin0 < b && a < eMin0) return true;
      }
      return false;
    }

    List<UICalendarSchedule> _byYmd(DateTime x) =>
        widget.schedules.where((it) => it.year == x.year && it.month == x.month && it.day == x.day).toList();

    final prev = DateTime(dLocal.year, dLocal.month, dLocal.day - 1);
    final next = DateTime(dLocal.year, dLocal.month, dLocal.day + 1);

    final sameList = _byYmd(dLocal);
    final prevList = _byYmd(prev);
    final nextList = _byYmd(next);

    final existingHit = _rangeOverlapListFromExisting(sameList, 0) ||
        _rangeOverlapListFromExisting(prevList, -1) ||
        _rangeOverlapListFromExisting(nextList, 1);

    final othersHit = _rangeOverlapWithOtherGroups(dLocal, 0) ||
        _rangeOverlapWithOtherGroups(dLocal, -1) ||
        _rangeOverlapWithOtherGroups(dLocal, 1);

    return existingHit || othersHit;
  }

  /// 저장 직전 전체 묶음/날짜에 대해 충돌 수집
  Map<int, List<DateTime>> _collectConflicts() {
    final map = <int, List<DateTime>>{};
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      for (final dUtc in g.selectedUtcDates) {
        final dLocal = DateTime(dUtc.year, dUtc.month, dUtc.day);
        if (_conflictFor(i, dLocal)) {
          (map[i] ??= <DateTime>[]).add(dLocal);
        }
      }
    }
    return map;
  }

  Future<bool?> _showConflictDialog(Map<int, List<DateTime>> conf) {
    // 보기 좋게 그룹/날짜 정렬
    final entries = conf.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('겹치는 날짜가 있어요'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((e) {
                  final g = _groups[e.key];
                  final albaName = _albaById(g.albaId)?.name ?? '알바';
                  final days = (e.value..sort((a, b) => a.compareTo(b)))
                      .map((d) => '• ${_ymd(d)}')
                      .join('\n');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('$albaName\n$days'),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('수정하러 가기'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('그대로 저장'),
            ),
          ],
        );
      },
    );
  }

  /* ─────────────── 이벤트 ─────────────── */

  void _addGroup({DateTime? initialDate}) {
    final firstAlba = widget.albas.isNotEmpty ? widget.albas.first.id : '';
    final d = initialDate ?? _presetLocal ?? DateTime.now();
    setState(() {
      _groups.add(_WorkGroup(
        existingScheduleId: null,
        albaId: firstAlba,
        selectedUtcDates: {DateTime.utc(d.year, d.month, d.day)},
        startH: 9,
        startM: 0,
        endH: 18,
        endM: 0,
        breakMin: 0,
      ));
    });
  }

  void _removeGroupAt(int i) {
    final g = _groups[i];
    if (g.existingScheduleId != null) {
      // 실제 스케줄 삭제
      widget.onDelete(g.existingScheduleId!);
    }
    setState(() {
      _groups.removeAt(i);
    });
    // 카드가 하나도 없을 때는 그대로 빈 화면 유지(요구사항: 근무 추가 버튼만)
  }

  Future<void> _openDateAssignFor(int i) async {
    final res = await showDateAssignSheet(
      context,
      existing: _groups[i].selectedUtcDates,
      checkConflict: (utc) => _conflictFor(i, DateTime(utc.year, utc.month, utc.day)),
    );
    if (res != null) {
      setState(() {
        // 편집 묶음이어도 다중 선택 허용(저장은 병합 로직으로 처리)
        _groups[i].selectedUtcDates = res.selectedDates.toSet();
        _error = null;
      });
    }
  }

  Future<void> _openTimePickerFor(int i) async {
    final g = _groups[i];
    await cp.showTimeSheet(
      context: context,
      startH: g.startH,
      startM: g.startM,
      endH: g.endH,
      endM: g.endM,
      onDone: (sh, sm, eh, em) {
        setState(() {
          g.startH = sh;
          g.startM = sm;
          g.endH = eh;
          g.endM = em;
        });
      },
    );
  }

  Future<void> _openBreakPickerFor(int i) async {
    final g = _groups[i];
    await cp.showBreakSheet(
      context: context,
      initialMinutes: g.breakMin,
      onDone: (m) => setState(() => g.breakMin = m),
    );
  }

  /* ─────────────── 병합 · 저장 ─────────────── */

  // 키: albaId|yyyy-mm-dd
  String _keyOf(String albaId, int y, int m, int d) =>
      '$albaId|$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

  Future<void> _onPressSave() async {
    // 간단 유효성
    for (int i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      if (g.albaId.isEmpty) {
        setState(() => _error = '${i + 1}번째 묶음: 알바를 선택하세요.');
        return;
      }
      if (g.selectedUtcDates.isEmpty) {
        setState(() => _error = '${i + 1}번째 묶음: 근무 날짜를 선택하세요.');
        return;
      }
    }

    // 충돌 수집 → 팝업
    final conflicts = _collectConflicts();
    if (conflicts.isNotEmpty) {
      final proceed = await _showConflictDialog(conflicts);
      if (proceed != true) return; // “수정하러 가기”
    }
    _saveAll(); // “그대로 저장” → 병합/대체 저장
  }

  void _saveAll() {
    // 1) 이번 저장으로 영향 받는 키 수집(원래 키 포함)
    final affectedKeys = <String>{};
    final editedOriginalKeys = <String>{}; // 편집 전 원래 키(날짜 변경 가능)
    for (final g in _groups) {
      for (final d in g.selectedUtcDates) {
        affectedKeys.add(_keyOf(g.albaId, d.year, d.month, d.day));
      }
      if (g.existingScheduleId != null) {
        final s = _findById(g.existingScheduleId!);
        if (s != null) {
          editedOriginalKeys.add(_keyOf(s.albaId, s.year, s.month, s.day));
        }
      }
    }
    affectedKeys.addAll(editedOriginalKeys);

    // 2) 키별로 기존 스케줄 → 세그먼트 수집
    final map = <String, List<_Seg>>{};
    void addSeg(String key, _Seg seg) {
      map.putIfAbsent(key, () => <_Seg>[]).add(seg);
    }

    // 기존 스케줄(편집 중인 건 일단 제외, 아래서 새 값으로 다시 넣음)
    for (final sc in widget.schedules) {
      final key = _keyOf(sc.albaId, sc.year, sc.month, sc.day);
      if (!affectedKeys.contains(key)) continue;
      bool skip = false;
      for (final g in _groups) {
        if (g.existingScheduleId != null && g.existingScheduleId == sc.id) {
          skip = true;
          break;
        }
      }
      if (skip) continue;

      final s0 = sc.startHour * 60 + sc.startMinute;
      var e0 = sc.endHour * 60 + sc.endMinute;
      if (e0 <= s0) e0 += 24 * 60; // 오버나이트 보정
      addSeg(key, _Seg(s0, e0, sc.breakMinutes));
    }

    // 이번에 저장할 묶음 → 세그먼트로 추가
    for (final g in _groups) {
      for (final d in g.selectedUtcDates) {
        final key = _keyOf(g.albaId, d.year, d.month, d.day);
        final s0 = g.startH * 60 + g.startM;
        var e0 = g.endH * 60 + g.endM;
        if (e0 <= s0) e0 += 24 * 60;
        addSeg(key, _Seg(s0, e0, g.breakMin));
      }
    }

    // 3) 키별 세그먼트 병합 (연속/겹침이면 합치고, 1분이라도 띄면 분리)
    List<_Seg> _merge(List<_Seg> list) {
      if (list.isEmpty) return list;
      list.sort((a, b) => a.startMin.compareTo(b.startMin));
      final out = <_Seg>[];
      var cur = _Seg(list.first.startMin, list.first.endMin, list.first.breakMin);
      for (int i = 1; i < list.length; i++) {
        final s = list[i];
        if (s.startMin <= cur.endMin) {
          // 이어지거나 겹치면 병합
          cur.endMin = (s.endMin > cur.endMin) ? s.endMin : cur.endMin;
          cur.breakMin += s.breakMin; // 휴게는 합산
        } else {
          out.add(cur);
          cur = _Seg(s.startMin, s.endMin, s.breakMin);
        }
      }
      out.add(cur);
      return out;
    }

    // 4) 실제 저장: 해당 키의 기존 스케줄 전부 삭제 → 병합 결과로 재생성
    for (final key in affectedKeys) {
      // key 파싱
      final parts = key.split('|');
      final albaId = parts[0];
      final ymd = parts[1].split('-');
      final y = int.parse(ymd[0]);
      final m = int.parse(ymd[1]);
      final d = int.parse(ymd[2]);

      // 삭제
      for (final sc in widget.schedules) {
        if (sc.albaId == albaId && sc.year == y && sc.month == m && sc.day == d) {
          widget.onDelete(sc.id);
        }
      }

      // 병합 결과로 재생성
      final merged = _merge(map[key] ?? const <_Seg>[]);
      for (final seg in merged) {
        final startMin = seg.startMin;
        final endMin = seg.endMin;

        final startH = (startMin ~/ 60) % 24;
        final startM = startMin % 60;

        final endMinNorm = endMin % (24 * 60);
        final endH = (endMinNorm ~/ 60) % 24;
        final endM = endMinNorm % 60;

        widget.onAdd(UICalendarSchedule(
          id: '',
          albaId: albaId,
          year: y,
          month: m,
          day: d,
          startHour: startH,
          startMinute: startM,
          endHour: endH,
          endMinute: endM,
          breakMinutes: seg.breakMin,
        ));
      }
    }

    widget.onBack();
  }

  /* ─────────────── UI ─────────────── */

  String _datesLabel(Set<DateTime> set) {
    if (set.isEmpty) return '없음';
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    if (list.length == 1) {
      final d = list.first;
      return _ymd(d);
    }
    return '${list.length}일';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: widget.onBack, child: const Text('뒤로')),
        title: Text(_title),
        centerTitle: true,
        actions: [
          TextButton(onPressed: _onPressSave, child: const Text('저장')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 상단: 근무 추가 버튼(가로 전체)
          FilledButton.icon(
            onPressed: () => _addGroup(),
            icon: const Icon(Icons.add),
            label: const Text('근무 추가'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),

          // 묶음 리스트 (없으면 버튼만 보이게)
          ...List.generate(_groups.length, (i) {
            final g = _groups[i];
            final borderColor = _albaColor(g.albaId);
            final timePreview =
                '${cp.fmtAmPm(g.startH, g.startM)} ~ ${cp.fmtAmPm(g.endH, g.endM)}'
                '${((g.endH * 60 + g.endM) <= (g.startH * 60 + g.startM)) ? " (다음날)" : ""}';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 1.5),
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.25),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    // 카드 헤더(우측 삭제)
                    Row(
                      children: [
                        Text(
                          g.existingScheduleId == null ? '신규 근무' : '기존 근무 수정',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _removeGroupAt(i),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 알바 선택
                    DropdownButtonFormField<String>(
                      value: g.albaId.isEmpty ? null : g.albaId,
                      items: widget.albas
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => g.albaId = v ?? ''),
                      decoration: const InputDecoration(labelText: '알바 선택'),
                    ),
                    const SizedBox(height: 12),

                    // 근무 날짜
                    Row(
                      children: [
                        Text('근무 날짜', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(onPressed: () => _openDateAssignFor(i), child: const Text('날짜 선택')),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '선택: ${_datesLabel(g.selectedUtcDates)}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 근무 시간
                    Row(
                      children: [
                        Text('근무시간', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(onPressed: () => _openTimePickerFor(i), child: const Text('시간 선택')),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '선택: $timePreview',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 휴게시간
                    Row(
                      children: [
                        Text('휴게시간', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(onPressed: () => _openBreakPickerFor(i), child: const Text('설정')),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '선택: ${g.breakMin}분',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
