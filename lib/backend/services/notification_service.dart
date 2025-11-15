import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

/// NotificationService: implementación simple con `flutter_local_notifications`.
///
/// Este servicio usa show() para notificaciones inmediatas y proporciona
/// métodos para consultar partos próximos desde Hive.
///
/// Para programaciones recurrentes confiables en producción, considera integrar
/// `timezone` y usar `zonedSchedule`, o implementar un servicio en segundo plano.

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Inicializa el plugin de notificaciones y timezone.
  static Future<void> initialize() async {
    // Inicializar timezone
    tzdata.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Manejo cuando el usuario interactúa con la notificación
      },
    );
  }

  /// Lee Hive y devuelve partos próximos en los próximos 7 días.
  static Future<List<Map<String, dynamic>>> getPartosProximos() async {
    try {
      final box = await Hive.openBox('porki_data');
      final allData = box.values.toList();
      final ahora = DateTime.now();

      final proximos = <Map<String, dynamic>>[];

      for (var item in allData) {
        if (item is Map &&
            item['type'] == 'sow' &&
            item['fecha_parto_calculado'] != null) {
          final fecha = DateTime.tryParse(item['fecha_parto_calculado']);
          if (fecha != null) {
            final dias = fecha.difference(ahora).inDays;
            if (dias >= 0 && dias <= 7) {
              proximos.add({
                'mensaje': 'Parto próximo',
                'prioridad': dias <= 2 ? 'alta' : 'media',
                'dias_restantes': dias,
                'fecha_parto': fecha.toIso8601String(),
                'cerda': item,
              });
            }
          }
        }
      }

      return proximos;
    } catch (e) {
      return [];
    }
  }

  /// Programa notificaciones para partos próximos en la fecha exacta.
  /// Las notificaciones se mostrarán a las 09:00 del día del parto.
  static Future<void> scheduleBirthNotifications() async {
    final proximos = await getPartosProximos();
    int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    for (var p in proximos) {
      try {
        final nombreCerda = p['cerda']?['nombre'] ?? 'Sin nombre';
        final fechaParto = DateTime.parse(p['fecha_parto']);
        final diasRestantes = p['dias_restantes'] ?? 0;

        // Programar para las 09:00 del día del parto
        final scheduledDate = tz.TZDateTime(
          tz.local,
          fechaParto.year,
          fechaParto.month,
          fechaParto.day,
          9,
          0,
        );

        // Si la fecha ya pasó, mostrar inmediatamente
        if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
          await _plugin.show(
            id,
            'Parto próximo',
            'Cerda: $nombreCerda — ¡Parto hoy!',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'partos_channel',
                'Partos',
                channelDescription: 'Recordatorios de partos',
                importance: Importance.max,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            payload: p['cerda']?.toString(),
          );
        } else {
          // Programar para la fecha exacta
          await _plugin.zonedSchedule(
            id,
            'Parto próximo',
            'Cerda: $nombreCerda — Parto en $diasRestantes días',
            scheduledDate,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'partos_channel',
                'Partos',
                channelDescription: 'Recordatorios de partos',
                importance: Importance.max,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: p['cerda']?.toString(),
          );
          print(
            '📅 Notificación de parto programada para: $nombreCerda - ${scheduledDate.toIso8601String()}',
          );
        }

        id++;
      } catch (e) {
        print('❌ Error programando notificación de parto: $e');
      }
    }
  }

  /// Programa recordatorios para vacunas en las fechas exactas.
  /// Las notificaciones se mostrarán a las 09:00 de cada fecha de dosis.
  static Future<void> scheduleVaccineReminders(
    Map<String, dynamic> vacuna,
  ) async {
    try {
      final nombre = vacuna['nombre'] ?? vacuna['nombre_vacuna'] ?? 'Vacuna';
      final dosisProgramadas =
          vacuna['dosis_programadas'] as List? ??
          vacuna['dosis'] as List? ??
          [];
      int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

      for (var d in dosisProgramadas) {
        final fechaStr =
            d['fecha_programada'] ?? d['fecha'] ?? d['fecha_primer_dosis'];
        if (fechaStr == null) continue;
        final fecha = DateTime.tryParse(fechaStr.toString());
        if (fecha == null) continue;
        final dosis = d['numero_dosis'] ?? '';

        try {
          // Programar para las 09:00 del día de la dosis
          final scheduledDate = tz.TZDateTime(
            tz.local,
            fecha.year,
            fecha.month,
            fecha.day,
            9,
            0,
          );

          // Si la fecha ya pasó, mostrar inmediatamente
          if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
            await _plugin.show(
              id,
              'Vacuna pendiente',
              '$nombre - Dosis $dosis (hoy)',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'vacunas_channel',
                  'Vacunas',
                  channelDescription: 'Recordatorios de vacunas',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
                iOS: DarwinNotificationDetails(),
              ),
            );
          } else {
            // Programar para la fecha exacta
            await _plugin.zonedSchedule(
              id,
              'Vacuna pendiente',
              '$nombre - Dosis $dosis',
              scheduledDate,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'vacunas_channel',
                  'Vacunas',
                  channelDescription: 'Recordatorios de vacunas',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
                iOS: DarwinNotificationDetails(),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
            print(
              '💉 Notificación de vacuna programada: $nombre - Dosis $dosis - ${scheduledDate.toIso8601String()}',
            );
          }

          id++;
        } catch (e) {
          print('❌ Error programando dosis $dosis de $nombre: $e');
        }
      }
    } catch (e) {
      print('❌ Error en scheduleVaccineReminders: $e');
    }
  }

  /// Cancela todas las notificaciones programadas
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
