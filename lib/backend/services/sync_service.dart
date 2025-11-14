import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'dart:async';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final int _maxRetries = 3;
  final Map<String, int> _retryCount = {};

  // ✅ SINCRONIZACIÓN SEGURA PARA UNA CERDA
  Future<bool> syncSowSafe(Map<String, dynamic> sowData, {int? localKey}) async {
    try {
      String sowId = sowData['sowId'] ?? 'sow_${DateTime.now().millisecondsSinceEpoch}';
      
      print('🔄 Iniciando sincronización segura para: ${sowData['nombre']}');
      
      // 1. GUARDAR COMO PENDIENTE PRIMERO
      await _saveAsPending(sowData, localKey);
      
      // 2. INTENTAR SINCRONIZACIÓN INMEDIATA
      bool syncSuccess = await _syncWithRetry(sowData, sowId, localKey);
      
      if (syncSuccess) {
        print('✅ Sincronización exitosa: ${sowData['nombre']}');
        await _removeFromPending(sowId);
        return true;
      } else {
        print('⏳ Sincronización fallida, guardada para reintentar: ${sowData['nombre']}');
        return false;
      }
    } catch (e) {
      print('❌ Error en syncSowSafe: $e');
      await _saveAsPending(sowData, localKey);
      return false;
    }
  }

  // ✅ SINCRONIZACIÓN CON REINTENTOS
  Future<bool> _syncWithRetry(Map<String, dynamic> sowData, String sowId, int? localKey) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        print('🔄 Intento $attempt de sincronización para: ${sowData['nombre']}');
        
        // Preparar datos para Firebase
        final firebaseData = Map<String, dynamic>.from(sowData);
        firebaseData['synced'] = true;
        firebaseData['lastSync'] = FieldValue.serverTimestamp();
        firebaseData['syncAttempts'] = attempt;
        if (localKey != null) {
          firebaseData['localKey'] = localKey.toString();
        }

        // Guardar en Firebase
        await _firestore.collection('cerdas').doc(sowId).set(firebaseData, SetOptions(merge: true));
        
        // VERIFICAR que realmente se guardó
        bool verified = await _verifySync(sowId);
        if (verified) {
          // Actualizar local como sincronizado
          await _updateLocalSyncStatus(localKey, sowData, true);
          return true;
        }
      } catch (e) {
        print('❌ Intento $attempt fallido: $e');
        await Future.delayed(Duration(seconds: attempt * 2)); // Backoff exponencial
      }
    }
    return false;
  }

  // ✅ VERIFICAR QUE REALMENTE SE GUARDÓ EN FIREBASE
  Future<bool> _verifySync(String sowId) async {
    try {
      DocumentSnapshot doc = await _firestore.collection('cerdas').doc(sowId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  // ✅ GUARDAR COMO PENDIENTE
  Future<void> _saveAsPending(Map<String, dynamic> sowData, int? localKey) async {
    try {
      final box = await Hive.openBox('porki_sync');
      String sowId = sowData['sowId'] ?? 'sow_${DateTime.now().millisecondsSinceEpoch}';
      
      final pendingData = {
        'action': 'create',
        'entityType': 'sow',
        'data': sowData,
        'sowId': sowId,
        'localKey': localKey,
        'timestamp': DateTime.now().toIso8601String(),
        'lastAttempt': DateTime.now().toIso8601String(),
        'attempts': 0,
      };
      
      await box.put(sowId, pendingData);
      print('📋 Guardado como pendiente: ${sowData['nombre']}');
    } catch (e) {
      print('❌ Error guardando como pendiente: $e');
    }
  }

  // ✅ ELIMINAR DE PENDIENTES
  Future<void> _removeFromPending(String sowId) async {
    try {
      final box = await Hive.openBox('porki_sync');
      await box.delete(sowId);
      _retryCount.remove(sowId);
      print('✅ Eliminado de pendientes: $sowId');
    } catch (e) {
      print('❌ Error eliminando de pendientes: $e');
    }
  }

  // ✅ ACTUALIZAR ESTADO LOCAL
  Future<void> _updateLocalSyncStatus(int? localKey, Map<String, dynamic> sowData, bool synced) async {
    if (localKey != null) {
      try {
        final box = await Hive.openBox('porki_data');
        sowData['synced'] = synced;
        sowData['lastSyncAttempt'] = DateTime.now().toIso8601String();
        await box.put(localKey, sowData);
      } catch (e) {
        print('❌ Error actualizando estado local: $e');
      }
    }
  }

  // ✅ DESCARGAR TODAS LAS CERDAS DE FIREBASE A HIVE (se ejecuta al iniciar sesión)
  Future<void> downloadAllSowsFromFirebase() async {
    try {
      print('📥 Descargando cerdas desde Firebase...');
      final box = await Hive.openBox('porki_data');

      // Obtener todas las cerdas del usuario desde Firebase
      final snapshot = await _firestore
          .collection('cerdas')
          .get();

      print('📦 Cerdas encontradas en Firebase: ${snapshot.docs.length}');

      // Guardar/actualizar cada cerda en Hive
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sowId = doc.id;

        // Agregar el ID de Firebase para sincronización futura
        final sowData = {
          ...data,
          'sowId': sowId,
          'type': 'sow',
          'synced': true,
          'lastSync': DateTime.now().toIso8601String(),
        };

        // Buscar si ya existe localmente (por sowId)
        bool encontrado = false;
        for (var key in box.keys) {
          final item = box.get(key);
          if (item is Map && item['sowId'] == sowId) {
            // Actualizar el existente
            await box.put(key, sowData);
            encontrado = true;
            print('🔄 Cerda actualizada: ${sowData['nombre']} (${sowData['identificacion']})');
            break;
          }
        }

        // Si no existe, agregar como nuevo
        if (!encontrado) {
          await box.add(sowData);
          print('✨ Nueva cerda agregada: ${sowData['nombre']} (${sowData['identificacion']})');
        }
      }

      print('✅ Descarga completada: ${snapshot.docs.length} cerdas sincronizadas');
    } catch (e) {
      print('❌ Error descargando cerdas: $e');
    }
  }

  // ✅ SINCRONIZAR TODOS LOS PENDIENTES (se ejecuta cada 1 minuto)
  Future<void> syncAllPending() async {
    try {
      final box = await Hive.openBox('porki_sync');
      final pendingKeys = box.keys.toList();
      
      print('🔄 Sincronizando ${pendingKeys.length} elementos pendientes...');
      
      for (var key in pendingKeys) {
        try {
          final pendingData = box.get(key);
          if (pendingData != null && pendingData is Map) {
            final data = Map<String, dynamic>.from(pendingData);
            
            // Verificar intentos máximos
            int attempts = (data['attempts'] ?? 0) + 1;
            if (attempts > _maxRetries) {
              print('🚫 Máximos intentos alcanzados para: $key');
              await box.delete(key);
              continue;
            }
            
            // Actualizar contador de intentos
            data['attempts'] = attempts;
            data['lastAttempt'] = DateTime.now().toIso8601String();
            await box.put(key, data);
            
            // Intentar sincronizar
            final sowData = Map<String, dynamic>.from(data['data']);
            bool success = await _syncWithRetry(sowData, data['sowId'], data['localKey']);
            
            if (success) {
              await box.delete(key);
            }
          }
        } catch (e) {
          print('❌ Error sincronizando pendiente $key: $e');
        }
      }
      
      print('✅ Sincronización de pendientes completada');
    } catch (e) {
      print('❌ Error en syncAllPending: $e');
    }
  }

  // ✅ VERIFICAR CONEXIÓN
  Future<bool> checkConnection() async {
    try {
      await _firestore.collection('cerdas').limit(1).get();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ✅ OBTENER ESTADO DE SINCRONIZACIÓN
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final box = await Hive.openBox('porki_sync');
      final pendingCount = box.keys.length;
      
      final dataBox = await Hive.openBox('porki_data');
      final totalCerdas = dataBox.values.length;
      final syncedCerdas = dataBox.values.where((data) => data is Map && data['synced'] == true).length;
      
      return {
        'pendingSync': pendingCount,
        'totalCerdas': totalCerdas,
        'syncedCerdas': syncedCerdas,
        'syncPercentage': totalCerdas > 0 ? (syncedCerdas / totalCerdas * 100).round() : 100,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}