// lib/screens/owner/owner_worker_schedule_screen.dart
import 'package:flutter/material.dart';

import '../../data/firebase_service.dart';
import '../../models/store_schedule.dart';
import '../../models/store_worker.dart';

class OwnerWorkerScheduleScreen extends StatelessWidget {
  const OwnerWorkerScheduleScreen({
    super.key,
    required this.ownerUid,
    required this.storeId,
    required this.storeName,
    required this.worker,
  });

  final String ownerUid;
  final String storeId;
  final String storeName;
  final StoreWorker worker;

  String _displayName(StoreWorker w) {
    final dn = (w.displayName ?? '').trim();
    return dn.isEmpty ? w.workerUid : dn;
  }

  String _hm(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final repo = FirebaseService();
    final displayName = _displayName(worker);

    return Scaffold(
      appBar: AppBar(
        title: Text('$displayName 근무'),
        centerTitle: false,
      ),
      body: StreamBuilder<List<StoreSchedule>>(
        stream: repo.watchSchedulesForWorkerReadOnly(
          ownerUid: ownerUid,
          storeId: storeId,
          workerUid: worker.workerUid,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('불러오기 실패: ${snapshot.error}'),
            );
          }

          final items = snapshot.data ?? const <StoreSchedule>[];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$storeName에서 아직 등록된 근무 일정이 없어요.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          // ✅ 날짜별 그룹(ymd 기준)
          final groups = <String, List<StoreSchedule>>{};
          for (final s in items) {
            groups.putIfAbsent(s.ymd, () => []).add(s);
          }

          final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: keys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final ymd = keys[i];
              final list = [...groups[ymd]!]..sort((a, b) {
                  final am = a.startHour * 60 + a.startMinute;
                  final bm = b.startHour * 60 + b.startMinute;
                  return am.compareTo(bm);
                });

              return _DayCard(ymd: ymd, schedules: list, hm: _hm);
            },
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.ymd,
    required this.schedules,
    required this.hm,
  });

  final String ymd;
  final List<StoreSchedule> schedules;
  final String Function(int h, int m) hm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ymd,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final s in schedules) ...[
            _ScheduleRow(s: s, hm: hm),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.s,
    required this.hm,
  });

  final StoreSchedule s;
  final String Function(int h, int m) hm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final start = hm(s.startHour, s.startMinute);
    final end = hm(s.endHour, s.endMinute);

    final nextDay =
        (s.endHour * 60 + s.endMinute) <= (s.startHour * 60 + s.startMinute)
            ? ' (다음날)'
            : '';

    final breakText = s.breakMinutes > 0 ? ' · 휴게 ${s.breakMinutes}분' : '';

    return Row(
      children: [
        Expanded(
          child: Text(
            '$start ~ $end$nextDay$breakText',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          s.workType,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
