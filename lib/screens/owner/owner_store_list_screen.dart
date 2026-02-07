import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/store_repository.dart';
import '../../models/store.dart';
import '../../common/ui/async_state_views.dart';
import '../../common/ui/bottom_cta.dart';

import 'owner_store_form_screen.dart';
import 'owner_store_detail_screen.dart';

class OwnerStoreListScreen extends StatelessWidget {
  const OwnerStoreListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인이 필요해요.')),
      );
    }

    final repo = StoreRepository();

    return Scaffold(
      appBar: AppBar(
        title: const Text('매장'),
        centerTitle: false,
      ),
      body: StreamBuilder<List<Store>>(
        stream: repo.watchStores(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingView();
          }

          if (snapshot.hasError) {
            return AppErrorView(
              title: '불러오기 실패',
              message: '${snapshot.error}',
              onRetry: () => (context as Element).markNeedsBuild(),
            );
          }

          final stores = snapshot.data ?? const <Store>[];
          if (stores.isEmpty) {
            return AppEmptyView(
              icon: Icons.storefront,
              title: '매장이 없어요',
              message: '+ 버튼을 눌러 추가하세요.',
              action: FilledButton.icon(
                onPressed: () => _openCreate(context),
                icon: const Icon(Icons.add),
                label: const Text('매장 추가'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: stores.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = stores[i];
              return _StoreCard(
                store: s,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OwnerStoreDetailScreen(store: s),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: BottomCta(
        onPressed: () => _openCreate(context),
        icon: Icons.add,
        label: '매장 추가',
      ),
    );
  }

  Future<void> _openCreate(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OwnerStoreFormScreen()),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onTap});
  final Store store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final wageText = store.defaultHourlyWage == null
        ? ''
        : ' · 시급 ${_comma(store.defaultHourlyWage!)}원';

    final payDayText = store.payDay == null ? '' : ' · ${store.payDay}일';

    return Material(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '내 매장$wageText$payDayText',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

String _comma(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    b.write(s[i]);
    final left = s.length - i - 1;
    if (left > 0 && left % 3 == 0) b.write(',');
  }
  return b.toString();
}
