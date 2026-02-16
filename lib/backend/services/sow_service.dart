import 'local_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

class SowService {
  static const String _sowType = 'sow';
  static final _firestore = FirebaseFirestore.instance;

  // Caja de Hive para acceso directo
  static Box? _porkiBox;

  /// Inicializar el servicio
  static Future<void> initialize() async {
    await LocalService.initialize();
    _porkiBox = await Hive.openBox('porki_data');
    print('✅ SowService inicializado con caja Hive');
  }

  /// Obtener la caja de Hive (con inicialización si es necesario)
  static Future<Box> _getBox() async {
    if (_porkiBox == null || !_porkiBox!.isOpen) {
      _porkiBox = await Hive.openBox('porki_data');
    }
    return _porkiBox!;
  }

  /// AGREGAR NUEVA CERDA - VERSIÓN MEJORADA
  static Future<Map<String, dynamic>> agregarCerda({
    required String idCtrl,
    required String nombre,
    DateTime? fechaPrenez,
    List<Map<String, dynamic>>? partos,
    List<Map<String, dynamic>>? vacunas,
    String? estado,
  }) async {
    try {
      final box = await _getBox();
      final String cerdaId = idCtrl.isNotEmpty
          ? idCtrl
          : 'sow_${DateTime.now().millisecondsSinceEpoch}';

      final bool prenada = fechaPrenez != null;
      final fechaPartoCalculado = prenada
          ? fechaPrenez.add(const Duration(days: 114))
          : null;

      final vacunasProcesadas = _procesarVacunas(vacunas);

      final nuevaCerda = {
        'id': cerdaId,
        'hiveKey': cerdaId,
        'type': _sowType,
        'nombre': nombre,
        'estado': estado ?? (prenada ? 'Preñada' : 'No preñada'),
        'fecha_prenez': fechaPrenez?.toIso8601String(),
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'partos': partos ?? [],
        'vacunas': vacunasProcesadas,
        'fecha_creacion': DateTime.now().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'synced': false, // Para sincronización
      };

      print('🔄 Guardando cerda localmente: $nombre');

      // 1. Guardar en Hive DIRECTAMENTE (más rápido y confiable)
      await box.put(cerdaId, nuevaCerda);
      print('✅ Cerda guardada en Hive: $cerdaId');

      // 2. Sincronizar con Firestore si hay conexión
      final hasConnection = await LocalService.checkConnectivity();
      if (hasConnection) {
        print('🌐 Sincronizando con Firestore...');
        try {
          await _firestore.collection('sows').doc(cerdaId).set(nuevaCerda);

          // Marcar como sincronizada
          nuevaCerda['synced'] = true;
          nuevaCerda['lastSync'] = DateTime.now().toIso8601String();
          await box.put(cerdaId, nuevaCerda);

          print('✅ Cerda sincronizada con Firestore: $nombre');
        } catch (firestoreError) {
          print('⚠️ Error sincronizando con Firestore: $firestoreError');
          // Guardar como pendiente de sincronización
          await LocalService.savePendingSync(
            action: 'create',
            entityType: _sowType,
            data: nuevaCerda,
          );
        }
      } else {
        print('📴 Sin conexión, guardando como pendiente');
        await LocalService.savePendingSync(
          action: 'create',
          entityType: _sowType,
          data: nuevaCerda,
        );
      }

      print('✅ Cerda agregada completamente: $nombre');
      return nuevaCerda;
    } catch (e) {
      print('❌ Error agregando cerda: $e');
      rethrow;
    }
  }

  /// ACTUALIZAR CERDA - VERSIÓN MEJORADA
  static Future<void> actualizarCerda({
    required String id,
    String? nombre,
    DateTime? fechaPrenez,
    List<Map<String, dynamic>>? partos,
    List<Map<String, dynamic>>? vacunas,
    String? estado,
  }) async {
    try {
      final box = await _getBox();
      final cerda = await obtenerCerda(id);

      if (cerda == null) {
        print('❌ Cerda no encontrada: $id');
        throw Exception('Cerda no encontrada');
      }

      print('🔄 Actualizando cerda: ${cerda['nombre']}');

      // FECHA PARTO CALCULADA
      DateTime? fechaPartoCalculado;
      if (fechaPrenez != null) {
        fechaPartoCalculado = fechaPrenez.add(const Duration(days: 114));
      } else {
        final fExist = DateTime.tryParse(cerda['fecha_prenez'] ?? '');
        fechaPartoCalculado = fExist != null
            ? fExist.add(const Duration(days: 114))
            : null;
      }

      // VACUNAS
      final vacunasProcesadas = _procesarVacunas(vacunas, cerda);

      // CORRECCIÓN DEL ESTADO
      final estadoFinal =
          estado ??
          ((fechaPrenez != null || cerda['fecha_prenez'] != null)
              ? 'Preñada'
              : 'No preñada');

      // OBJETO ACTUALIZADO
      final cerdaActualizada = {
        ...cerda,
        'nombre': nombre ?? cerda['nombre'],
        'fecha_prenez': fechaPrenez?.toIso8601String() ?? cerda['fecha_prenez'],
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'partos':
            partos ?? List<Map<String, dynamic>>.from(cerda['partos'] ?? []),
        'vacunas': vacunasProcesadas.isNotEmpty
            ? vacunasProcesadas
            : List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []),
        'estado': estadoFinal,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'synced': false, // Marcar como no sincronizada
      };

      // 1. Guardar en Hive DIRECTAMENTE
      await box.put(id, cerdaActualizada);

      print('✅ Cerda actualizada en Hive: ${cerdaActualizada['nombre']}');

      // 2. Sincronizar con Firestore
      final hasConnection = await LocalService.checkConnectivity();
      if (hasConnection) {
        print('🌐 Sincronizando actualización con Firestore...');
        try {
          await _firestore.collection('sows').doc(id).set(cerdaActualizada);

          // Marcar como sincronizada
          cerdaActualizada['synced'] = true;
          cerdaActualizada['lastSync'] = DateTime.now().toIso8601String();
          await box.put(id, cerdaActualizada);

          print('✅ Actualización sincronizada con Firestore');
        } catch (firestoreError) {
          print('⚠️ Error sincronizando actualización: $firestoreError');
          await LocalService.savePendingSync(
            action: 'update',
            entityType: _sowType,
            data: cerdaActualizada,
          );
        }
      } else {
        print('📴 Sin conexión, guardando actualización como pendiente');
        await LocalService.savePendingSync(
          action: 'update',
          entityType: _sowType,
          data: cerdaActualizada,
        );
      }

      print('✅ Cerda actualizada completamente');
    } catch (e) {
      print('❌ Error actualizando cerda: $e');
      rethrow;
    }
  }

  /// PROCESAR VACUNAS
  static List<Map<String, dynamic>> _procesarVacunas(
    List<Map<String, dynamic>>? vacunas, [
    Map<String, dynamic>? cerdaExistente,
  ]) {
    final vacunasProcesadas = <Map<String, dynamic>>[];

    if (vacunas != null) {
      for (var v in vacunas) {
        final int dosis = (v['dosis'] is int)
            ? v['dosis']
            : int.tryParse(v['dosis'].toString()) ?? 1;

        final int frecuencia = (v['frecuencia_dias'] is int)
            ? v['frecuencia_dias']
            : int.tryParse(v['frecuencia_dias'].toString()) ?? 30;

        List<Map<String, dynamic>> dosisProgramadas = [];

        if (cerdaExistente != null && cerdaExistente['vacunas'] != null) {
          final vacExistente = (cerdaExistente['vacunas'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere(
                (vx) => vx['nombre'] == v['nombre'],
                orElse: () => {},
              );

          if (vacExistente.isNotEmpty &&
              vacExistente['dosis_programadas'] != null) {
            dosisProgramadas = List<Map<String, dynamic>>.from(
              vacExistente['dosis_programadas'],
            );
          }
        }

        final now = DateTime.now();
        for (int i = dosisProgramadas.length; i < dosis; i++) {
          dosisProgramadas.add({
            'numero_dosis': i + 1,
            'fecha': now.add(Duration(days: i * frecuencia)).toIso8601String(),
          });
        }

        vacunasProcesadas.add({
          'nombre': v['nombre'] ?? 'Vacuna',
          'dosis': dosis,
          'frecuencia_dias': frecuencia,
          'dosis_programadas': dosisProgramadas,
        });
      }
    }

    return vacunasProcesadas;
  }

  /// OBTENER CERDA POR ID - VERSIÓN MEJORADA
  static Future<Map<String, dynamic>?> obtenerCerda(String id) async {
    try {
      final box = await _getBox();

      // 1. Intentar Hive primero (más rápido)
      final localData = box.get(id);

      if (localData != null &&
          localData is Map &&
          localData['type'] == _sowType) {
        print('✅ Cerda encontrada en Hive: $id');
        return Map<String, dynamic>.from(localData);
      }

      // 2. Si no está en Hive, buscar en Firestore
      print('🔍 Cerda no encontrada en Hive, buscando en Firestore...');
      final doc = await _firestore.collection('sows').doc(id).get();

      if (doc.exists) {
        final data = doc.data()!;
        final cerdaData = {
          ...data,
          'id': doc.id,
          'type': _sowType,
          'partos': data['partos'] ?? [],
          'vacunas': data['vacunas'] ?? [],
          'synced': true,
          'lastSync': DateTime.now().toIso8601String(),
        };

        // Guardar en Hive para futuras consultas
        await box.put(doc.id, cerdaData);

        print('✅ Cerda cargada desde Firestore y guardada en Hive: $id');
        return cerdaData;
      }

      print('❌ Cerda no encontrada: $id');
      return null;
    } catch (e) {
      print('❌ Error obteniendo cerda $id: $e');
      return null;
    }
  }

  /// OBTENER TODAS LAS CERDAS - VERSIÓN MEJORADA Y REACTIVA
  static Future<List<Map<String, dynamic>>> obtenerCerdas({
    bool forceRefresh = false,
  }) async {
    try {
      final box = await _getBox();

      print('🔄 === LLAMANDO obtenerCerdas() ===');

      if (forceRefresh) {
        print('🔍 Forzando actualización desde Firestore...');
        await _sincronizarTodasCerdas();
      }

      // Obtener todas las cerdas de Hive
      final allData = <Map<String, dynamic>>[];

      for (var key in box.keys) {
        final value = box.get(key);
        if (value is Map && value['type'] == _sowType) {
          final cerda = <String, dynamic>{};
          value.forEach((k, v) => cerda[k.toString()] = v);
          allData.add(cerda);
        }
      }

      print('📦 Cerdas encontradas en Hive: ${allData.length}');

      // Ordenar por fecha de creación (más reciente primero)
      allData.sort((a, b) {
        final fechaA =
            DateTime.tryParse(a['fecha_creacion'] ?? '') ?? DateTime.now();
        final fechaB =
            DateTime.tryParse(b['fecha_creacion'] ?? '') ?? DateTime.now();
        return fechaB.compareTo(fechaA);
      });

      return allData;
    } catch (e) {
      print('❌ Error en obtenerCerdas: $e');
      return [];
    }
  }

  /// SINCRONIZAR TODAS LAS CERDAS DESDE FIRESTORE
  static Future<void> _sincronizarTodasCerdas() async {
    try {
      final box = await _getBox();
      final hasConnection = await LocalService.checkConnectivity();

      if (!hasConnection) {
        print('📴 Sin conexión, no se puede sincronizar');
        return;
      }

      print('🌐 Sincronizando cerdas desde Firestore...');
      final snapshot = await _firestore.collection('sows').get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sowData = {
          ...data,
          'id': doc.id,
          'type': _sowType,
          'synced': true,
          'lastSync': DateTime.now().toIso8601String(),
        };

        await box.put(doc.id, sowData);
      }

      print('✅ Sincronizadas ${snapshot.docs.length} cerdas desde Firestore');
    } catch (e) {
      print('❌ Error sincronizando cerdas: $e');
    }
  }

  /// ELIMINAR CERDA - VERSIÓN MEJORADA
  static Future<void> eliminarCerda(String id) async {
    try {
      final box = await _getBox();
      final cerda = await obtenerCerda(id);

      if (cerda == null) {
        print('⚠️ Cerda no encontrada para eliminar: $id');
        return;
      }

      print('🗑️ Eliminando cerda: ${cerda['nombre']}');

      // 1. Eliminar de Hive
      await box.delete(id);
      print('✅ Cerda eliminada de Hive: $id');

      // 2. Sincronizar con Firestore
      final hasConnection = await LocalService.checkConnectivity();
      if (hasConnection) {
        try {
          await _firestore.collection('sows').doc(id).delete();
          print('✅ Cerda eliminada de Firestore: $id');
        } catch (firestoreError) {
          print('⚠️ Error eliminando de Firestore: $firestoreError');
          await LocalService.savePendingSync(
            action: 'delete',
            entityType: _sowType,
            data: {'id': id, 'type': _sowType},
          );
        }
      } else {
        print('📴 Sin conexión, guardando eliminación como pendiente');
        await LocalService.savePendingSync(
          action: 'delete',
          entityType: _sowType,
          data: {'id': id, 'type': _sowType},
        );
      }
    } catch (e) {
      print('❌ Error eliminando cerda: $e');
      rethrow;
    }
  }

  /// OBTENER PARTOS PRÓXIMOS - VERSIÓN MEJORADA
  static Future<List<Map<String, dynamic>>> obtenerPartosProximos({
    int dias = 7,
  }) async {
    try {
      final cerdas = await obtenerCerdas();
      final ahora = DateTime.now();
      final proximos = <Map<String, dynamic>>[];

      for (var cerda in cerdas) {
        final fechaPartoStr = cerda['fecha_parto_calculado'];

        if (fechaPartoStr != null) {
          try {
            final fechaParto = DateTime.parse(fechaPartoStr.toString());
            final diff = fechaParto.difference(ahora).inDays;

            if (diff >= 0 && diff <= dias) {
              proximos.add({...cerda, 'dias_restantes': diff});
            }
          } catch (e) {
            print('⚠️ Error parseando fecha parto de ${cerda['nombre']}: $e');
          }
        }
      }

      proximos.sort(
        (a, b) =>
            (a['dias_restantes'] as int).compareTo(b['dias_restantes'] as int),
      );

      print('📅 Partos próximos encontrados: ${proximos.length}');
      return proximos;
    } catch (e) {
      print('❌ Error obteniendo partos próximos: $e');
      return [];
    }
  }

  /// OBTENER TOTAL DE LECHONES DE UNA CERDA - RENOMBRADO PARA EVITAR CONFLICTO
  static int calcularTotalLechones(Map<String, dynamic> cerda) {
    try {
      final partos = cerda['partos'] as List<dynamic>? ?? [];
      int total = 0;
      for (var parto in partos) {
        final numLechones = parto['num_lechones'];
        total += numLechones is int
            ? numLechones
            : int.tryParse('$numLechones') ?? 0;
      }
      return total;
    } catch (e) {
      print('❌ Error calculando lechones: $e');
      return 0;
    }
  }

  /// OBTENER ESTADÍSTICAS PARA EL RESUMEN - VERSIÓN CORREGIDA
  static Future<Map<String, int>> obtenerEstadisticasResumen() async {
    try {
      final cerdas = await obtenerCerdas();
      final ahora = DateTime.now();

      int totalCerdas = cerdas.length;
      int prenadas = 0;
      int totalLechones = 0;
      int partosHoy = 0;
      int partosPendientes = 0;
      int vacunasHoy = 0;

      print('📊 Calculando estadísticas para ${totalCerdas} cerdas...');

      for (var cerda in cerdas) {
        // Contar preñadas
        final estado = (cerda['estado'] ?? '').toString().toLowerCase();
        final fechaPrenez = cerda['fecha_prenez'];
        final fechaPartoCalc = cerda['fecha_parto_calculado'];

        if (estado.contains('preñ') ||
            estado.contains('pregnant') ||
            fechaPrenez != null ||
            (fechaPartoCalc != null &&
                DateTime.tryParse(fechaPartoCalc.toString())?.isAfter(ahora) ==
                    true)) {
          prenadas++;
        }

        // Contar lechones - USANDO MÉTODO RENOMBRADO
        totalLechones += calcularTotalLechones(cerda);

        // Contar partos hoy
        final partos = cerda['partos'] as List<dynamic>? ?? [];
        for (var parto in partos) {
          if (parto is Map) {
            final fechaPartoStr = parto['fecha'];
            if (fechaPartoStr != null) {
              final fechaParto = DateTime.tryParse(fechaPartoStr.toString());
              if (fechaParto != null &&
                  fechaParto.year == ahora.year &&
                  fechaParto.month == ahora.month &&
                  fechaParto.day == ahora.day) {
                partosHoy++;
              }
            }
          }
        }

        // Contar partos pendientes
        if (fechaPartoCalc != null) {
          final fechaParto = DateTime.tryParse(fechaPartoCalc.toString());
          if (fechaParto != null && !fechaParto.isBefore(ahora)) {
            partosPendientes++;
          }
        }

        // Contar vacunas hoy
        final vacunas = cerda['vacunas'] as List<dynamic>? ?? [];
        for (var vac in vacunas) {
          if (vac is Map) {
            final dosisProgramadas =
                vac['dosis_programadas'] as List<dynamic>? ?? [];
            for (var dosis in dosisProgramadas) {
              if (dosis is Map) {
                final fechaVacStr = dosis['fecha'];
                if (fechaVacStr != null) {
                  final fechaVac = DateTime.tryParse(fechaVacStr.toString());
                  if (fechaVac != null &&
                      fechaVac.year == ahora.year &&
                      fechaVac.month == ahora.month &&
                      fechaVac.day == ahora.day) {
                    vacunasHoy++;
                  }
                }
              }
            }
          }
        }
      }

      final stats = {
        'totalCerdas': totalCerdas,
        'prenadas': prenadas,
        'totalLechones': totalLechones,
        'partosHoy': partosHoy,
        'partosPendientes': partosPendientes,
        'vacunasHoy': vacunasHoy,
      };

      print('✅ Estadísticas calculadas: $stats');
      return stats;
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {
        'totalCerdas': 0,
        'prenadas': 0,
        'totalLechones': 0,
        'partosHoy': 0,
        'partosPendientes': 0,
        'vacunasHoy': 0,
      };
    }
  }

  /// FORZAR SINCRONIZACIÓN (para usar desde HomeScreen)
  static Future<void> forzarSincronizacion() async {
    await _sincronizarTodasCerdas();
  }
}
