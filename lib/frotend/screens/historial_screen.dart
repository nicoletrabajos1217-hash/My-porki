import 'package:flutter/material.dart';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:my_porki/backend/services/local_service.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  bool _isLoading = true;
  String _filtroSeleccionado = 'Todas';
  List<Map<String, dynamic>> _cerdas = [];

  @override
  void initState() {
    super.initState();
    _cargarCerdas();
  }

  Future<void> _cargarCerdas() async {
    try {
      // CORREGIDO: Usar SowService.obtenerCerdas() en lugar de acceder directamente a Hive
      final cerdas = await SowService.obtenerCerdas();

      setState(() {
        _cerdas = cerdas;
        _isLoading = false;
      });

      print('✅ Historial: ${cerdas.length} cerdas cargadas');
    } catch (e) {
      print('❌ Error cargando cerdas en historial: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _obtenerCerdasFiltradas() {
    if (_filtroSeleccionado == 'Todas') return _cerdas;

    return _cerdas.where((cerda) {
      switch (_filtroSeleccionado) {
        case 'Preñadas':
          return cerda['estado'] == 'Preñada';
        case 'No preñadas':
          return cerda['estado'] == 'No preñada';
        case 'Con partos':
          return (cerda['partos'] as List?)?.isNotEmpty ?? false;
        case 'Con vacunas':
          return (cerda['vacunas'] as List?)?.isNotEmpty ?? false;
        default:
          return true;
      }
    }).toList();
  }

  int _convertirLechones(dynamic valor) {
    try {
      if (valor is int) return valor;
      if (valor is String) return int.tryParse(valor) ?? 0;
    } catch (_) {}
    return 0;
  }

  Widget _buildCerdaCard(Map<String, dynamic> cerda) {
    final partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
    final vacunas = List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []);
    int totalLechones = 0;

    for (var parto in partos) {
      totalLechones += _convertirLechones(parto['num_lechones']);
    }

    Color estadoColor = cerda['estado'] == 'Preñada'
        ? Colors.green
        : Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NOMBRE + ESTADO
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cerda['nombre'] ?? 'Sin nombre',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'ID: ${cerda['id'] ?? '-'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    cerda['estado'] ?? '-',
                    style: TextStyle(
                      color: estadoColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // HISTORIAL RESUMIDO
            Row(
              children: [
                Chip(
                  label: Text('Partos: ${partos.length}'),
                  backgroundColor: Colors.pink[50],
                  avatar: const Icon(Icons.pets, size: 20, color: Colors.pink),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text('Lechones: $totalLechones'),
                  backgroundColor: Colors.orange[50],
                  avatar: const Icon(
                    Icons.pets,
                    size: 20,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text('Vacunas: ${vacunas.length}'),
                  backgroundColor: Colors.blue[50],
                  avatar: const Icon(
                    Icons.vaccines,
                    size: 20,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenEstadisticas() {
    final cerdas = _obtenerCerdasFiltradas();

    final prenadas = cerdas.where((c) => c['estado'] == 'Preñada').length;

    int totalLechones = 0;
    for (var cerda in cerdas) {
      final partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
      for (var p in partos) {
        totalLechones += _convertirLechones(p['num_lechones']);
      }
    }

    int totalVacunas = 0;
    for (var cerda in cerdas) {
      totalVacunas += (cerda['vacunas'] as List?)?.length ?? 0;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildEstadisticaItem(
              "Cerdas",
              cerdas.length,
              Icons.pets,
              Colors.pink,
            ),
            _buildEstadisticaItem(
              "Preñadas",
              prenadas,
              Icons.pets,
              Colors.green,
            ),
            _buildEstadisticaItem(
              "Lechones",
              totalLechones,
              Icons.pets,
              Colors.orange,
            ),
            _buildEstadisticaItem(
              "Vacunas",
              totalVacunas,
              Icons.vaccines,
              Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticaItem(
    String titulo,
    int valor,
    IconData icono,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icono, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          valor.toString(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.pink)),
      );
    }

    final cerdasFiltradas = _obtenerCerdasFiltradas();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Historial de Cerdas 🐷"),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _cargarCerdas();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // FILTROS
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
                          (f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(f),
                              selected: _filtroSeleccionado == f,
                              onSelected: (s) =>
                                  setState(() => _filtroSeleccionado = f),
                              selectedColor: Colors.pink[100],
                              backgroundColor: Colors.grey[300],
                            ),
                          ),
                        )
                        .toList(),
              ),
            ),
          ),

          // RESUMEN
          _buildResumenEstadisticas(),

          // LISTA
          Expanded(
            child: cerdasFiltradas.isEmpty
                ? const Center(
                    child: Text(
                      'No hay cerdas para mostrar',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async => _cargarCerdas(),
                    child: ListView.builder(
                      itemCount: cerdasFiltradas.length,
                      itemBuilder: (context, index) =>
                          _buildCerdaCard(cerdasFiltradas[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
