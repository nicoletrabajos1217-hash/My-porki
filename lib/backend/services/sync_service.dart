import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'dart:developer' as developer;

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
      
      developer.log('🔄 Sincronización completada', name: 'my_porki.sync');
    } catch (e) {
      developer.log('❌ Error en sincronización general: $e', name: 'my_porki.sync');
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
        developer.log('✅ $collection sincronizado: $docId', name: 'my_porki.sync');
      }
    } catch (e) {
      developer.log('❌ Error sincronizando $key: $e', name: 'my_porki.sync');
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
      developer.log('❌ Error sincronizando desde Firebase: $e', name: 'my_porki.sync');
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