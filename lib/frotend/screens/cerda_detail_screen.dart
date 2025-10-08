import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart';

class CerdaDetailScreen extends StatefulWidget {
  const CerdaDetailScreen({super.key});

  @override
  State<CerdaDetailScreen> createState() => _CerdaDetailScreenState();
}

class _CerdaDetailScreenState extends State<CerdaDetailScreen> {
  late Box box;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _abrirHive();
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
    setState(() => _isLoading = false);
  }

  void _eliminarCerda(int key, String nombre) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar Cerda"),
        content: Text("¿Estás seguro de eliminar a $nombre?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () async {
              await box.delete(key);
              setState(() {});
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$nombre eliminada")),
              );
            },
            child: const Text("Eliminar", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _editarCerda(Map<String, dynamic> cerda, int hiveKey) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgregarCerdaScreen(
          cerdaExistente: cerda,
          hiveKey: hiveKey,
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _verDetallesCompletos(Map<String, dynamic> cerda, int key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(cerda['nombre'] ?? "Sin nombre"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoItem("Identificación", cerda['identificacion']),
              _buildInfoItem("Estado reproductivo", cerda['estado_reproductivo']),
              _buildInfoItem("Número de lechones", cerda['num_lechones']?.toString()),
              _buildInfoItem("Observaciones", cerda['observacion']),
              
              if (cerda['fecha_prez'] != null) 
                _buildInfoItem("Fecha preñez", _formatearFecha(cerda['fecha_prez'])),
              
              if (cerda['fecha_estim_parto'] != null)
                _buildInfoItem("Fecha estimada parto", _formatearFecha(cerda['fecha_estim_parto'])),
              
              if (cerda['fecha_real_parto'] != null)
                _buildInfoItem("Fecha real parto", _formatearFecha(cerda['fecha_real_parto'])),
              
              const SizedBox(height: 10),
              if (cerda['vacunas'] != null && (cerda['vacunas'] as List).isNotEmpty) ...[
                const Text("Vacunas:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...(cerda['vacunas'] as List).map((vacuna) => 
                  Text("  • ${vacuna['nombre']} - ${_formatearFecha(vacuna['fecha'])}")
                ).toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar"),
          ),
          TextButton(
            onPressed: () => _editarCerda(cerda, key),
            child: const Text("Editar"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String titulo, String? valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$titulo: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(valor ?? "No especificado")),
        ],
      ),
    );
  }

  String _formatearFecha(String fechaString) {
    try {
      final fecha = DateTime.parse(fechaString);
      return "${fecha.day}/${fecha.month}/${fecha.year}";
    } catch (e) {
      return fechaString;
    }
  }

  Color _getEstadoColor(String? estado) {
    switch (estado) {
      case 'Preñada':
        return Colors.green;
      case 'Lactante':
        return Colors.blue;
      case 'No preñada':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getEstadoIcon(String? estado) {
    switch (estado) {
      case 'Preñada':
        return Icons.pregnant_woman;
      case 'Lactante':
        return Icons.child_care;
      case 'No preñada':
        return Icons.accessible;
      default:
        return Icons.pets;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final keys = box.keys.toList();

    if (keys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pets, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "No hay cerdas registradas",
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AgregarCerdaScreen()),
                ).then((_) => setState(() {}));
              },
              child: const Text("Agregar primera cerda"),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total de cerdas: ${keys.length}",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AgregarCerdaScreen()),
                  ).then((_) => setState(() {}));
                },
                icon: const Icon(Icons.add),
                label: const Text("Agregar Cerda"),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: keys.length,
            itemBuilder: (context, index) {
              final key = keys[index];
              final cerda = box.get(key) as Map<String, dynamic>;
              final nombre = cerda['nombre'] ?? "Sin nombre";
              final estado = cerda['estado_reproductivo'] ?? 'No preñada';
              final identificacion = cerda['identificacion'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(
                    _getEstadoIcon(estado),
                    color: _getEstadoColor(estado),
                    size: 30,
                  ),
                  title: Text(
                    nombre,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (identificacion != null && identificacion.isNotEmpty)
                        Text("ID: $identificacion"),
                      Text("Estado: $estado"),
                      if (cerda['fecha_prez'] != null)
                        Text("Preñada desde: ${_formatearFecha(cerda['fecha_prez'])}"),
                      if (cerda['num_lechones'] != null && cerda['num_lechones'] > 0)
                        Text("Lechones: ${cerda['num_lechones']}"),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, color: Colors.blue),
                        onPressed: () => _verDetallesCompletos(cerda, key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        onPressed: () => _editarCerda(cerda, key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminarCerda(key, nombre),
                      ),
                    ],
                  ),
                  onTap: () => _verDetallesCompletos(cerda, key),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}