import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class LocalService {
  static const String _mainBox = 'porki_data';
  static const String _usersBox = 'porki_users';
  static const String _syncBox = 'porki_sync';

  /// Inicializar el servicio local
  static Future<void> initialize() async {
    await Hive.openBox(_mainBox);
    await Hive.openBox(_usersBox);
    await Hive.openBox(_syncBox);
    print('✅ LocalService inicializado');
  }

  /// GUARDAR DATOS LOCALMENTE
  static Future<void> saveData({
    required String key,
    required dynamic value,
    String boxName = 'porki_data',
  }) async {
    try {
      final box = await Hive.openBox(boxName);
      await box.put(key, value);
      print('✅ Dato guardado localmente: $key');
    } catch (e) {
      print('❌ Error guardando dato local: $e');
      rethrow;
    }
  }

  /// OBTENER DATOS LOCALES
  static Future<dynamic> getData({
    required String key,
    String boxName = 'porki_data',
    dynamic defaultValue,
  }) async {
    try {
      final box = await Hive.openBox(boxName);
      return box.get(key, defaultValue: defaultValue);
    } catch (e) {
      print('❌ Error obteniendo dato local: $e');
      return defaultValue;
    }
  }

  /// ELIMINAR DATO LOCAL
  static Future<void> deleteData({
    required String key,
    String boxName = 'porki_data',
  }) async {
    try {
      final box = await Hive.openBox(boxName);
      await box.delete(key);
      print('✅ Dato eliminado localmente: $key');
    } catch (e) {
      print('❌ Error eliminando dato local: $e');
      rethrow;
    }
  }

  /// OBTENER TODOS LOS DATOS DE UNA BOX
  static Future<List<dynamic>> getAllData({String boxName = 'porki_data'}) async {
    try {
      final box = await Hive.openBox(boxName);
      return box.values.toList();
    } catch (e) {
      print('❌ Error obteniendo todos los datos: $e');
      return [];
    }
  }

  /// GUARDAR USUARIO LOCALMENTE
  static Future<void> saveUser(Map<String, dynamic> userData) async {
    try {
      final box = await Hive.openBox(_usersBox);
      await box.put('current_user', userData);
      print('✅ Usuario guardado localmente');
    } catch (e) {
      print('❌ Error guardando usuario local: $e');
      rethrow;
    }
  }

  /// OBTENER USUARIO LOCAL
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final box = await Hive.openBox(_usersBox);
      final user = box.get('current_user');
      return user is Map ? Map<String, dynamic>.from(user) : null;
    } catch (e) {
      print('❌ Error obteniendo usuario local: $e');
      return null;
    }
  }

  /// ELIMINAR USUARIO LOCAL (logout)
  static Future<void> clearUser() async {
    try {
      final box = await Hive.openBox(_usersBox);
      await box.delete('current_user');
      print('✅ Usuario eliminado localmente');
    } catch (e) {
      print('❌ Error eliminando usuario local: $e');
      rethrow;
    }
  }

  /// GUARDAR ESTADO DE SINCRONIZACIÓN
  static Future<void> saveSyncStatus({
    required String entityType,
    required DateTime lastSync,
    required int syncedItems,
  }) async {
    try {
      final box = await Hive.openBox(_syncBox);
      await box.put('${entityType}_last_sync', {
        'lastSync': lastSync.toIso8601String(),
        'syncedItems': syncedItems,
        'entityType': entityType,
      });
      print('✅ Estado de sync guardado: $entityType');
    } catch (e) {
      print('❌ Error guardando estado de sync: $e');
    }
  }

  /// OBTENER ESTADO DE SINCRONIZACIÓN
  static Future<Map<String, dynamic>?> getSyncStatus(String entityType) async {
    try {
      final box = await Hive.openBox(_syncBox);
      final status = box.get('${entityType}_last_sync');
      return status is Map ? Map<String, dynamic>.from(status) : null;
    } catch (e) {
      print('❌ Error obteniendo estado de sync: $e');
      return null;
    }
  }

  /// VERIFICAR CONEXIÓN A INTERNET
  static Future<bool> checkConnectivity() async {
    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      
      return result != ConnectivityResult.none;
    } catch (e) {
      print('❌ Error verificando conexión: $e');
      return false;
    }
  }

  /// ESCUCHAR CAMBIOS DE CONEXIÓN
  static Stream<bool> get connectivityStream {
    return Connectivity().onConnectivityChanged.map((result) {
      return result != ConnectivityResult.none;
    });
  }

  /// GUARDAR DATOS PARA SINCRONIZACIÓN PENDIENTE
  static Future<void> savePendingSync({
    required String action, // 'create', 'update', 'delete'
    required String entityType, // 'sow', 'vaccine', etc.
    required Map<String, dynamic> data,
  }) async {
    try {
      final box = await Hive.openBox(_syncBox);
      final pendingKey = 'pending_${DateTime.now().millisecondsSinceEpoch}';
      
      await box.put(pendingKey, {
        'action': action,
        'entityType': entityType,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'pendingKey': pendingKey,
      });
      
      print('✅ Sync pendiente guardado: $entityType - $action');
    } catch (e) {
      print('❌ Error guardando sync pendiente: $e');
    }
  }

  /// OBTENER DATOS PENDIENTES DE SINCRONIZACIÓN
  static Future<List<Map<String, dynamic>>> getPendingSync() async {
    try {
      final box = await Hive.openBox(_syncBox);
      final allData = box.values.toList();
      
      final pendingSyncs = allData.where((data) => 
        data is Map && 
        data['pendingKey'] != null &&
        data['pendingKey'].toString().startsWith('pending_')
      ).cast<Map<String, dynamic>>().toList();

      // Ordenar por timestamp (más antiguos primero)
      pendingSyncs.sort((a, b) => 
        a['timestamp'].compareTo(b['timestamp'])
      );

      return pendingSyncs;
    } catch (e) {
      print('❌ Error obteniendo sync pendientes: $e');
      return [];
    }
  }

  /// ELIMINAR SINCRONIZACIÓN PENDIENTE
  static Future<void> removePendingSync(String pendingKey) async {
    try {
      final box = await Hive.openBox(_syncBox);
      await box.delete(pendingKey);
      print('✅ Sync pendiente eliminado: $pendingKey');
    } catch (e) {
      print('❌ Error eliminando sync pendiente: $e');
    }
  }

  /// LIMPIAR TODOS LOS DATOS LOCALES (para testing o reset)
  static Future<void> clearAllData() async {
    try {
      final mainBox = await Hive.openBox(_mainBox);
      final usersBox = await Hive.openBox(_usersBox);
      final syncBox = await Hive.openBox(_syncBox);
      
      await mainBox.clear();
      await usersBox.clear();
      await syncBox.clear();
      
      print('✅ Todos los datos locales eliminados');
    } catch (e) {
      print('❌ Error eliminando datos locales: $e');
      rethrow;
    }
  }

  /// OBTENER ESTADÍSTICAS DE ALMACENAMIENTO
  static Future<Map<String, dynamic>> getStorageStats() async {
    try {
      final mainBox = await Hive.openBox(_mainBox);
      final usersBox = await Hive.openBox(_usersBox);
      final syncBox = await Hive.openBox(_syncBox);

      return {
        'total_cerdas': mainBox.values.where((data) => 
          data is Map && data['type'] == 'sow').length,
        'total_usuarios': usersBox.length,
        'sync_pendientes': syncBox.values.where((data) => 
          data is Map && data['pendingKey'] != null).length,
        'ultima_sincronizacion': await getSyncStatus('sows'),
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {};
    }
  }
}