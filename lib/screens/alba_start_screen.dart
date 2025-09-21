import 'package:flutter/material.dart';

import '../models/ui_calendar_models.dart';
import '../common/common_pickers.dart' as cp;
import 'work_editor_args.dart' as wargs;

class AlbaStartScreen extends StatefulWidget {
  const AlbaStartScreen({
    super.key,
    required this.albas,
    required this.schedules,
    required this.onBack, // 현재는 미사용
    required this.onGoToAlbaForm,
    required this.onEditAlba,
    required this.onOpenWorkEditor,
    this.getTaxPolicy,
    this.getInsurancePolicy,
    this.getSurchargePolicy,
  });

  final List<UICalendarAlba> albas;
  final List<UICalendarSchedule> schedules;
  final VoidCallback onBack;
  final VoidCallback onGoToAlbaForm;
  final void Function(String albaId) onEditAlba;
  final void Function(wargs.WorkEditorArgs) onOpenWorkEditor;

  // 선택: 세후 계산을 위해 전달 가능
  final Object? Function(String albaId)? getTaxPolicy;
  final Object? Function(String albaId)? getInsurancePolicy;
  final Object? Function(String albaId)? getSurchargePolicy;

  @override
  State<AlbaStartScreen> createState() => _AlbaStartScreenState();
}

class _AlbaStartScreenState extends State<AlbaStartScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ⬇️ 상단 타이틀/뒤로 제거, 오른쪽에 '알바 등록'만 둡니다.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: null,
        actions: [
          TextButton(
            onPressed: widget.onGoToAlbaForm,
            child: const Text('알바 등록'),
          ),
        ],
      ),
      body: widget.albas.isEmpty
          ? const _EmptyView()
          : ListView.builder(
              itemCount: widget.albas.length,
              itemBuilder: (context, index) {
                final alba = widget.albas[index];
                final todayGross = _calcGrossUntilToday(alba, widget.schedules);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ExpansionTile(
                    key: PageStorageKey(alba.id),
                    leading: CircleAvatar(backgroundColor: cp.parseColor(alba.colorHex)),
                    title: Text(alba.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('오늘까지 급여 ${_won(todayGross)}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => widget.onEditAlba(alba.id),
                              child: const Text('수정'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => widget.onOpenWorkEditor(
                                wargs.WorkEditorArgs(
                                  mode: wargs.WorkEditorArgsMode.add,
                                  preselectedAlbaId: alba.id,
                                ),
                              ),
                              child: const Text('근무 추가'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('시급', _won(alba.hourlyWage.toDouble())),
                            _kv('급여일', '${alba.payDay}일'),
                            // 정책 표시가 필요하면 여기에 연결 가능
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  double _calcGrossUntilToday(UICalendarAlba alba, List<UICalendarSchedule> all) {
    final now = DateTime.now();
    final targets = all.where((s) {
      if (s.albaId != alba.id) return false;
      final d = DateTime(s.year, s.month, s.day);
      return !d.isAfter(DateTime(now.year, now.month, now.day));
    });

    double gross = 0;
    for (final s in targets) {
      final minutes = _workedMinutes(s);
      final wage = (s.overrideHourlyWage ?? alba.hourlyWage).toDouble();
      gross += (minutes / 60.0) * wage;
    }
    return gross;
  }

  int _workedMinutes(UICalendarSchedule s) {
    final start = Duration(hours: s.startHour, minutes: s.startMinute);
    var end = Duration(hours: s.endHour, minutes: s.endMinute);
    var diff = end - start;
    if (diff.isNegative) {
      diff += const Duration(days: 1);
    }
    final worked = diff.inMinutes - (s.breakMinutes).clamp(0, diff.inMinutes);
    return worked.clamp(0, 24 * 60);
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(v, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  String _won(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final revIdx = s.length - 1 - i;
      buf.write(s[revIdx]);
      if (i % 3 == 2 && i != s.length - 1) buf.write(',');
    }
    final r = buf.toString().split('').reversed.join();
    return '$r원';
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.work_outline, size: 64),
            const SizedBox(height: 12),
            const Text('등록된 알바가 없습니다.'),
            const SizedBox(height: 8),
            Text(
              '오른쪽 상단의 “알바 등록” 버튼을 눌러 시작해 보세요.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
