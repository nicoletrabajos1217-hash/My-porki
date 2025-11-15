import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_service.dart';

class SowService {
  static const String _sowType = 'sow';
  static const String _vaccineType = 'vaccine';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Inicializar el servicio
  static Future<void> initialize() async {
    await LocalService.initialize();
    print('✅ SowService inicializado');
  }

  /// ✅ CORREGIDO: Verificar conexión
  static Future<bool> _hasInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult != ConnectivityResult.none;
    } catch (e) {
      print('❌ Error verificando conexión: $e');
      return false;
    }
  }

  /// ✅ NUEVO: Sincronizar con Firestore
  static Future<void> _syncWithFirestore(
    Map<String, dynamic> data,
    String action,
  ) async {
    try {
      final hasConnection = await _hasInternetConnection();
      final cerdaId = data['id'];

      if (hasConnection) {
        switch (action) {
          case 'create':
          case 'update':
            await _firestore
                .collection('sows')
                .doc(cerdaId)
                .set(data, SetOptions(merge: true));
            print('✅ Cerda sincronizada con Firestore: $cerdaId - $action');
            break;
          case 'delete':
            await _firestore.collection('sows').doc(cerdaId).delete();
            print('✅ Cerda eliminada de Firestore: $cerdaId');
            break;
        }
      } else {
        // Guardar para sync posterior
        await LocalService.savePendingSync(
          action: action,
          entityType: _sowType,
          data: data,
        );
        print(
          '📱 Cambio guardado para sync posterior (offline): $action - $cerdaId',
        );
      }
    } catch (e) {
      print('❌ Error en sync con Firestore: $e');
      // Si falla, guardar como pendiente
      await LocalService.savePendingSync(
        action: action,
        entityType: _sowType,
        data: data,
      );
    }
  }

  /// ✅ CORREGIDO: AGREGAR NUEVA CERDA - CON FIRESTORE
  static Future<Map<String, dynamic>> agregarCerda({
    required String nombre,
    required String numeroArete,
    required DateTime fechaNacimiento,
    String? raza,
    required String estado,
    DateTime? fechaMonta,
    DateTime? fechaPalpacion,
    String? observaciones,
  }) async {
    try {
      // Calcular fecha de parto (114 días después de la monta)
      DateTime? fechaPartoCalculado;
      if (fechaMonta != null) {
        fechaPartoCalculado = fechaMonta.add(const Duration(days: 114));
      }

      // Generar ID único
      final String cerdaId = 'sow_${DateTime.now().millisecondsSinceEpoch}';

      final nuevaCerda = {
        'id': cerdaId,
        'type': _sowType,
        'nombre': nombre,
        'numero_arete': numeroArete,
        'fecha_nacimiento': fechaNacimiento.toIso8601String(),
        'raza': raza ?? 'desconocida',
        'estado': estado,
        'fecha_monta': fechaMonta?.toIso8601String(),
        'fecha_palpacion': fechaPalpacion?.toIso8601String(),
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'observaciones': observaciones ?? '',
        'fecha_creacion': DateTime.now().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'synced': false,
      };

      // ✅ 1. GUARDAR LOCALMENTE (Hive)
      await LocalService.saveData(key: cerdaId, value: nuevaCerda);

      // ✅ 2. SINCRONIZAR CON FIRESTORE
      await _syncWithFirestore(nuevaCerda, 'create');

      print('✅ Cerda agregada: $nombre (ID: $cerdaId)');
      return nuevaCerda;
    } catch (e) {
      print('❌ Error agregando cerda: $e');
      rethrow;
    }
  }

  /// ✅ CORREGIDO: OBTENER TODAS LAS CERDAS
  static Future<List<Map<String, dynamic>>> obtenerCerdas() async {
    try {
      final allData = await LocalService.getAllData();

      final cerdas = allData
          .where((data) => data is Map && data['type'] == _sowType)
          .cast<Map<String, dynamic>>()
          .toList();

      // Ordenar por fecha de creación (más recientes primero)
      cerdas.sort((a, b) => b['fecha_creacion'].compareTo(a['fecha_creacion']));

      return cerdas;
    } catch (e) {
      print('❌ Error obteniendo cerdas: $e');
      return [];
    }
  }

  /// ✅ CORREGIDO: OBTENER CERDA POR ID
  static Future<Map<String, dynamic>?> obtenerCerdaPorId(String id) async {
    try {
      final data = await LocalService.getData(key: id);

      if (data is Map && data['type'] == _sowType) {
        return data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('❌ Error obteniendo cerda por ID: $e');
      return null;
    }
  }

  /// ✅ CORREGIDO: ACTUALIZAR CERDA - CON FIRESTORE
  static Future<void> actualizarCerda({
    required String id,
    String? nombre,
    String? numeroArete,
    DateTime? fechaNacimiento,
    String? raza,
    String? estado,
    DateTime? fechaMonta,
    DateTime? fechaPalpacion,
    String? observaciones,
  }) async {
    try {
      final cerdaExistente = await obtenerCerdaPorId(id);

      if (cerdaExistente == null) {
        throw Exception('Cerda no encontrada');
      }

      // Recalcular fecha de parto si se actualiza la fecha de monta
      DateTime? fechaPartoCalculado;
      if (fechaMonta != null) {
        fechaPartoCalculado = fechaMonta.add(const Duration(days: 114));
      } else if (cerdaExistente['fecha_monta'] != null) {
        fechaPartoCalculado = DateTime.parse(
          cerdaExistente['fecha_monta'],
        ).add(const Duration(days: 114));
      }

      final cerdaActualizada = {
        ...cerdaExistente,
        'nombre': nombre ?? cerdaExistente['nombre'],
        'numero_arete': numeroArete ?? cerdaExistente['numero_arete'],
        'fecha_nacimiento':
            fechaNacimiento?.toIso8601String() ??
            cerdaExistente['fecha_nacimiento'],
        'raza': raza ?? cerdaExistente['raza'],
        'estado': estado ?? cerdaExistente['estado'],
        'fecha_monta':
            fechaMonta?.toIso8601String() ?? cerdaExistente['fecha_monta'],
        'fecha_palpacion':
            fechaPalpacion?.toIso8601String() ??
            cerdaExistente['fecha_palpacion'],
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'observaciones': observaciones ?? cerdaExistente['observaciones'],
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'synced': false,
      };

      // ✅ 1. ACTUALIZAR LOCALMENTE
      await LocalService.saveData(key: id, value: cerdaActualizada);

      // ✅ 2. SINCRONIZAR CON FIRESTORE
      await _syncWithFirestore(cerdaActualizada, 'update');

      print('✅ Cerda actualizada: ${cerdaActualizada['nombre']}');
    } catch (e) {
      print('❌ Error actualizando cerda: $e');
      rethrow;
    }
  }

  /// ✅ CORREGIDO: ELIMINAR CERDA - CON FIRESTORE
  static Future<void> eliminarCerda(String id) async {
    try {
      final cerda = await obtenerCerdaPorId(id);

      if (cerda == null) {
        throw Exception('Cerda no encontrada');
      }

      // ✅ 1. ELIMINAR LOCALMENTE (Hive)
      await LocalService.deleteData(key: id);
      print('✅ Cerda eliminada localmente: $id');

      // ✅ 2. SINCRONIZAR CON FIRESTORE
      await _syncWithFirestore(cerda, 'delete');

      print('✅ Eliminación completada: $id');
    } catch (e) {
      print('❌ Error eliminando cerda: $e');
      rethrow;
    }
  }

  /// ✅ CORREGIDO: AGREGAR VACUNA A CERDA - CON FIRESTORE
  static Future<void> agregarVacuna({
    required String cerdaId,
    required String nombreVacuna,
    required DateTime fechaPrimeraDosis,
    required int totalDosis,
    int diasEntreDosis = 21,
    String? laboratorio,
    String? lote,
    String? observaciones,
  }) async {
    try {
      final cerda = await obtenerCerdaPorId(cerdaId);

      if (cerda == null) {
        throw Exception('Cerda no encontrada');
      }

      // Generar ID único para vacuna
      final String vacunaId = 'vac_${DateTime.now().millisecondsSinceEpoch}';

      final nuevaVacuna = {
        'id': vacunaId,
        'type': _vaccineType,
        'cerda_id': cerdaId,
        'cerda_nombre': cerda['nombre'],
        'nombre_vacuna': nombreVacuna,
        'fecha_primer_dosis': fechaPrimeraDosis.toIso8601String(),
        'total_dosis': totalDosis,
        'dias_entre_dosis': diasEntreDosis,
        'laboratorio': laboratorio,
        'lote': lote,
        'observaciones': observaciones,
        'fecha_creacion': DateTime.now().toIso8601String(),
      };

      // ✅ 1. GUARDAR VACUNA LOCALMENTE
      await LocalService.saveData(key: vacunaId, value: nuevaVacuna);

      // ✅ 2. ACTUALIZAR CERDA CON LA NUEVA VACUNA
      final vacunasActuales = List<Map<String, dynamic>>.from(
        cerda['vacunas'] ?? [],
      );
      vacunasActuales.add(nuevaVacuna);

      final cerdaActualizada = {
        ...cerda,
        'vacunas': vacunasActuales,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'synced': false,
      };

      await LocalService.saveData(key: cerdaId, value: cerdaActualizada);

      // ✅ 3. SINCRONIZAR CERDA ACTUALIZADA CON FIRESTORE
      await _syncWithFirestore(cerdaActualizada, 'update');

      print('✅ Vacuna agregada: $nombreVacuna a ${cerda['nombre']}');
    } catch (e) {
      print('❌ Error agregando vacuna: $e');
      rethrow;
    }
  }

  /// ✅ OBTENER VACUNAS DE UNA CERDA
  static Future<List<Map<String, dynamic>>> obtenerVacunas(
    String cerdaId,
  ) async {
    try {
      final allData = await LocalService.getAllData();

      final vacunas = allData
          .where(
            (data) =>
                data is Map &&
                data['type'] == _vaccineType &&
                data['cerda_id'] == cerdaId,
          )
          .cast<Map<String, dynamic>>()
          .toList();

      // Ordenar por fecha de creación
      vacunas.sort(
        (a, b) => b['fecha_creacion'].compareTo(a['fecha_creacion']),
      );

      return vacunas;
    } catch (e) {
      print('❌ Error obteniendo vacunas: $e');
      return [];
    }
  }

  /// ✅ OBTENER CERDAS POR ESTADO
  static Future<List<Map<String, dynamic>>> obtenerCerdasPorEstado(
    String estado,
  ) async {
    final todasCerdas = await obtenerCerdas();
    return todasCerdas.where((cerda) => cerda['estado'] == estado).toList();
  }

  /// ✅ OBTENER PARTOS PRÓXIMOS
  static Future<List<Map<String, dynamic>>> obtenerPartosProximos() async {
    final todasCerdas = await obtenerCerdas();
    final ahora = DateTime.now();

    return todasCerdas.where((cerda) {
      if (cerda['fecha_parto_calculado'] == null) return false;

      try {
        final fechaParto = DateTime.parse(cerda['fecha_parto_calculado']);
        final diasRestantes = fechaParto.difference(ahora).inDays;
        return diasRestantes >= 0 && diasRestantes <= 7;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// ✅ OBTENER ESTADÍSTICAS
  static Future<Map<String, dynamic>> obtenerEstadisticas() async {
    final cerdas = await obtenerCerdas();

    return {
      'total_cerdas': cerdas.length,
      'preñadas': cerdas.where((c) => c['estado'] == 'preñada').length,
      'lactantes': cerdas.where((c) => c['estado'] == 'lactante').length,
      'vacias': cerdas.where((c) => c['estado'] == 'vacía').length,
      'partos_proximos': (await obtenerPartosProximos()).length,
    };
  }

  /// ✅ NUEVO: OBTENER STREAM EN TIEMPO REAL DESDE FIRESTORE
  static Stream<QuerySnapshot> getSowsStream() {
    return _firestore.collection('sows').snapshots();
  }

  /// ✅ NUEVO: SINCRONIZAR CAMBIOS PENDIENTES
  static Future<void> syncPendingChanges() async {
    try {
      final hasConnection = await _hasInternetConnection();
      if (!hasConnection) {
        print('📴 Sin conexión - No se puede sincronizar');
        return;
      }

      final pendingSyncs = await LocalService.getPendingSync();
      print('🔄 Sincronizando ${pendingSyncs.length} cambios pendientes...');

      for (final sync in pendingSyncs) {
        try {
          final data = sync['data'];
          final action = sync['action'];
          final entityType = sync['entityType'];
          final pendingKey = sync['pendingKey'];

          if (entityType == _sowType) {
            switch (action) {
              case 'create':
              case 'update':
                await _firestore
                    .collection('sows')
                    .doc(data['id'])
                    .set(data, SetOptions(merge: true));
                print('✅ Sync completado: $action - ${data['id']}');
                break;
              case 'delete':
                await _firestore.collection('sows').doc(data['id']).delete();
                print('✅ Eliminación sincronizada: ${data['id']}');
                break;
            }
          }

          // Eliminar sync pendiente después de éxito
          await LocalService.removePendingSync(pendingKey);
        } catch (e) {
          print('❌ Error en sync pendiente: $e');
        }
      }

      print('✅ Todos los cambios pendientes sincronizados');
    } catch (e) {
      print('❌ Error sincronizando cambios pendientes: $e');
    }
  }

  /// ✅ NUEVO: DESCARGAR TODAS LAS CERDAS DESDE FIRESTORE
  static Future<void> downloadAllSowsFromFirebase() async {
    try {
      final hasConnection = await _hasInternetConnection();
      if (!hasConnection) {
        throw Exception('No hay conexión a internet');
      }

      print('📥 Descargando cerdas desde Firestore...');
      final snapshot = await _firestore.collection('sows').get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sowId = doc.id;

        final sowData = {
          ...data,
          'id': sowId,
          'type': _sowType,
          'synced': true,
          'lastSync': DateTime.now().toIso8601String(),
        };

        // Guardar en Hive
        await LocalService.saveData(key: sowId, value: sowData);
      }

      print('✅ ${snapshot.docs.length} cerdas descargadas desde Firestore');
    } catch (e) {
      print('❌ Error descargando cerdas: $e');
      rethrow;
    }
  }

  /// ✅ NUEVO: OBTENER ESTADO DE SINCRONIZACIÓN
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final cerdas = await obtenerCerdas();
      final pendingSyncs = await LocalService.getPendingSync();

      final syncedCerdas = cerdas
          .where((cerda) => cerda['synced'] == true)
          .length;
      final totalCerdas = cerdas.length;
      final syncPercentage = totalCerdas > 0
          ? ((syncedCerdas / totalCerdas) * 100).round()
          : 0;

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
      };
    }
  }
}
