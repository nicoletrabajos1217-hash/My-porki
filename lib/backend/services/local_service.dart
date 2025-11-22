import 'package:hive/hive.dart';
import 'connectivity_service.dart';

class LocalService {
  // Boxes
  static const String _mainBox = 'porki_data';     // Cerdas, partos, vacunas, etc.
  static const String _usersBox = 'porki_users';   // Usuario actual
  static const String _syncBox = 'porki_sync';     // Acciones pendientes (offline)

  static final ConnectivityService _connectivity = ConnectivityService();

  /// --------------------------------------------------------------------------
  /// 🔵 INICIALIZACIÓN
  /// --------------------------------------------------------------------------
  static Future<void> initialize() async {
    await Hive.openBox(_mainBox);
    await Hive.openBox(_usersBox);
    await Hive.openBox(_syncBox);
    print('✅ LocalService inicializado correctamente');
  }

  /// --------------------------------------------------------------------------
  /// 🔵 MÉTODOS GENERALES DE HIVE
  /// --------------------------------------------------------------------------
  static Future<Box> _openBox(String box) async =>
      Hive.isBoxOpen(box) ? Hive.box(box) : await Hive.openBox(box);

  static Future<void> _safePut(Box box, dynamic key, dynamic value) async {
    try {
      await box.put(key, value);
    } catch (e) {
      print("❌ Error guardando en hive: $e");
      rethrow;
    }
  }

  /// Guardar. Si key es null intenta usar value['id'], si tampoco existe genera 'auto_<timestamp>'.
  /// Devuelve la clave real usada en el box (puede ser String o int).
  static Future<dynamic> saveData({
    dynamic key,
    required dynamic value,
    String boxName = _mainBox,
  }) async {
    final box = await _openBox(boxName);

    dynamic useKey = key;
    try {
      // si no nos pasaron key, preferimos usar value['id']
      if (useKey == null && value is Map && value.containsKey('id')) {
        useKey = value['id'];
      }

      // si sigue nulo, generamos una key única
      if (useKey == null) {
        useKey = 'auto_${DateTime.now().millisecondsSinceEpoch}';
      }

      await _safePut(box, useKey, value);
      print('💾 Guardado en $boxName → $useKey');
      return useKey;
    } catch (e) {
      print('❌ saveData error: $e');
      rethrow;
    }
  }

  /// Obtener: intenta key directo (clave del box), si no encuentra busca un elemento cuyo ['id'] == key - CORREGIDO
  static Future<dynamic> getData({
    required dynamic key,
    String boxName = _mainBox,
    dynamic defaultValue,
  }) async {
    final box = await _openBox(boxName);

    // intento directo
    if (box.containsKey(key)) {
      final value = box.get(key, defaultValue: defaultValue);
      // CORRECCIÓN: Asegurar que los Map tengan claves String
      if (value is Map) {
        final convertedMap = <String, dynamic>{};
        value.forEach((k, v) => convertedMap[k.toString()] = v);
        return convertedMap;
      }
      return value;
    }

    // intento buscar por id dentro de los valores
    for (var bKey in box.keys) {
      final item = box.get(bKey);
      if (item is Map) {
        // CORRECCIÓN: Convertir claves a String para la comparación
        final convertedItem = <String, dynamic>{};
        item.forEach((k, v) => convertedItem[k.toString()] = v);
        
        if (convertedItem['id'] == key) {
          return convertedItem;
        }
      }
    }

    return defaultValue;
  }

  /// Eliminar: acepta tanto la clave real del box como el 'id' dentro del objeto.
  static Future<void> deleteData({
    required dynamic key,
    String boxName = _mainBox,
  }) async {
    final box = await _openBox(boxName);

    // si existe como clave directa lo borramos
    if (box.containsKey(key)) {
      await box.delete(key);
      print('🗑️ Eliminado de $boxName → $key (clave directa)');
      return;
    }

    // si no, buscamos el elemento cuyo ['id'] == key y borramos esa clave real
    for (var bKey in box.keys.toList()) {
      final item = box.get(bKey);
      if (item is Map && item['id'] == key) {
        await box.delete(bKey);
        print('🗑️ Eliminado de $boxName → $bKey (encontrado por id: $key)');
        return;
      }
    }

    print('⚠️ deleteData: no se encontró clave ni id "$key" en $boxName');
  }

  /// Listar todo: devuelve la lista de valores (clonado si es Map) - CORREGIDO
  static Future<List<dynamic>> getAllData({String boxName = _mainBox}) async {
    final box = await _openBox(boxName);
    final out = <dynamic>[];
    
    for (var v in box.values) {
      if (v is Map) {
        // CORRECCIÓN: Preservar todas las claves, no solo las String
        final clonedMap = <String, dynamic>{};
        v.forEach((key, value) {
          clonedMap[key.toString()] = value;
        });
        out.add(clonedMap);
      } else {
        out.add(v);
      }
    }
    
    print('📊 DEBUG: getAllData retornando ${out.length} elementos');
    return out;
  }

  /// --------------------------------------------------------------------------
  /// 🔵 USUARIOS LOCALES
  /// --------------------------------------------------------------------------
  static Future<void> saveUser(Map<String, dynamic> userData) async {
    final box = await _openBox(_usersBox);
    await box.put('current_user', userData);
    print('👤 Usuario guardado localmente');
  }

  static Future<Map<String, dynamic>?> getCurrentUser() async {
    final box = await _openBox(_usersBox);
    final user = box.get('current_user');
    return user is Map ? Map<String, dynamic>.from(user) : null;
  }

  static Future<void> clearUser() async {
    final box = await _openBox(_usersBox);
    await box.delete('current_user');
    print('👤 Usuario eliminado');
  }

  /// --------------------------------------------------------------------------
  /// 🔵 SINCRONIZACIÓN (OFFLINE → FIRESTORE)
  /// --------------------------------------------------------------------------
  /// Guardar registro pendiente de sincronización
  static Future<void> savePendingSync({
    required String action,      // create, update, delete
    required String entityType,  // sow, parto, vacuna…
    required Map<String, dynamic> data,
  }) async {
    final box = await _openBox(_syncBox);

    final pendingKey = "pending_${DateTime.now().millisecondsSinceEpoch}";

    await box.put(pendingKey, {
      "pendingKey": pendingKey,
      "action": action,
      "entityType": entityType,
      "data": data,
      "timestamp": DateTime.now().toIso8601String(),
    });

    print("📌 Guardado para sincronizar: [$entityType] $action ($pendingKey)");
  }

  /// Obtener registros pendientes
  static Future<List<Map<String, dynamic>>> getPendingSync() async {
    final box = await _openBox(_syncBox);
    final list = box.values
        .where((e) => e is Map && e['pendingKey'] != null)
        .cast<Map<String, dynamic>>()
        .toList();

    list.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
    return List<Map<String, dynamic>>.from(list);
  }

  /// Eliminar un registro ya sincronizado
  static Future<void> removePendingSync(String pendingKey) async {
    final box = await _openBox(_syncBox);
    if (box.containsKey(pendingKey)) {
      await box.delete(pendingKey);
      print("✔️ Eliminado pendiente → $pendingKey");
    } else {
      print("⚠️ removePendingSync: no existe $pendingKey");
    }
  }

  /// --------------------------------------------------------------------------
  /// 🔵 ESTADÍSTICAS
  /// --------------------------------------------------------------------------
  static Future<Map<String, dynamic>> getStorageStats() async {
    final main = await _openBox(_mainBox);
    final users = await _openBox(_usersBox);
    final sync = await _openBox(_syncBox);

    final totalCerdas = main.values.where((e) =>
        e is Map && (e['type'] == 'sow' || e['type'] == 'cerda' || e['id'] != null)).length;

    return {
      "total_cerdas": totalCerdas,
      "total_usuarios": users.length,
      "pendientes_sync": sync.values.where((e) => e is Map && e['pendingKey'] != null).length,
    };
  }

  /// --------------------------------------------------------------------------
  /// 🔵 INTERNET
  /// --------------------------------------------------------------------------
  static Future<bool> checkConnectivity() async {
    try {
      return await _connectivity.checkConnection();
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> get connectivityStream => _connectivity.connectionStream;

  /// --------------------------------------------------------------------------
  /// 🔵 BORRAR TODO (para reset o testing)
  /// --------------------------------------------------------------------------
  static Future<void> clearAllData() async {
    await (await _openBox(_mainBox)).clear();
    await (await _openBox(_usersBox)).clear();
    await (await _openBox(_syncBox)).clear();

    print('🧨 TODO limpiado localmente (Hive reset)');
  }
}