import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'cerda_detail_screen.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  late Box box;
  bool _isLoading = true;
  String _filtroSeleccionado = 'Todas';
  List<Map<String, dynamic>> _cerdas = [];
  final Map<dynamic, bool> _cerdasExpandidas = {};

  @override
  void initState() {
    super.initState();
    _abrirHive();
  }

  Future<void> _abrirHive() async {
    try {
      box = await Hive.openBox('porki_data');
      print('✅ Hive abierto correctamente');
      _cargarCerdas();
    } catch (e) {
      print('❌ Error abriendo Hive: $e');
      setState(() => _isLoading = false);
    }
  }

  void _cargarCerdas() {
    try {
      final keys = box.keys.toList();
      print('📦 Keys en Hive: $keys');

      final cerdasTemporales = <Map<String, dynamic>>[];

      for (var key in keys) {
        final data = box.get(key);
        print('🔍 Key: $key, Data: $data');

        if (data is Map && data['type'] == 'sow') {
          cerdasTemporales.add({...data, 'hiveKey': key});
        }
      }

      _cerdas = cerdasTemporales;
      print('🐷 Total cerdas cargadas: ${_cerdas.length}');

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ Error cargando cerdas: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _obtenerCerdasFiltradas() {
    if (_filtroSeleccionado == 'Todas') return _cerdas;

    return _cerdas.where((cerda) {
      switch (_filtroSeleccionado) {
        case 'Preñadas':
          return cerda['estado_reproductivo'] == 'Preñada';
        case 'No preñadas':
          return cerda['estado_reproductivo'] == 'No preñada';
        case 'Con partos':
          return cerda['partos'] != null &&
              (cerda['partos'] as List).isNotEmpty;
        case 'Con vacunas':
          return cerda['vacunas'] != null &&
              (cerda['vacunas'] as List).isNotEmpty;
        default:
          return true;
      }
    }).toList();
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'No especificada';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Fecha inválida';
    }
  }

  String _calcularDiasParto(String? fechaPartoString) {
    if (fechaPartoString == null) return '';
    try {
      final fechaParto = DateTime.parse(fechaPartoString);
      final ahora = DateTime.now();
      final diferencia = fechaParto.difference(ahora).inDays;

      if (diferencia > 0) {
        return ' ($diferencia días)';
      } else if (diferencia == 0) {
        return ' (¡Hoy!)';
      } else {
        return ' (Hace ${-diferencia} días)';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildCerdaExpandible(Map<String, dynamic> cerda) {
    final key = cerda['hiveKey'];
    final estaExpandida = _cerdasExpandidas[key] ?? false;

    final partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
    final vacunas = List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      child: ExpansionTile(
        key: Key(key.toString()),
        initiallyExpanded: estaExpandida,
        onExpansionChanged: (expanded) {
          setState(() {
            _cerdasExpandidas[key] = expanded;
          });
        },
        leading: Icon(
          Icons.pets,
          color: cerda['estado_reproductivo'] == 'Preñada'
              ? Colors.green
              : Colors.grey,
        ),
        title: Text(
          cerda['nombre'] ?? 'Sin nombre',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'ID: ${cerda['identificacion'] ?? 'No ID'} - ${cerda['estado_reproductivo'] ?? 'No especificado'}',
        ),
        trailing: Chip(
          label: Text('${partos.length} partos'),
          backgroundColor: Colors.pink[50],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // INFORMACIÓN BÁSICA
                const Text(
                  '📋 Información General',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.badge, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('ID: ${cerda['identificacion'] ?? 'No ID'}'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.female, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'Estado: ${cerda['estado_reproductivo'] ?? 'No especificado'}',
                    ),
                  ],
                ),

                // ESTADO ACTUAL DE PREÑEZ
                if (cerda['embarazada'] == true ||
                    (cerda['lechones_nacidos'] ?? 0) > 0) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '🐷 Estado de Preñez Actual',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (cerda['embarazada'] == true)
                    const Row(
                      children: [
                        Icon(Icons.pets, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Preña'),
                      ],
                    ),
                  if ((cerda['lechones_nacidos'] ?? 0) > 0)
                    Row(
                      children: [
                        const Icon(
                          Icons.child_friendly,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text('Lechones Nacidos: ${cerda['lechones_nacidos']}'),
                      ],
                    ),
                ],
                const SizedBox(height: 8),
                // Botón rápido para ver detalle completo y editar
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Navegar a la pantalla de detalle de cerda
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CerdasScreen(
                                openCerda: Map<String, dynamic>.from(cerda),
                                openKey: key,
                              ),
                            ),
                          );
                          // Recargar para reflejar cambios
                          await _abrirHive();
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Ver detalle'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pink,
                        ),
                      ),
                    ),
                  ],
                ),

                // FECHAS IMPORTANTES SI ESTÁ PREÑADA
                if (cerda['estado_reproductivo'] == 'Preñada') ...[
                  const SizedBox(height: 12),
                  const Text(
                    '🤰 Gestación Actual',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (cerda['fecha_prenez_actual'] != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Preñez: ${_formatDate(cerda['fecha_prenez_actual'])}',
                        ),
                      ],
                    ),
                  if (cerda['fecha_parto_calculado'] != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.event_available,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Parto estimado: ${_formatDate(cerda['fecha_parto_calculado'])}${_calcularDiasParto(cerda['fecha_parto_calculado'])}',
                        ),
                      ],
                    ),
                ],

                // HISTORIAL DE PARTOS
                const SizedBox(height: 16),
                const Text(
                  '🐷 Historial de Partos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (partos.isEmpty)
                  const Text(
                    '  No hay partos registrados',
                    style: TextStyle(color: Colors.grey),
                  ),
                if (partos.isNotEmpty)
                  ...partos.asMap().entries.map((entry) {
                    final index = entry.key;
                    final parto = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Parto ${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (parto['fecha_prez'] != null)
                            Text(
                              '  • Preñez: ${_formatDate(parto['fecha_prez'])}',
                            ),
                          if (parto['fecha_confirmacion'] != null)
                            Text(
                              '  • Confirmación: ${_formatDate(parto['fecha_confirmacion'])}',
                            ),
                          if (parto['fecha_parto'] != null)
                            Text(
                              '  • Parto: ${_formatDate(parto['fecha_parto'])}',
                            ),
                          if (parto['num_lechones'] != null)
                            Text('  • Lechones: ${parto['num_lechones']}'),
                          if (parto['observaciones'] != null &&
                              parto['observaciones'].isNotEmpty)
                            Text(
                              '  • Observaciones: ${parto['observaciones']}',
                            ),
                        ],
                      ),
                    );
                  }),

                // HISTORIAL DE VACUNAS
                const SizedBox(height: 16),
                const Text(
                  '💉 Historial de Vacunas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (vacunas.isEmpty)
                  const Text(
                    '  No hay vacunas registradas',
                    style: TextStyle(color: Colors.grey),
                  ),
                if (vacunas.isNotEmpty)
                  ...vacunas.map((vacuna) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.vaccines,
                            size: 16,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${vacuna['nombre']} - ${_formatDate(vacuna['fecha'])}',
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                // METADATOS
                const SizedBox(height: 16),
                const Text(
                  '📊 Información del Sistema',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Creada: ${_formatDate(cerda['createdAt'])}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (cerda['updatedAt'] != null)
                  Text(
                    'Actualizada: ${_formatDate(cerda['updatedAt'])}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),

                // HISTORIAL DE CAMBIOS
                const SizedBox(height: 16),
                const Text(
                  '📋 Historial de Cambios',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (cerda['historial'] == null ||
                    (cerda['historial'] as List).isEmpty)
                  const Text(
                    '  No hay cambios registrados',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...(cerda['historial'] as List).map((cambio) {
                    final cambios =
                        cambio['cambios'] as Map<String, dynamic>? ?? {};
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber[200] ?? Colors.amber,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(cambio['fecha']),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...cambios.entries.map(
                            (c) => Text(
                              '  • ${c.key}: ${c.value}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenEstadisticas() {
    final cerdas = _obtenerCerdasFiltradas();
    final prenadas = cerdas
        .where((c) => c['estado_reproductivo'] == 'Preñada')
        .length;

    // Calcular total de lechones de todos los partos
    int totalLechones = 0;
    for (var cerda in cerdas) {
      final partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
      for (var parto in partos) {
        totalLechones += (parto['num_lechones'] as int? ?? 0);
      }
    }

    // Calcular total de vacunas
    int totalVacunas = 0;
    for (var cerda in cerdas) {
      totalVacunas += (cerda['vacunas'] as List).length;
    }

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
                _buildEstadisticaItem("Cerdas", cerdas.length, Icons.pets),
                _buildEstadisticaItem(
                  "Preñadas",
                  prenadas,
                  Icons.pregnant_woman,
                ),
                _buildEstadisticaItem("Lechones", totalLechones, Icons.face),
                _buildEstadisticaItem("Vacunas", totalVacunas, Icons.vaccines),
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
        Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.pink),
            SizedBox(height: 16),
            Text('Cargando historial...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    final cerdasFiltradas = _obtenerCerdasFiltradas();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial Completo 🐷"),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _cargarCerdas();
            },
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
                children:
                    [
                          'Todas',
                          'Preñadas',
                          'No preñadas',
                          'Con partos',
                          'Con vacunas',
                        ]
                        .map(
                          (filtro) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(filtro),
                              selected: _filtroSeleccionado == filtro,
                              onSelected: (selected) {
                                setState(() => _filtroSeleccionado = filtro);
                              },
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),

          // Resumen
          _buildResumenEstadisticas(),

          // Contador de resultados
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${cerdasFiltradas.length} cerdas encontradas',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const Spacer(),
                if (_filtroSeleccionado != 'Todas')
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filtroSeleccionado = 'Todas';
                      });
                    },
                    child: const Text('Limpiar filtro'),
                  ),
              ],
            ),
          ),

          // Lista de cerdas
          Expanded(
            child: cerdasFiltradas.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pets, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No hay cerdas que coincidan\ncon el filtro seleccionado',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await _abrirHive();
                    },
                    child: ListView.builder(
                      itemCount: cerdasFiltradas.length,
                      itemBuilder: (context, index) {
                        return _buildCerdaExpandible(cerdasFiltradas[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
