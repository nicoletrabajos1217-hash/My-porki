import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, String> _collections = {
    'sows': 'cerdas',
    'births': 'partos', 
    'pregnancies': 'preñeces',
    'users': 'usuarios'
  };

  Future<void> syncLocalData() async {
    try {
      final box = await Hive.openBox('porki_data');
      final localKeys = box.keys.toList();

      for (var key in localKeys) {
        await _syncRecord(key, box);
      }
      
      await _syncFromFirebaseToLocal();
      
      print('🔄 Sincronización completada');
    } catch (e) {
      print('❌ Error en sincronización general: $e');
    }
  }

  Future<void> _syncRecord(String key, Box box) async {
    try {
      final data = box.get(key);
      
      if (data != null && data is Map) {
        final recordData = Map<String, dynamic>.from(data);
        final collection = _getCollectionType(recordData);
        final String docId = recordData['localId'] ?? key;

        await _firestore
            .collection(collection)
            .doc(docId)
            .set(recordData, SetOptions(merge: true));

        await box.delete(key);
        print('✅ $collection sincronizado: $docId');
      }
    } catch (e) {
      print('❌ Error sincronizando $key: $e');
    }
  }

  Future<void> _syncFromFirebaseToLocal() async {
    try {
      final box = await Hive.openBox('porki_data');
      
      for (final collection in _collections.values) {
        final snapshot = await _firestore.collection(collection).get();
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['synced'] = true;
          await box.put(doc.id, data);
        }
      }
    } catch (e) {
      print('❌ Error sincronizando desde Firebase: $e');
    }
  }

  String _getCollectionType(Map<String, dynamic> data) {
    if (data.containsKey('sowId')) return _collections['sows']!;
    if (data.containsKey('birthDate')) return _collections['births']!;
    if (data.containsKey('pregnancyDate')) return _collections['pregnancies']!;
    return 'registros_generales';
  }

  Future<void> syncData() async {
    await syncLocalData();
  }
}