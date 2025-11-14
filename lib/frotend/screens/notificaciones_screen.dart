import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  List<Map<String, dynamic>> _notificaciones = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
  }

  Future<void> _cargarNotificaciones() async {
    try {
      final box = await Hive.openBox('porki_data');
      final allData = box.values.toList();
      final cerdas = allData.where((data) => 
        data is Map && data['type'] == 'sow'
      ).cast<Map<String, dynamic>>().toList();
      
      final partosProximos = <Map<String, dynamic>>[];
      final ahora = DateTime.now();
      
      for (var cerda in cerdas) {
        if (cerda['fecha_parto_calculado'] != null) {
          try {
            final fechaParto = DateTime.parse(cerda['fecha_parto_calculado']);
            final diasRestantes = fechaParto.difference(ahora).inDays;
            
            if (diasRestantes >= 0 && diasRestantes <= 7) {
              partosProximos.add({
                'cerda': cerda,
                'fecha_parto': fechaParto,
                'dias_restantes': diasRestantes,
                'tipo': 'parto_proximo',
                'mensaje': _generarMensajeParto(cerda['nombre'], diasRestantes),
                'prioridad': diasRestantes <= 3 ? 'alta' : 'media',
              });
            }
          } catch (e) {
            // Fecha inválida, continuar
          }
        }
      }
      
      // Ordenar por prioridad y fecha
      partosProximos.sort((a, b) {
        if (a['prioridad'] != b['prioridad']) {
          return a['prioridad'] == 'alta' ? -1 : 1;
        }
        return a['dias_restantes'].compareTo(b['dias_restantes']);
      });
      
      setState(() {
        _notificaciones = partosProximos;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando notificaciones: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  String _generarMensajeParto(String? nombreCerda, int diasRestantes) {
    final nombre = nombreCerda ?? 'Cerda sin nombre';
    if (diasRestantes == 0) {
      return '¡Hoy es el parto de $nombre! 🎉';
    } else if (diasRestantes == 1) {
      return 'Mañana es el parto de $nombre 📅';
    } else {
      return 'Parto de $nombre en $diasRestantes días 🗓️';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordatorios 🗓️'),
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
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notificaciones.isEmpty
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
                        '¡Todo bajo control! 🎉',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _notificaciones.length,
                  itemBuilder: (context, index) {
                    final notif = _notificaciones[index];
                    final cerda = notif['cerda'];
                    final diasRestantes = notif['dias_restantes'];
                    final prioridad = notif['prioridad'];
                    
                    return Card(
                      margin: const EdgeInsets.all(8),
                      elevation: 2,
                      color: prioridad == 'alta' ? Colors.red[50] : Colors.orange[50],
                      child: ListTile(
                        leading: Icon(
                          Icons.pregnant_woman,
                          color: prioridad == 'alta' ? Colors.red : Colors.orange,
                          size: 30,
                        ),
                        title: Text(
                          cerda['nombre'] ?? 'Cerda sin nombre',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: prioridad == 'alta' ? Colors.red : Colors.orange,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(notif['mensaje']),
                            const SizedBox(height: 4),
                            Text(
                              'Parto estimado: ${_formatDate(notif['fecha_parto'])}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            if (cerda['identificacion'] != null)
                              Text(
                                'ID: ${cerda['identificacion']}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$diasRestantes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: prioridad == 'alta' ? Colors.red : Colors.orange,
                              ),
                            ),
                            Text(
                              'días',
                              style: TextStyle(
                                fontSize: 10,
                                color: prioridad == 'alta' ? Colors.red : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}