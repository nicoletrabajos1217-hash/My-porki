import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  late Box box;
  bool _isLoading = true;
  String _filtroSeleccionado = 'Todas';

  @override
  void initState() {
    super.initState();
    _abrirHive();
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> _obtenerCerdasFiltradas() {
    final keys = box.keys.toList();
    final todasLasCerdas = keys.map((key) {
      final cerda = box.get(key) as Map<String, dynamic>;
      return {...cerda, 'hiveKey': key};
    }).toList();

    if (_filtroSeleccionado == 'Todas') return todasLasCerdas;

    return todasLasCerdas.where((cerda) {
      switch (_filtroSeleccionado) {
        case 'Preñadas':
          return cerda['estado_reproductivo'] == 'Preñada';
        case 'Lactantes':
          return cerda['estado_reproductivo'] == 'Lactante';
        case 'No preñadas':
          return cerda['estado_reproductivo'] == 'No preñada';
        case 'Con partos':
          return cerda['historial_partos'] != null && 
                 (cerda['historial_partos'] as List).isNotEmpty;
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildResumenEstadisticas() {
    final cerdas = _obtenerCerdasFiltradas();
    final preadas = cerdas.where((c) => c['estado_reproductivo'] == 'Preñada').length;
    final lactantes = cerdas.where((c) => c['estado_reproductivo'] == 'Lactante').length;
    
    // CORRECCIÓN: Manejo seguro de num_lechones
    final totalLechones = cerdas.fold(0, (sum, cerda) {
      final lechones = cerda['num_lechones'];
      if (lechones is int) {
        return sum + lechones;
      } else if (lechones is String) {
        return sum + (int.tryParse(lechones) ?? 0);
      }
      return sum;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Resumen General",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildEstadisticaItem("Total", cerdas.length, Icons.pets),
                _buildEstadisticaItem("Preñadas", preadas, Icons.pregnant_woman),
                _buildEstadisticaItem("Lactantes", lactantes, Icons.child_care),
                _buildEstadisticaItem("Lechones", totalLechones, Icons.face),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticaItem(String titulo, int valor, IconData icono) {
    return Column(
      children: [
        Icon(icono, color: Colors.pink, size: 24),
        const SizedBox(height: 4),
        Text(
          valor.toString(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildListaEventosRecientes() {
    final cerdas = _obtenerCerdasFiltradas();
    final eventos = <Map<String, dynamic>>[];

    // Recolectar todos los eventos de todas las cerdas
    for (final cerda in cerdas) {
      final nombreCerda = cerda['nombre'] ?? 'Sin nombre';

      // Evento de preñez
      if (cerda['fecha_prez'] != null) {
        eventos.add({
          'tipo': 'preñez',
          'titulo': 'Preñez confirmada',
          'subtitulo': nombreCerda,
          'fecha': cerda['fecha_prez'],
          'color': Colors.green,
          'icono': Icons.pregnant_woman,
        });
      }

      // Evento de parto
      if (cerda['fecha_real_parto'] != null) {
        // CORRECCIÓN: Manejo seguro de num_lechones para el subtítulo
        final lechones = cerda['num_lechones'];
        final textoLechones = lechones != null ? ' - $lechones lechones' : '';
        
        eventos.add({
          'tipo': 'parto',
          'titulo': 'Parto registrado',
          'subtitulo': '$nombreCerda$textoLechones',
          'fecha': cerda['fecha_real_parto'],
          'color': Colors.blue,
          'icono': Icons.child_care,
        });
      }

      // Eventos de vacunas
      if (cerda['vacunas'] != null && cerda['vacunas'] is List) {
        for (final vacuna in cerda['vacunas'] as List) {
          if (vacuna is Map && vacuna['fecha'] != null) {
            eventos.add({
              'tipo': 'vacuna',
              'titulo': 'Vacuna aplicada',
              'subtitulo': '${vacuna['nombre']} - $nombreCerda',
              'fecha': vacuna['fecha'],
              'color': Colors.orange,
              'icono': Icons.medical_services,
            });
          }
        }
      }
    }

    // Ordenar eventos por fecha (más recientes primero)
    eventos.sort((a, b) {
      try {
        return b['fecha'].compareTo(a['fecha']);
      } catch (e) {
        return 0;
      }
    });

    if (eventos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              "No hay eventos registrados",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Eventos Recientes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...eventos.take(10).map((evento) => _buildItemEvento(evento)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildItemEvento(Map<String, dynamic> evento) {
    try {
      final fecha = DateTime.parse(evento['fecha']);
      final fechaFormateada = "${fecha.day}/${fecha.month}/${fecha.year}";

      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: evento['color'].withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(evento['icono'], color: evento['color'], size: 20),
        ),
        title: Text(evento['titulo'] ?? 'Evento'),
        subtitle: Text(evento['subtitulo'] ?? ''),
        trailing: Text(
          fechaFormateada,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        dense: true,
      );
    } catch (e) {
      return const ListTile(
        title: Text("Evento con fecha inválida"),
        leading: Icon(Icons.error, color: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial y Estadísticas"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Todas', 'Preñadas', 'Lactantes', 'No preñadas', 'Con partos']
                    .map((filtro) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filtro),
                            selected: _filtroSeleccionado == filtro,
                            onSelected: (selected) {
                              setState(() => _filtroSeleccionado = filtro);
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

          // Contenido
          Expanded(
            child: ListView(
              children: [
                _buildResumenEstadisticas(),
                _buildListaEventosRecientes(),
                
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "Más funcionalidades próximamente...",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}