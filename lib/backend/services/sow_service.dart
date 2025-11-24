import 'local_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SowService {
  static const String _sowType = 'sow';
  static final _firestore = FirebaseFirestore.instance;

  /// Inicializar el servicio
  static Future<void> initialize() async {
    await LocalService.initialize();
    print('✅ SowService inicializado');
  }

  /// AGREGAR NUEVA CERDA
  static Future<Map<String, dynamic>> agregarCerda({
    required String idCtrl,
    required String nombre,
    DateTime? fechaPrenez,
    List<Map<String, dynamic>>? partos,
    List<Map<String, dynamic>>? vacunas,
    String? estado,
  }) async {
    try {
      final String cerdaId = idCtrl.isNotEmpty
          ? idCtrl
          : 'sow_${DateTime.now().millisecondsSinceEpoch}';
      final bool prenada = fechaPrenez != null;
      final fechaPartoCalculado =
          prenada ? fechaPrenez.add(const Duration(days: 114)) : null;

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
      };

      // Guardar localmente
      await LocalService.saveData(key: cerdaId, value: nuevaCerda);

      // Sincronizar con Firestore si hay conexión
      final hasConnection = await LocalService.checkConnectivity();
      if (hasConnection) {
        await _firestore.collection('sows').doc(cerdaId).set(nuevaCerda);
      } else {
        await LocalService.savePendingSync(
          action: 'create',
          entityType: _sowType,
          data: nuevaCerda,
        );
      }

      print('✅ Cerda agregada: $nombre');
      return nuevaCerda;
    } catch (e) {
      print('❌ Error agregando cerda: $e');
      rethrow;
    }
  }

  static Future<void> actualizarCerda({
    required String id,
    String? nombre,
    DateTime? fechaPrenez,
    List<Map<String, dynamic>>? partos,
    List<Map<String, dynamic>>? vacunas,
    String? estado,
  }) async {
    try {
      final cerda = await obtenerCerda(id);
      if (cerda == null) throw Exception('Cerda no encontrada');

      // FECHA PARTO CALCULADA
      DateTime? fechaPartoCalculado;
      if (fechaPrenez != null) {
        fechaPartoCalculado = fechaPrenez.add(const Duration(days: 114));
      } else {
        final fExist = DateTime.tryParse(cerda['fecha_prenez'] ?? '');
        fechaPartoCalculado =
            fExist != null ? fExist.add(const Duration(days: 114)) : null;
      }

      // VACUNAS
      final vacunasProcesadas = _procesarVacunas(vacunas, cerda);

      // CORRECCIÓN REAL DEL ESTADO - LÓGICA SIMPLIFICADA
      final estadoFinal = estado ?? 
          ((fechaPrenez != null || cerda['fecha_prenez'] != null) 
              ? 'Preñada' 
              : 'No preñada');

      // OBJETO ACTUALIZADO
      final cerdaActualizada = {
        ...cerda,
        'nombre': nombre ?? cerda['nombre'],
        'fecha_prenez': fechaPrenez?.toIso8601String() ?? cerda['fecha_prenez'],
        'fecha_parto_calculado': fechaPartoCalculado?.toIso8601String(),
        'partos': partos ?? List<Map<String, dynamic>>.from(cerda['partos'] ?? []),
        'vacunas': vacunasProcesadas.isNotEmpty
            ? vacunasProcesadas
            : List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []),
        'estado': estadoFinal, // Estado corregido
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      };

      // Guardar local
      await LocalService.saveData(key: id, value: cerdaActualizada);

      // Guardar Firestore
      final hasConnection = await LocalService.checkConnectivity();
      if (hasConnection) {
        await _firestore.collection('sows').doc(id).set(cerdaActualizada);
      } else {
        await LocalService.savePendingSync(
          action: 'update',
          entityType: _sowType,
          data: cerdaActualizada,
        );
      }

      print('✅ Cerda actualizada correctamente: ${cerdaActualizada['nombre']}');
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

          if (vacExistente.isNotEmpty && vacExistente['dosis_programadas'] != null) {
            dosisProgramadas = List<Map<String, dynamic>>.from(vacExistente['dosis_programadas']);
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

  /// OBTENER CERDA POR ID (Hive + Firestore)
  static Future<Map<String, dynamic>?> obtenerCerda(String id) async {
    try {
      // 1. Intentar Hive
      final local = await LocalService.getData(key: id);
      if (local != null && local['type'] == _sowType) {
        return Map<String, dynamic>.from(local);
      }

      // 2. Intentar Firestore
      final doc = await _firestore.collection('sows').doc(id).get();
      if (doc.exists) {
        final data = doc.data()!;
        data['id'] = doc.id;
        data['type'] = _sowType;
        data['partos'] ??= [];
        data['vacunas'] ??= [];

        // Guardar en Hive
        await LocalService.saveData(key: doc.id, value: data);

        return data;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo cerda: $e');
      return null;
    }
  }

  /// OBTENER TODAS LAS CERDAS - CORREGIDO
  static Future<List<Map<String, dynamic>>> obtenerCerdas() async {
    try {
      // CORREGIDO: Usar LocalService.getAllData() que ya maneja Hive correctamente
      final allData = await LocalService.getAllData();
      final cerdas = allData
          .where((data) => data is Map && data['type'] == _sowType)
          .cast<Map<String, dynamic>>()
          .toList();

      // Ordenar por fecha de creación (más reciente primero)
      cerdas.sort((a, b) {
        final fechaA = DateTime.tryParse(a['fecha_creacion'] ?? '') ?? DateTime.now();
        final fechaB = DateTime.tryParse(b['fecha_creacion'] ?? '') ?? DateTime.now();
        return fechaB.compareTo(fechaA);
      });

      print('✅ Cerdas encontradas en obtenerCerdas: ${cerdas.length}');
      return cerdas;
    } catch (e) {
      print('❌ Error en obtenerCerdas: $e');
      return [];
    }
  }

  /// ELIMINAR CERDA
  static Future<void> eliminarCerda(String id) async {
    final cerda = await obtenerCerda(id);
    if (cerda == null) return;

    await LocalService.deleteData(key: id);

    final hasConnection = await LocalService.checkConnectivity();
    if (hasConnection) {
      await _firestore.collection('sows').doc(id).delete();
    } else {
      await LocalService.savePendingSync(
        action: 'delete',
        entityType: _sowType,
        data: cerda,
      );
    }

    print('✅ Cerda eliminada: $id');
  }

  /// OBTENER PARTOS PRÓXIMOS
  static Future<List<Map<String, dynamic>>> obtenerPartosProximos({int dias = 7}) async {
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
            proximos.add({
              ...cerda,
              'dias_restantes': diff,
            });
          }
        } catch (e) {
          print('Error parseando fecha parto de ${cerda['nombre']}: $e');
        }
      }
    }

    proximos.sort((a, b) => (a['dias_restantes'] as int).compareTo(b['dias_restantes'] as int));
    return proximos;
  }

  /// OBTENER TOTAL DE LECHONES DE UNA CERDA
  static int totalLechones(Map<String, dynamic> cerda) {
    final partos = cerda['partos'] as List<dynamic>? ?? [];
    int total = 0;
    for (var parto in partos) {
      final numLechones = parto['num_lechones'];
      total += numLechones is int ? numLechones : int.tryParse('$numLechones') ?? 0;
    }
    return total;
  }

  /// NUEVO MÉTODO: OBTENER ESTADÍSTICAS PARA EL RESUMEN
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

      for (var cerda in cerdas) {
        // Contar preñadas
        final estado = (cerda['estado'] ?? '').toString().toLowerCase();
        final fechaPrenez = cerda['fecha_prenez'];
        final fechaPartoCalc = cerda['fecha_parto_calculado'];
        
        if (estado.contains('preñ') || 
            estado.contains('pregnant') || 
            fechaPrenez != null ||
            (fechaPartoCalc != null && DateTime.parse(fechaPartoCalc.toString()).isAfter(ahora))) {
          prenadas++;
        }

        // Contar lechones
        final partos = cerda['partos'] as List<dynamic>? ?? [];
        for (var parto in partos) {
          if (parto is Map) {
            final numLechones = parto['num_lechones'];
            totalLechones += (numLechones is int ? numLechones : int.tryParse('$numLechones') ?? 0);

            // Contar partos hoy
            final fechaPartoStr = parto['fecha'];
            if (fechaPartoStr != null) {
              try {
                final fechaParto = DateTime.parse(fechaPartoStr.toString());
                if (fechaParto.year == ahora.year && 
                    fechaParto.month == ahora.month && 
                    fechaParto.day == ahora.day) {
                  partosHoy++;
                }
              } catch (e) {
                // Ignorar errores de parseo
              }
            }
          }
        }

        // Contar partos pendientes
        if (fechaPartoCalc != null) {
          try {
            final fechaParto = DateTime.parse(fechaPartoCalc.toString());
            if (!fechaParto.isBefore(ahora)) {
              partosPendientes++;
            }
          } catch (e) {
            // Ignorar errores de parseo
          }
        }

        // Contar vacunas hoy
        final vacunas = cerda['vacunas'] as List<dynamic>? ?? [];
        for (var vac in vacunas) {
          if (vac is Map) {
            final dosisProgramadas = vac['dosis_programadas'] as List<dynamic>? ?? [];
            for (var dosis in dosisProgramadas) {
              if (dosis is Map) {
                final fechaVacStr = dosis['fecha'];
                if (fechaVacStr != null) {
                  try {
                    final fechaVac = DateTime.parse(fechaVacStr.toString());
                    if (fechaVac.year == ahora.year && 
                        fechaVac.month == ahora.month && 
                        fechaVac.day == ahora.day) {
                      vacunasHoy++;
                    }
                  } catch (e) {
                    // Ignorar errores de parseo
                  }
                }
              }
            }
          }
        }
      }

      return {
        'totalCerdas': totalCerdas,
        'prenadas': prenadas,
        'totalLechones': totalLechones,
        'partosHoy': partosHoy,
        'partosPendientes': partosPendientes,
        'vacunasHoy': vacunasHoy,
      };
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
}