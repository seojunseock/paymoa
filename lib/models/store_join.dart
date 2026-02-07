import 'package:cloud_firestore/cloud_firestore.dart';

class StoreJoin {
  final String id; // ownerUid_storeId
  final String workerUid;

  final String ownerUid;
  final String storeId;
  final String storeName;
  final String storeCode;

  final bool inheritFromStore;

  final DateTime? joinedAt;
  final DateTime? updatedAt;

  const StoreJoin({
    required this.id,
    required this.workerUid,
    required this.ownerUid,
    required this.storeId,
    required this.storeName,
    required this.storeCode,
    required this.inheritFromStore,
    this.joinedAt,
    this.updatedAt,
  });

  static StoreJoin fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final Timestamp? joinedAtTs = d['joinedAt'] as Timestamp?;
    final Timestamp? updatedAtTs = d['updatedAt'] as Timestamp?;

    return StoreJoin(
      id: doc.id,
      workerUid: (d['workerUid'] as String?) ?? '',
      ownerUid: (d['ownerUid'] as String?) ?? '',
      storeId: (d['storeId'] as String?) ?? '',
      storeName: (d['storeName'] as String?) ?? '',
      storeCode: (d['storeCode'] as String?) ?? '',
      inheritFromStore: (d['inheritFromStore'] as bool?) ?? true,
      joinedAt: joinedAtTs?.toDate(),
      updatedAt: updatedAtTs?.toDate(),
    );
  }
}
