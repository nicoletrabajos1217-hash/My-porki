import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_service.dart';

class SyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ✅ VERIFICAR CONEXIÓN
  Future<bool> checkConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Verificar conexión a Firestore
      await _firestore.collection('sows').limit(1).get();
      return true;
    } catch (e) {
      print('❌ Sin conexión: $e');
      return false;
    }
  }

  /// ✅ SINCRONIZAR TODOS LOS PENDIENTES
  Future<void> syncAllPending() async {
    try {
      final hasConnection = await checkConnection();
      if (!hasConnection) {
        print('📴 Sin conexión - No se puede sincronizar');
        return;
      }

      final pendingSyncs = await LocalService.getPendingSync();
      print('🔄 Sincronizando ${pendingSyncs.length} elementos pendientes...');

      for (final sync in pendingSyncs) {
        try {
          final data = sync['data'];
          final action = sync['action'];
          final entityType = sync['entityType'];
          final pendingKey = sync['pendingKey'];

          if (entityType == 'sow') {
            final sowId = data['id'];

            switch (action) {
              case 'create':
              case 'update':
                await _firestore
                    .collection('sows')
                    .doc(sowId)
                    .set(data, SetOptions(merge: true));
                print('✅ Sync completado: $action - $sowId');
                break;
              case 'delete':
                await _firestore.collection('sows').doc(sowId).delete();
                print('✅ Eliminación sincronizada: $sowId');
                break;
            }
          }

          // Eliminar sync pendiente después de éxito
          await LocalService.removePendingSync(pendingKey);
        } catch (e) {
          print('❌ Error en sync pendiente: $e');
          // No eliminamos para reintentar luego
        }
      }

      print('✅ Sincronización de pendientes completada');
    } catch (e) {
      print('❌ Error en syncAllPending: $e');
    }
  }

  /// ✅ DESCARGAR TODAS LAS CERDAS DE FIREBASE A HIVE
  Future<void> downloadAllSowsFromFirebase() async {
    try {
      final hasConnection = await checkConnection();
      if (!hasConnection) {
        throw Exception('No hay conexión a internet');
      }

      print('📥 Descargando cerdas desde Firebase...');
      final snapshot = await _firestore.collection('sows').get();

      print('📦 Cerdas encontradas en Firebase: ${snapshot.docs.length}');

      // Guardar/actualizar cada cerda en Hive
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final sowId = doc.id;

          // ✅ CORREGIDO: Estructura consistente con SowService
          final sowData = {
            ...data,
            'id': sowId, // ✅ Usar 'id' en lugar de 'sowId'
            'type': 'sow',
            'synced': true,
            'lastSync': DateTime.now().toIso8601String(),
          };

          // ✅ CORREGIDO: Guardar usando el ID como key
          await LocalService.saveData(key: sowId, value: sowData);

          print('    ✅ Cerda sincronizada: ${sowData['nombre']} ($sowId)');
        } catch (e) {
          print('    ❌ Error procesando cerda: $e');
        }
      }

      print(
        '✅ Descarga completada: ${snapshot.docs.length} cerdas sincronizadas',
      );
    } catch (e) {
      print('❌ Error descargando cerdas: $e');
      rethrow;
    }
  }

  /// ✅ OBTENER ESTADO DE SINCRONIZACIÓN
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final pendingSyncs = await LocalService.getPendingSync();

      // Obtener datos de cerdas
      final allData = await LocalService.getAllData();
      final cerdas = allData
          .where((data) => data is Map && data['type'] == 'sow')
          .cast<Map<String, dynamic>>()
          .toList();

      final totalCerdas = cerdas.length;
      final syncedCerdas = cerdas
          .where((cerda) => cerda['synced'] == true)
          .length;
      final syncPercentage = totalCerdas > 0
          ? ((syncedCerdas / totalCerdas) * 100).round()
          : 100;

      return {
        'totalCerdas': totalCerdas,
        'syncedCerdas': syncedCerdas,
        'pendingSync': pendingSyncs.length,
        'syncPercentage': syncPercentage,
        'lastUpdate': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error obteniendo estado de sync: $e');
      return {
        'totalCerdas': 0,
        'syncedCerdas': 0,
        'pendingSync': 0,
        'syncPercentage': 0,
        'lastUpdate': DateTime.now().toIso8601String(),
        'error': e.toString(),
      };
    }
  }

  /// ✅ SINCRONIZACIÓN MANUAL COMPLETA
  Future<void> fullSync() async {
    try {
      print('🔄 INICIANDO SINCRONIZACIÓN COMPLETA...');

      // 1. Verificar conexión
      final hasConnection = await checkConnection();
      if (!hasConnection) {
        throw Exception('No hay conexión a internet');
      }

      // 2. Sincronizar cambios pendientes locales → Firebase
      await syncAllPending();

      // 3. Descargar cambios de Firebase → Local
      await downloadAllSowsFromFirebase();

      // 4. Obtener estado final
      final syncStatus = await getSyncStatus();

      print('''
✅ SINCRONIZACIÓN COMPLETADA
   📊 Total cerdas: ${syncStatus['totalCerdas']}
   ✅ Sincronizadas: ${syncStatus['syncedCerdas']} 
   📋 Pendientes: ${syncStatus['pendingSync']}
   📈 Porcentaje: ${syncStatus['syncPercentage']}%
      ''');
    } catch (e) {
      print('❌ Error en sincronización completa: $e');
      rethrow;
    }
  }

  /// ✅ SINCRONIZACIÓN RÁPIDA (solo pendientes)
  Future<void> quickSync() async {
    try {
      print('⚡ INICIANDO SINCRONIZACIÓN RÁPIDA...');

      final hasConnection = await checkConnection();
      if (!hasConnection) {
        throw Exception('No hay conexión a internet');
      }

      await syncAllPending();

      final syncStatus = await getSyncStatus();
      print(
        '✅ Sincronización rápida completada - Pendientes: ${syncStatus['pendingSync']}',
      );
    } catch (e) {
      print('❌ Error en sincronización rápida: $e');
      rethrow;
    }
  }

  /// ✅ LIMPIAR PENDIENTES ANTIGUOS (más de 7 días)
  Future<void> cleanOldPendingSyncs() async {
    try {
      final pendingSyncs = await LocalService.getPendingSync();
      final ahora = DateTime.now();
      int cleanedCount = 0;

      for (final sync in pendingSyncs) {
        try {
          final timestamp = sync['timestamp'];
          if (timestamp != null) {
            final syncDate = DateTime.parse(timestamp);
            final diferencia = ahora.difference(syncDate).inDays;

            if (diferencia > 7) {
              await LocalService.removePendingSync(sync['pendingKey']);
              cleanedCount++;
              print('🧹 Pendiente limpiado (antiguo): ${sync['pendingKey']}');
            }
          }
        } catch (e) {
          print('❌ Error limpiando pendiente: $e');
        }
      }

      if (cleanedCount > 0) {
        print('✅ $cleanedCount pendientes antiguos limpiados');
      }
    } catch (e) {
      print('❌ Error limpiando pendientes antiguos: $e');
    }
  }

  /// ✅ VERIFICAR INTEGRIDAD DE DATOS
  Future<Map<String, dynamic>> checkDataIntegrity() async {
    try {
      final allData = await LocalService.getAllData();
      final cerdas = allData
          .where((data) => data is Map && data['type'] == 'sow')
          .cast<Map<String, dynamic>>()
          .toList();

      int conErrores = 0;
      final errores = <String>[];

      for (var cerda in cerdas) {
        // Verificar campos requeridos
        if (cerda['id'] == null) {
          conErrores++;
          errores.add('Cerda sin ID: ${cerda['nombre']}');
        }
        if (cerda['nombre'] == null || cerda['nombre'].toString().isEmpty) {
          conErrores++;
          errores.add('Cerda sin nombre: ${cerda['id']}');
        }
      }

      return {
        'totalCerdas': cerdas.length,
        'conErrores': conErrores,
        'errores': errores,
        'integro': conErrores == 0,
      };
    } catch (e) {
      return {
        'totalCerdas': 0,
        'conErrores': 0,
        'errores': ['Error verificando integridad: $e'],
        'integro': false,
      };
    }
  }

  /// ✅ OBTENER ESTADÍSTICAS DETALLADAS
  Future<Map<String, dynamic>> getDetailedStats() async {
    try {
      final syncStatus = await getSyncStatus();
      final dataIntegrity = await checkDataIntegrity();
      final pendingSyncs = await LocalService.getPendingSync();

      // Contar por acción pendiente
      int pendientesCrear = pendingSyncs
          .where((s) => s['action'] == 'create')
          .length;
      int pendientesActualizar = pendingSyncs
          .where((s) => s['action'] == 'update')
          .length;
      int pendientesEliminar = pendingSyncs
          .where((s) => s['action'] == 'delete')
          .length;

      return {
        ...syncStatus,
        'dataIntegrity': dataIntegrity,
        'pendientesCrear': pendientesCrear,
        'pendientesActualizar': pendientesActualizar,
        'pendientesEliminar': pendientesEliminar,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'error': 'Error obteniendo estadísticas: $e',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
}
