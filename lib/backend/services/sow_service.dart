import 'local_service.dart';

class SowService {
  static const String _sowType = 'sow';
  static const String _vaccineType = 'vaccine';

  /// Inicializar el servicio
  static Future<void> initialize() async {
    await LocalService.initialize();
    print('✅ SowService inicializado');
  }

  /// AGREGAR NUEVA CERDA - CORREGIDO
  static Future<Map<String, dynamic>> agregarCerda({
    required String nombre,
    required String numeroArete,
    required DateTime fechaNacimiento,
    required String raza,
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

      // CORREGIDO: Generar ID único
      final String cerdaId = 'sow_${DateTime.now().millisecondsSinceEpoch}';

      final nuevaCerda = {
        'id': cerdaId,
        'type': _sowType,
        'nombre': nombre,
        'numero_arete': numeroArete,
        'fecha_nacimiento': fechaNacimiento.toIso8601String(),
        'raza': raza,
        'estado': estado,
        'fecha_monta': fechaMonta?.toIso8601String(),
        'fecha_palpacion': fechaPalpacion?.toIso8601String(),
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'observaciones': observaciones ?? '',
        'fecha_creacion': DateTime.now().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      };

      // ✅ CORREGIDO: Usar el ID como clave
      await LocalService.saveData(
        key: cerdaId, // Usar el ID string como clave
        value: nuevaCerda,
      );

      // Guardar para sync pendiente si hay conexión
      final hasConnection = await LocalService.checkConnectivity();
      if (!hasConnection) {
        await LocalService.savePendingSync(
          action: 'create',
          entityType: _sowType,
          data: nuevaCerda,
        );
      }

      print('✅ Cerda agregada: $nombre (ID: $cerdaId)');
      return nuevaCerda;
    } catch (e) {
      print('❌ Error agregando cerda: $e');
      rethrow;
    }
  }

  /// OBTENER TODAS LAS CERDAS
  static Future<List<Map<String, dynamic>>> obtenerCerdas() async {
    try {
      final allData = await LocalService.getAllData();
      
      final cerdas = allData.where((data) => 
        data is Map && data['type'] == _sowType
      ).cast<Map<String, dynamic>>().toList();

      // Ordenar por fecha de creación (más recientes primero)
      cerdas.sort((a, b) => 
        b['fecha_creacion'].compareTo(a['fecha_creacion'])
      );

      return cerdas;
    } catch (e) {
      print('❌ Error obteniendo cerdas: $e');
      return [];
    }
  }

  /// OBTENER CERDA POR ID - CORREGIDO
  static Future<Map<String, dynamic>?> obtenerCerdaPorId(String id) async {
    try {
      final data = await LocalService.getData(key: id); // Buscar por ID string
      
      if (data is Map && data['type'] == _sowType) {
        return data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('❌ Error obteniendo cerda por ID: $e');
      return null;
    }
  }

  /// ACTUALIZAR CERDA - CORREGIDO
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
        fechaPartoCalculado = DateTime.parse(cerdaExistente['fecha_monta']).add(const Duration(days: 114));
      }

      final cerdaActualizada = {
        ...cerdaExistente,
        'nombre': nombre ?? cerdaExistente['nombre'],
        'numero_arete': numeroArete ?? cerdaExistente['numero_arete'],
        'fecha_nacimiento': fechaNacimiento?.toIso8601String() ?? cerdaExistente['fecha_nacimiento'],
        'raza': raza ?? cerdaExistente['raza'],
        'estado': estado ?? cerdaExistente['estado'],
        'fecha_monta': fechaMonta?.toIso8601String() ?? cerdaExistente['fecha_monta'],
        'fecha_palpacion': fechaPalpacion?.toIso8601String() ?? cerdaExistente['fecha_palpacion'],
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'observaciones': observaciones ?? cerdaExistente['observaciones'],
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      };

      // ✅ CORREGIDO: Usar el mismo ID para actualizar
      await LocalService.saveData(
        key: id, // Usar el mismo ID
        value: cerdaActualizada,
      );

      // Guardar para sync pendiente si no hay conexión
      final hasConnection = await LocalService.checkConnectivity();
      if (!hasConnection) {
        await LocalService.savePendingSync(
          action: 'update',
          entityType: _sowType,
          data: cerdaActualizada,
        );
      }

      print('✅ Cerda actualizada: ${cerdaActualizada['nombre']}');
    } catch (e) {
      print('❌ Error actualizando cerda: $e');
      rethrow;
    }
  }

  /// ELIMINAR CERDA - CORREGIDO
  static Future<void> eliminarCerda(String id) async {
    try {
      final cerda = await obtenerCerdaPorId(id);
      
      // ✅ CORREGIDO: Eliminar por ID string
      await LocalService.deleteData(key: id);

      // Guardar para sync pendiente si no hay conexión
      final hasConnection = await LocalService.checkConnectivity();
      if (!hasConnection && cerda != null) {
        await LocalService.savePendingSync(
          action: 'delete',
          entityType: _sowType,
          data: {'id': id, ...cerda},
        );
      }

      print('✅ Cerda eliminada: $id');
    } catch (e) {
      print('❌ Error eliminando cerda: $e');
      rethrow;
    }
  }

  /// AGREGAR VACUNA A CERDA - CORREGIDO
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

      // CORREGIDO: Generar ID único para vacuna
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

      // ✅ CORREGIDO: Usar ID de vacuna como clave
      await LocalService.saveData(
        key: vacunaId,
        value: nuevaVacuna,
      );

      print('✅ Vacuna agregada: $nombreVacuna a ${cerda['nombre']}');
    } catch (e) {
      print('❌ Error agregando vacuna: $e');
      rethrow;
    }
  }

  /// OBTENER VACUNAS DE UNA CERDA
  static Future<List<Map<String, dynamic>>> obtenerVacunas(String cerdaId) async {
    try {
      final allData = await LocalService.getAllData();
      
      final vacunas = allData.where((data) => 
        data is Map && 
        data['type'] == _vaccineType &&
        data['cerda_id'] == cerdaId
      ).cast<Map<String, dynamic>>().toList();

      // Ordenar por fecha de creación
      vacunas.sort((a, b) => 
        b['fecha_creacion'].compareTo(a['fecha_creacion'])
      );

      return vacunas;
    } catch (e) {
      print('❌ Error obteniendo vacunas: $e');
      return [];
    }
  }

  /// OBTENER CERDAS POR ESTADO
  static Future<List<Map<String, dynamic>>> obtenerCerdasPorEstado(String estado) async {
    final todasCerdas = await obtenerCerdas();
    return todasCerdas.where((cerda) => cerda['estado'] == estado).toList();
  }

  /// OBTENER PARTOS PRÓXIMOS
  static Future<List<Map<String, dynamic>>> obtenerPartosProximos() async {
    final todasCerdas = await obtenerCerdas();
    final ahora = DateTime.now();
    
    return todasCerdas.where((cerda) {
      if (cerda['fecha_parto_calculado'] == null) return false;
      
      final fechaParto = DateTime.parse(cerda['fecha_parto_calculado']);
      final diasRestantes = fechaParto.difference(ahora).inDays;
      
      return diasRestantes >= 0 && diasRestantes <= 7;
    }).toList();
  }

  /// OBTENER ESTADÍSTICAS
  static Future<Map<String, dynamic>> obtenerEstadisticas() async {
    final cerdas = await obtenerCerdas();
    
    return {
      'total_cerdas': cerdas.length,
      'preñadas': cerdas.where((c) => c['estado'] == 'preñada').length,
      'lactantes': cerdas.where((c) => c['estado'] == 'lactante').length,
      'vacias': cerdas.where((c) => c['estado'] == 'vacía').length,
      'partos_proximos': await obtenerPartosProximos().then((list) => list.length),
    };
  }
}