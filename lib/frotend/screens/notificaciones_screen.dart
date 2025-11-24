import 'package:flutter/material.dart';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:my_porki/backend/services/notification_service.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  List<Map<String, dynamic>> _partosHoy = [];
  List<Map<String, dynamic>> _vacunasHoy = [];
  List<Map<String, dynamic>> _partosProximos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
  }

  Future<void> _cargarNotificaciones() async {
    try {
      final cerdas = await SowService.obtenerCerdas();
      final ahora = DateTime.now();
      final hoy = DateTime(ahora.year, ahora.month, ahora.day);

      _partosHoy.clear();
      _vacunasHoy.clear();
      _partosProximos.clear();

      for (var cerda in cerdas) {
        final nombre = cerda['nombre'] ?? 'Cerda sin nombre';

        // 1. VERIFICAR PARTOS DE HOY
        final partos = cerda['partos'] as List<dynamic>? ?? [];
        for (var parto in partos) {
          if (parto is Map) {
            final fechaPartoStr = parto['fecha'];
            if (fechaPartoStr != null) {
              try {
                final fechaParto = DateTime.parse(fechaPartoStr.toString());
                final fechaPartoHoy = DateTime(fechaParto.year, fechaParto.month, fechaParto.day);
                
                if (fechaPartoHoy == hoy) {
                  _partosHoy.add({
                    'cerda': cerda,
                    'fecha': fechaParto,
                    'dias_restantes': 0,
                    'tipo': 'parto_hoy',
                    'mensaje': 'Hoy es el parto de $nombre',
                    'prioridad': 'alta',
                  });
                }
              } catch (e) {
                // Fecha inválida
              }
            }
          }
        }

        // 2. VERIFICAR VACUNAS DE HOY
        final vacunas = cerda['vacunas'] as List<dynamic>? ?? [];
        for (var vacuna in vacunas) {
          if (vacuna is Map) {
            final dosisProgramadas = vacuna['dosis_programadas'] as List<dynamic>? ?? [];
            for (var dosis in dosisProgramadas) {
              if (dosis is Map) {
                final fechaVacunaStr = dosis['fecha'];
                if (fechaVacunaStr != null) {
                  try {
                    final fechaVacuna = DateTime.parse(fechaVacunaStr.toString());
                    final fechaVacunaHoy = DateTime(fechaVacuna.year, fechaVacuna.month, fechaVacuna.day);
                    
                    if (fechaVacunaHoy == hoy) {
                      final numDosis = dosis['numero_dosis'] ?? 1;
                      final nombreVacuna = vacuna['nombre'] ?? 'Vacuna';
                      
                      _vacunasHoy.add({
                        'cerda': cerda,
                        'fecha': fechaVacuna,
                        'dias_restantes': 0,
                        'tipo': 'vacuna_hoy',
                        'mensaje': '$nombreVacuna (Dosis $numDosis) para $nombre',
                        'prioridad': 'media',
                      });
                    }
                  } catch (e) {
                    // Fecha inválida
                  }
                }
              }
            }
          }
        }

        // 3. VERIFICAR PARTOS PRÓXIMOS (5 días)
        final fechaPartoStr = cerda['fecha_parto_calculado'];
        if (fechaPartoStr != null) {
          try {
            final fechaParto = DateTime.parse(fechaPartoStr.toString());
            final diasRestantes = fechaParto.difference(ahora).inDays;

            if (diasRestantes > 0 && diasRestantes <= 5) {
              _partosProximos.add({
                'cerda': cerda,
                'fecha': fechaParto,
                'dias_restantes': diasRestantes,
                'tipo': 'parto_proximo',
                'mensaje': _generarMensajeParto(nombre, diasRestantes),
                'prioridad': diasRestantes <= 2 ? 'alta' : 'media',
              });
            }
          } catch (e) {
            // Fecha inválida
          }
        }
      }

      // Ordenar por prioridad y fecha
      _partosProximos.sort((a, b) {
        if (a['prioridad'] != b['prioridad']) {
          return a['prioridad'] == 'alta' ? -1 : 1;
        }
        return a['dias_restantes'].compareTo(b['dias_restantes']);
      });

      setState(() {
        _isLoading = false;
      });
      
      print('🔔 Notificaciones cargadas:');
      print('   - ${_partosHoy.length} partos hoy');
      print('   - ${_vacunasHoy.length} vacunas hoy');
      print('   - ${_partosProximos.length} partos próximos');
      
      // Programar notificaciones push automáticas
      await NotificationService.programarNotificacionesAutomaticas();
      
    } catch (e) {
      print('❌ Error cargando notificaciones: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _generarMensajeParto(String nombre, int diasRestantes) {
    if (diasRestantes == 1) {
      return 'Mañana es el parto de $nombre';
    } else {
      return 'Parto de $nombre en $diasRestantes días';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildNotificacionItem(Map<String, dynamic> notif) {
    final cerda = notif['cerda'];
    final diasRestantes = notif['dias_restantes'];
    final prioridad = notif['prioridad'];
    final tipo = notif['tipo'];

    // Definir icono y color según el tipo
    IconData icono;
    Color color;
    String titulo;

    switch (tipo) {
      case 'parto_hoy':
        icono = Icons.pets;
        color = Colors.red;
        titulo = '🐷 Parto Hoy';
        break;
      case 'vacuna_hoy':
        icono = Icons.medical_services;
        color = Colors.blue;
        titulo = '💉 Vacuna Hoy';
        break;
      case 'parto_proximo':
        icono = Icons.calendar_today;
        color = prioridad == 'alta' ? Colors.orange : Colors.green;
        titulo = '📅 Parto Próximo';
        break;
      default:
        icono = Icons.notifications;
        color = Colors.grey;
        titulo = 'Notificación';
    }

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 2,
      color: _getColorByPriority(prioridad).withOpacity(0.1),
      child: ListTile(
        leading: Icon(
          icono,
          color: color,
          size: 30,
        ),
        title: Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notif['mensaje']),
            const SizedBox(height: 4),
            Text(
              'Cerda: ${cerda['nombre'] ?? 'Sin nombre'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Text(
              'Fecha: ${_formatDate(notif['fecha'])}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (diasRestantes > 0)
              Text(
                'Días restantes: $diasRestantes',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
        trailing: prioridad == 'alta'
            ? const Icon(Icons.warning, color: Colors.red)
            : null,
      ),
    );
  }

  Color _getColorByPriority(String prioridad) {
    switch (prioridad) {
      case 'alta':
        return Colors.red;
      case 'media':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  Widget _buildSeccion(String titulo, List<Map<String, dynamic>> notificaciones) {
    if (notificaciones.isEmpty) {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('${notificaciones.length}'),
                backgroundColor: Colors.pink,
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        ...notificaciones.map(_buildNotificacionItem).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final todasLasNotificaciones = [..._partosHoy, ..._vacunasHoy, ..._partosProximos];
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordatorios 🐷'),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _cargarNotificaciones();
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active),
            onPressed: () {
              NotificationService.mostrarNotificacionPrueba();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : todasLasNotificaciones.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay recordatorios pendientes',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '¡Todo bajo control! 🐷',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSeccion('🐷 Partos Hoy', _partosHoy),
                  _buildSeccion('💉 Vacunas Hoy', _vacunasHoy),
                  _buildSeccion('📅 Próximos Partos', _partosProximos),
                ],
              ),
            ),
    );
  }
}