import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:my_porki/backend/services/auth_service.dart';
import 'package:my_porki/backend/services/local_service.dart';
import 'package:my_porki/backend/services/sow_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      tzdata.initializeTimeZones();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      final iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      final settings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {},
      );

      print('✅ NotificationService inicializado');
    } catch (e) {
      print('❌ Error inicializando NotificationService: $e');
    }
  }

  // MÉTODO NUEVO: Programar notificaciones automáticas para partos y vacunas
  static Future<void> programarNotificacionesAutomaticas() async {
    try {
      print('🔔 Programando notificaciones automáticas...');

      final cerdas = await SowService.obtenerCerdas();
      final ahora = tz.TZDateTime.now(tz.local);

      for (var cerda in cerdas) {
        final nombre = cerda['nombre'] ?? 'Cerda sin nombre';

        // NOTIFICACIONES DE PARTOS - 5 días antes y mismo día
        final fechaPartoStr = cerda['fecha_parto_calculado'];
        if (fechaPartoStr != null) {
          try {
            final fechaParto = DateTime.parse(fechaPartoStr.toString());
            final tzFechaParto = tz.TZDateTime.from(fechaParto, tz.local);
            final diasRestantes = tzFechaParto.difference(ahora).inDays;

            // Notificación 5 días antes
            if (diasRestantes == 5) {
              await _programarNotificacion(
                id: 'parto_${cerda['id']}_5dias',
                title: '🐷 Parto Próximo',
                body: 'Parto de $nombre en 5 días',
                scheduledDate: tzFechaParto.subtract(const Duration(days: 5)),
              );
            }

            // Notificación el mismo día
            if (diasRestantes == 0) {
              await _programarNotificacion(
                id: 'parto_${cerda['id']}_hoy',
                title: '🐷 Parto Hoy',
                body: 'Hoy es el parto de $nombre',
                scheduledDate: tzFechaParto,
              );
            }
          } catch (e) {
            print('❌ Error programando notificación de parto: $e');
          }
        }

        // NOTIFICACIONES DE VACUNAS - Mismo día
        final vacunas = cerda['vacunas'] as List<dynamic>? ?? [];
        for (var vacuna in vacunas) {
          if (vacuna is Map) {
            final dosisProgramadas =
                vacuna['dosis_programadas'] as List<dynamic>? ?? [];
            for (var dosis in dosisProgramadas) {
              if (dosis is Map) {
                final fechaVacunaStr = dosis['fecha'];
                if (fechaVacunaStr != null) {
                  try {
                    final fechaVacuna = DateTime.parse(
                      fechaVacunaStr.toString(),
                    );
                    final tzFechaVacuna = tz.TZDateTime.from(
                      fechaVacuna,
                      tz.local,
                    );
                    final nombreVacuna = vacuna['nombre'] ?? 'Vacuna';
                    final numDosis = dosis['numero_dosis'] ?? 1;

                    // Notificación el día de la vacuna
                    await _programarNotificacion(
                      id: 'vacuna_${cerda['id']}_${nombreVacuna}_$numDosis',
                      title: '💉 Vacuna Hoy',
                      body: '$nombreVacuna (Dosis $numDosis) para $nombre',
                      scheduledDate: tzFechaVacuna,
                    );
                  } catch (e) {
                    print('❌ Error programando notificación de vacuna: $e');
                  }
                }
              }
            }
          }
        }
      }

      print('✅ Notificaciones automáticas programadas');
    } catch (e) {
      print('❌ Error en programarNotificacionesAutomaticas: $e');
    }
  }

  // MÉTODO NUEVO: Mostrar notificación de prueba
  static Future<void> mostrarNotificacionPrueba() async {
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        '🐷 My Porki',
        'Las notificaciones están funcionando correctamente',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'general_channel',
            'Notificaciones My Porki',
            channelDescription: 'Recordatorios de partos y vacunas',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(sound: 'default'),
        ),
      );
      print('✅ Notificación de prueba mostrada');
    } catch (e) {
      print('❌ Error mostrando notificación de prueba: $e');
    }
  }

  // MÉTODO AUXILIAR: Programar notificación individual
  static Future<void> _programarNotificacion({
    required String id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
  }) async {
    // Solo programar si la fecha es en el futuro
    if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
      await _plugin.zonedSchedule(
        id.hashCode,
        title,
        body,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'general_channel',
            'Notificaciones My Porki',
            channelDescription: 'Recordatorios de partos y vacunas',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(sound: 'default'),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('📅 Notificación programada: $title - $scheduledDate');
    }
  }

  /// Obtiene todas las notificaciones pendientes (vacunas, partos, confirmaciones de preñez) - OPTIMIZADO
  static Future<List<Map<String, dynamic>>> getNotificaciones() async {
    try {
      final logged = await AuthService.isLoggedIn();
      if (!logged) return [];

      // CORRECCIÓN: Usar LocalService en lugar de Hive directamente
      final allData = await LocalService.getAllData();
      final ahora = DateTime.now();
      final notificaciones = <Map<String, dynamic>>[];

      for (var item in allData) {
        if (item is Map && item['type'] == 'sow') {
          // Partos próximos
          final fechaPartoStr = item['fecha_parto_calculado'];
          if (fechaPartoStr != null &&
              (item['notificado_parto'] ?? false) == false) {
            final fechaParto = DateTime.tryParse(fechaPartoStr.toString());
            if (fechaParto != null) {
              final diffDias = fechaParto.difference(ahora).inDays;
              if (diffDias >= 0 && diffDias <= 7) {
                notificaciones.add({
                  'tipo': 'parto',
                  'cerda': item,
                  'fecha': fechaParto,
                  'dias_restantes': diffDias,
                });
              }
            }
          }

          // Vacunas pendientes - CORREGIDO
          final vacunas = item['vacunas'] as List? ?? [];
          for (var vacuna in vacunas) {
            if (vacuna is! Map) continue;

            final dosisProgramadas = vacuna['dosis_programadas'] as List? ?? [];
            for (var dosis in dosisProgramadas) {
              if (dosis is! Map) continue;

              final fechaStr = dosis['fecha']?.toString();
              if (fechaStr == null || (dosis['notificado'] ?? false) == true)
                continue;

              final fechaDosis = DateTime.tryParse(fechaStr);
              if (fechaDosis == null) continue;

              final diffDias = fechaDosis.difference(ahora).inDays;
              if (diffDias >= 0 && diffDias <= 7) {
                notificaciones.add({
                  'tipo': 'vacuna',
                  'cerda': item,
                  'vacuna': vacuna,
                  'dosis': dosis,
                  'fecha': fechaDosis,
                  'dias_restantes': diffDias,
                });
              }
            }
          }

          // Confirmación de preñez - CORREGIDO
          final estado = (item['estado'] ?? '').toString().toLowerCase();
          final fechaPrenezStr = item['fecha_prenez'];
          if (estado.contains('preñada') &&
              fechaPrenezStr != null &&
              (item['notificado_prenez'] ?? false) == false) {
            final fechaInseminacion = DateTime.tryParse(
              fechaPrenezStr.toString(),
            );
            if (fechaInseminacion != null) {
              final fechaConfirmacion = fechaInseminacion.add(
                const Duration(days: 21),
              );
              if (ahora.isAfter(fechaConfirmacion) ||
                  ahora.isAtSameMomentAs(fechaConfirmacion)) {
                notificaciones.add({
                  'tipo': 'confirmar_preñez',
                  'cerda': item,
                  'fecha': fechaConfirmacion,
                });
              }
            }
          }
        }
      }

      // Ordenar por fecha más próxima
      notificaciones.sort(
        (a, b) => (a['fecha'] as DateTime).compareTo(b['fecha'] as DateTime),
      );

      print('🔔 Notificaciones encontradas: ${notificaciones.length}');
      return notificaciones;
    } catch (e) {
      print('❌ Error obteniendo notificaciones: $e');
      return [];
    }
  }

  /// Programar todas las notificaciones pendientes - OPTIMIZADO
  static Future<void> scheduleAllNotifications() async {
    try {
      final logged = await AuthService.isLoggedIn();
      if (!logged) return;

      final notis = await getNotificaciones();
      if (notis.isEmpty) {
        print('🔔 No hay notificaciones para programar');
        return;
      }

      int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      for (var noti in notis) {
        try {
          final tipo = noti['tipo'];
          final cerda = noti['cerda'] as Map<String, dynamic>;
          final nombre = cerda['nombre']?.toString() ?? 'Sin nombre';
          final fecha = noti['fecha'] as DateTime;

          // Programar para las 9:00 AM del día correspondiente
          final scheduledDate = tz.TZDateTime(
            tz.local,
            fecha.year,
            fecha.month,
            fecha.day,
            9, // 9:00 AM
            0,
          );

          String titulo = '';
          String cuerpo = '';

          if (tipo == 'parto') {
            final dias = noti['dias_restantes'] ?? 0;
            titulo = 'Parto próximo 🐷';
            cuerpo = dias == 0
                ? '$nombre tiene parto hoy!'
                : '$nombre tiene parto en $dias días';

            // Marcar como notificado
            cerda['notificado_parto'] = true;
          } else if (tipo == 'vacuna') {
            final vacuna = noti['vacuna'] as Map<String, dynamic>? ?? {};
            final dosis = noti['dosis'] as Map<String, dynamic>? ?? {};
            final vacunaNombre = vacuna['nombre']?.toString() ?? 'Vacuna';
            final dosisNum = dosis['numero_dosis']?.toString() ?? '';

            titulo = 'Vacuna pendiente 💉';
            cuerpo =
                '$nombre - $vacunaNombre ${dosisNum.isNotEmpty ? '- Dosis $dosisNum' : ''}';

            // Marcar como notificado
            dosis['notificado'] = true;
          } else if (tipo == 'confirmar_preñez') {
            titulo = 'Confirmar preñez 🐷';
            cuerpo = 'Confirma si $nombre quedó preñada (21 días después)';

            // Marcar como notificado
            cerda['notificado_prenez'] = true;
          }

          // Si la fecha ya pasó, mostrar notificación inmediata
          if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
            await _plugin.show(
              id,
              titulo,
              cuerpo,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'general_channel',
                  'Notificaciones My Porki',
                  channelDescription:
                      'Recordatorios de partos, vacunas y preñez',
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: true,
                ),
                iOS: const DarwinNotificationDetails(sound: 'default'),
              ),
            );
            print('📱 Notificación mostrada: $titulo');
          } else {
            // Programar notificación futura
            await _plugin.zonedSchedule(
              id,
              titulo,
              cuerpo,
              scheduledDate,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'general_channel',
                  'Notificaciones My Porki',
                  channelDescription:
                      'Recordatorios de partos, vacunas y preñez',
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: true,
                ),
                iOS: const DarwinNotificationDetails(sound: 'default'),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
            print(
              '⏰ Notificación programada: $titulo para ${scheduledDate.toString()}',
            );
          }

          // Guardar cambios en Hive para que no se repita la notificación
          final cerdaId = cerda['id']?.toString();
          if (cerdaId != null) {
            await LocalService.saveData(key: cerdaId, value: cerda);
          }

          id++;
        } catch (e) {
          print('❌ Error programando notificación individual: $e');
        }
      }
    } catch (e) {
      print('❌ Error en scheduleAllNotifications: $e');
    }
  }

  /// Cancelar todas las notificaciones
  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
      print('🔕 Todas las notificaciones canceladas');
    } catch (e) {
      print('❌ Error cancelando notificaciones: $e');
    }
  }

  /// Obtener notificaciones pendientes para la pantalla de notificaciones
  static Future<List<Map<String, dynamic>>>
  getNotificacionesParaPantalla() async {
    try {
      final notis = await getNotificaciones();

      // Formatear para mostrar en la UI
      return notis.map((noti) {
        final tipo = noti['tipo'];
        final cerda = noti['cerda'] as Map<String, dynamic>;
        final nombre = cerda['nombre']?.toString() ?? 'Sin nombre';
        final fecha = noti['fecha'] as DateTime;
        final diasRestantes = noti['dias_restantes'];

        String titulo = '';
        String descripcion = '';
        String icono = '';

        if (tipo == 'parto') {
          titulo = 'Parto próximo';
          descripcion = diasRestantes == 0
              ? '$nombre tiene parto hoy'
              : '$nombre tiene parto en $diasRestantes días';
          icono = '🐷';
        } else if (tipo == 'vacuna') {
          final vacuna = noti['vacuna'] as Map<String, dynamic>? ?? {};
          final dosis = noti['dosis'] as Map<String, dynamic>? ?? {};
          final vacunaNombre = vacuna['nombre']?.toString() ?? 'Vacuna';
          final dosisNum = dosis['numero_dosis']?.toString() ?? '';

          titulo = 'Vacuna pendiente';
          descripcion =
              '$nombre - $vacunaNombre ${dosisNum.isNotEmpty ? '(Dosis $dosisNum)' : ''}';
          icono = '💉';
        } else if (tipo == 'confirmar_preñez') {
          titulo = 'Confirmar preñez';
          descripcion = 'Verifica si $nombre quedó preñada';
          icono = '🔍';
        }

        return {
          'titulo': titulo,
          'descripcion': descripcion,
          'icono': icono,
          'fecha': fecha,
          'dias_restantes': diasRestantes,
          'cerda_nombre': nombre,
          'tipo': tipo,
        };
      }).toList();
    } catch (e) {
      print('❌ Error obteniendo notificaciones para pantalla: $e');
      return [];
    }
  }
}
