import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
// import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart'; // ya no usado tras remover FAB

class PartosScreen extends StatefulWidget {
  const PartosScreen({super.key});

  @override
  State<PartosScreen> createState() => _PartosScreenState();
}

class _PartosScreenState extends State<PartosScreen> {
  late Box box;
  bool _isLoading = true;
  String _filtroPartos = 'Todos'; // 'Todos', 'Proximos', 'Realizados'

  @override
  void initState() {
    super.initState();
    _abrirHive();
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> _obtenerCerdasConPartos() {
    final keys = box.keys.toList();
    final todasLasCerdas = keys.map((key) {
      final cerda = box.get(key) as Map<String, dynamic>;
      return {...cerda, 'hiveKey': key};
    }).toList();

    // Filtrar cerdas que tienen fecha de preñez (pueden tener partos)
    final cerdasConPrez = todasLasCerdas.where((cerda) {
      return cerda['fecha_prez'] != null;
    }).toList();

    // Aplicar filtros adicionales
    return cerdasConPrez.where((cerda) {
      switch (_filtroPartos) {
        case 'Proximos':
          return cerda['fecha_real_parto'] == null && 
                 _esPartoProximo(cerda);
        case 'Realizados':
          return cerda['fecha_real_parto'] != null;
        case 'Todos':
        default:
          return true;
      }
    }).toList();
  }

  bool _esPartoProximo(Map<String, dynamic> cerda) {
    if (cerda['fecha_estim_parto'] == null) return false;
    
    try {
      final fechaEstimada = DateTime.parse(cerda['fecha_estim_parto']);
      final ahora = DateTime.now();
      final diferencia = fechaEstimada.difference(ahora).inDays;
      
      return diferencia <= 7 && diferencia >= 0; // Próximos 7 días
    } catch (e) {
      return false;
    }
  }

  bool _esPartoAtrasado(Map<String, dynamic> cerda) {
    if (cerda['fecha_estim_parto'] == null || cerda['fecha_real_parto'] != null) {
      return false;
    }
    
    try {
      final fechaEstimada = DateTime.parse(cerda['fecha_estim_parto']);
      final ahora = DateTime.now();
      
      return ahora.isAfter(fechaEstimada);
    } catch (e) {
      return false;
    }
  }

  Color _getColorEstadoParto(Map<String, dynamic> cerda) {
    if (cerda['fecha_real_parto'] != null) {
      return Colors.green; // Parto realizado
    } else if (_esPartoAtrasado(cerda)) {
      return Colors.red; // Parto atrasado
    } else if (_esPartoProximo(cerda)) {
      return Colors.orange; // Parto próximo
    } else {
      return Colors.blue; // Parto en curso
    }
  }

  String _getTextoEstadoParto(Map<String, dynamic> cerda) {
    if (cerda['fecha_real_parto'] != null) {
      return 'Realizado';
    } else if (_esPartoAtrasado(cerda)) {
      return 'Atrasado';
    } else if (_esPartoProximo(cerda)) {
      return 'Próximo';
    } else {
      return 'En curso';
    }
  }

  String _formatearFecha(String? fechaString) {
    if (fechaString == null) return 'No definida';
    
    try {
      final fecha = DateTime.parse(fechaString);
      return "${fecha.day}/${fecha.month}/${fecha.year}";
    } catch (e) {
      return fechaString;
    }
  }

  int _diasRestantes(String? fechaEstimada) {
    if (fechaEstimada == null) return 0;
    
    try {
      final fecha = DateTime.parse(fechaEstimada);
      final ahora = DateTime.now();
      return fecha.difference(ahora).inDays;
    } catch (e) {
      return 0;
    }
  }

  void _marcarPartoRealizado(Map<String, dynamic> cerda, int hiveKey) async {
    final fechaRealParto = DateTime.now();
    
    final cerdaActualizada = {
      ...cerda,
      'fecha_real_parto': fechaRealParto.toIso8601String(),
      'estado_reproductivo': 'Lactante',
    };

    await box.put(hiveKey, cerdaActualizada);
    setState(() {});
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Parto registrado para ${cerda['nombre']}")),
    );
  }

  void _verDetallesParto(Map<String, dynamic> cerda) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Parto - ${cerda['nombre']}"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoParto("Estado", _getTextoEstadoParto(cerda)),
              _buildInfoParto("Fecha preñez", _formatearFecha(cerda['fecha_prez'])),
              _buildInfoParto("Fecha estimada parto", _formatearFecha(cerda['fecha_estim_parto'])),
              if (cerda['fecha_real_parto'] != null)
                _buildInfoParto("Fecha real parto", _formatearFecha(cerda['fecha_real_parto'])),
              _buildInfoParto("Lechones esperados", cerda['num_lechones']?.toString() ?? 'No definido'),
              if (cerda['fecha_estim_parto'] != null && cerda['fecha_real_parto'] == null)
                _buildInfoParto("Días restantes", _diasRestantes(cerda['fecha_estim_parto']).toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          if (cerda['fecha_real_parto'] == null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _marcarPartoRealizado(cerda, cerda['hiveKey']);
              },
              child: const Text('Marcar como realizado'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoParto(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$titulo: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }

  Widget _buildResumenPartos() {
    final cerdas = _obtenerCerdasConPartos();
    final realizados = cerdas.where((c) => c['fecha_real_parto'] != null).length;
    final proximos = cerdas.where((c) => _esPartoProximo(c)).length;
    final atrasados = cerdas.where((c) => _esPartoAtrasado(c)).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Resumen de Partos",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildEstadisticaParto("Total", cerdas.length, Icons.pregnant_woman),
                _buildEstadisticaParto("Realizados", realizados, Icons.check_circle, Colors.green),
                _buildEstadisticaParto("Próximos", proximos, Icons.schedule, Colors.orange),
                _buildEstadisticaParto("Atrasados", atrasados, Icons.warning, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadisticaParto(String titulo, int valor, IconData icono, [Color? color]) {
    return Column(
      children: [
        Icon(icono, color: color ?? Colors.pink, size: 24),
        const SizedBox(height: 4),
        Text(
          valor.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black,
          ),
        ),
        Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final cerdasConPartos = _obtenerCerdasConPartos();

    return Scaffold(
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Todos', 'Proximos', 'Realizados']
                    .map((filtro) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filtro),
                            selected: _filtroPartos == filtro,
                            onSelected: (selected) {
                              setState(() => _filtroPartos = filtro);
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

          // Resumen
          _buildResumenPartos(),

          // Lista de partos
          Expanded(
            child: cerdasConPartos.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pregnant_woman, size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          "No hay partos registrados",
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Agrega cerdas preñadas para ver sus partos aquí",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: cerdasConPartos.length,
                    itemBuilder: (context, index) {
                      final cerda = cerdasConPartos[index];
                      final colorEstado = _getColorEstadoParto(cerda);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorEstado.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.pregnant_woman,
                              color: colorEstado,
                            ),
                          ),
                          title: Text(
                            cerda['nombre'] ?? 'Sin nombre',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Estado: ${_getTextoEstadoParto(cerda)}"),
                              if (cerda['fecha_estim_parto'] != null)
                                Text("Estimado: ${_formatearFecha(cerda['fecha_estim_parto'])}"),
                              if (cerda['fecha_real_parto'] != null)
                                Text("Realizado: ${_formatearFecha(cerda['fecha_real_parto'])}"),
                            ],
                          ),
                          trailing: cerda['fecha_real_parto'] == null
                              ? ElevatedButton(
                                  onPressed: () => _marcarPartoRealizado(cerda, cerda['hiveKey']),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Realizado'),
                                )
                              : const Icon(Icons.check_circle, color: Colors.green),
                          onTap: () => _verDetallesParto(cerda),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      // Se removió el FloatingActionButton '+' por solicitud (se usa 'Agregar Cerda' desde el menú)
    );
  }
}