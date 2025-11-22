import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:my_porki/backend/services/auth_service.dart';
import 'package:my_porki/backend/services/local_service.dart';

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

      final settings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {},
      );
      
      print('✅ NotificationService inicializado');
    } catch (e) {
      print('❌ Error inicializando NotificationService: $e');
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
          if (fechaPartoStr != null && (item['notificado_parto'] ?? false) == false) {
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
              if (fechaStr == null || (dosis['notificado'] ?? false) == true) continue;

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
            
            final fechaInseminacion = DateTime.tryParse(fechaPrenezStr.toString());
            if (fechaInseminacion != null) {
              final fechaConfirmacion = fechaInseminacion.add(const Duration(days: 21));
              if (ahora.isAfter(fechaConfirmacion) || ahora.isAtSameMomentAs(fechaConfirmacion)) {
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
      notificaciones.sort((a, b) => (a['fecha'] as DateTime).compareTo(b['fecha'] as DateTime));
      
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
            cuerpo = '$nombre - $vacunaNombre ${dosisNum.isNotEmpty ? '- Dosis $dosisNum' : ''}';
            
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
                  channelDescription: 'Recordatorios de partos, vacunas y preñez',
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: true,
                ),
                iOS: const DarwinNotificationDetails(
                  sound: 'default',
                ),
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
                  channelDescription: 'Recordatorios de partos, vacunas y preñez',
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: true,
                ),
                iOS: const DarwinNotificationDetails(
                  sound: 'default',
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
            print('⏰ Notificación programada: $titulo para ${scheduledDate.toString()}');
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
  static Future<List<Map<String, dynamic>>> getNotificacionesParaPantalla() async {
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
          descripcion = '$nombre - $vacunaNombre ${dosisNum.isNotEmpty ? '(Dosis $dosisNum)' : ''}';
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