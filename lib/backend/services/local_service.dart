import 'package:hive_flutter/hive_flutter.dart';

class LocalService {
  // Es mejor abrir la box cuando se necesite en lugar de tenerla como final
  Future<Box> get _box async => await Hive.openBox('porki_data');

  // Guardar dato local
  Future<void> saveData(String key, dynamic value) async {
    final box = await _box;
    await box.put(key, value);
  }

  // Obtener dato local
  Future<dynamic> getData(String key) async {
    final box = await _box;
    return box.get(key);
  }

  // Obtener todos los datos locales
  Future<Map<String, dynamic>> getAllData() async {
    final box = await _box;
    return Map<String, dynamic>.from(box.toMap());
  }

  // Eliminar un dato local
  Future<void> deleteData(String key) async {
    final box = await _box;
    await box.delete(key);
  }

  // Limpiar todo el almacenamiento local
  Future<void> clearAll() async {
    final box = await _box;
    await box.clear();
  }

  // Podrías agregar métodos específicos para My Porki
  Future<void> saveSow(Map<String, dynamic> sowData) async {
    final key = 'sow_${sowData['id'] ?? DateTime.now().millisecondsSinceEpoch}';
    await saveData(key, {...sowData, 'type': 'sow'});
  }

  Future<List<Map<String, dynamic>>> getSows() async {
    final allData = await getAllData();
    return allData.entries
        .where((entry) => entry.value is Map && entry.value['type'] == 'sow')
        .map((entry) => Map<String, dynamic>.from(entry.value))
        .toList();
  }
}