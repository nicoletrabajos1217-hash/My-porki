import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // 👈 importante: NO 'hive.dart'

/// ✅ Pantalla principal: lista de cerdas + detalle individual
class CerdasScreen extends StatefulWidget {
  const CerdasScreen({super.key});

  @override
  State<CerdasScreen> createState() => _CerdasScreenState();
}

class _CerdasScreenState extends State<CerdasScreen> {
  late Box box;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _abrirHive();
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
    setState(() => _loading = false);
  }

  void _abrirDetalle({Map<String, dynamic>? cerda, int? key}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CerdaDetailScreen(cerdaExistente: cerda, hiveKey: key),
      ),
    );
    setState(() {}); // refresca al volver
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cerdas 🐷'),
        backgroundColor: Colors.pink,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pink,
        onPressed: () => _abrirDetalle(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : ValueListenableBuilder(
              valueListenable: Hive.box('porki_data').listenable(),
              builder: (context, Box box, _) {
                final cerdas = box.values
                    .where((item) => item is Map && item['type'] == 'sow')
                    .toList();

                if (cerdas.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay cerdas registradas 🐖',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: cerdas.length,
                  itemBuilder: (context, index) {
                    final cerda = cerdas[index];
                    final key = box.keyAt(index);
                    final nombre = cerda['nombre'] ?? 'Sin nombre';
                    final id = cerda['identificacion'] ?? 'Sin ID';
                    final estado =
                        cerda['estado_reproductivo'] ?? 'Desconocido';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: const Text(
                          '🐷',
                          style: TextStyle(fontSize: 28),
                        ),
                        title: Text(
                          nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('ID: $id\nEstado: $estado'),
                        isThreeLine: true,
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.pink,
                        ),
                        onTap: () => _abrirDetalle(
                          cerda: Map<String, dynamic>.from(cerda),
                          key: key,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/// ✅ Pantalla de detalle y edición de una cerda específica
class _CerdaDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? cerdaExistente;
  final int? hiveKey;

  const _CerdaDetailScreen({this.cerdaExistente, this.hiveKey});

  @override
  State<_CerdaDetailScreen> createState() => _CerdaDetailScreenState();
}

class _CerdaDetailScreenState extends State<_CerdaDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  late Box box;

  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _identificacionCtrl = TextEditingController();
  String? _estadoReproductivo;

  List<Map<String, dynamic>> _partos = [];
  List<Map<String, dynamic>> _vacunas = [];

  @override
  void initState() {
    super.initState();
    _abrirHive();

    if (widget.cerdaExistente != null) {
      final cerda = widget.cerdaExistente!;
      _nombreCtrl.text = cerda['nombre'] ?? '';
      _identificacionCtrl.text = cerda['identificacion'] ?? '';
      _estadoReproductivo = cerda['estado_reproductivo'];
      _partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
      _vacunas = List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []);
    }
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
  }

  Future<void> _guardarCerda() async {
    if (!_formKey.currentState!.validate()) return;

    final nuevaCerda = {
      'type': 'sow',
      'nombre': _nombreCtrl.text.trim(),
      'identificacion': _identificacionCtrl.text.trim(),
      'estado_reproductivo': _estadoReproductivo ?? 'No preñada',
      'partos': _partos,
      'vacunas': _vacunas,
    };

    if (widget.hiveKey != null) {
      await box.put(widget.hiveKey, nuevaCerda);
    } else {
      final existingKey = box.keys.firstWhere((key) {
        final data = box.get(key);
        return data['nombre'] == nuevaCerda['nombre'] ||
            data['identificacion'] == nuevaCerda['identificacion'];
      }, orElse: () => null);
      if (existingKey != null) {
        await box.put(existingKey, nuevaCerda);
      } else {
        await box.add(nuevaCerda);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cerda guardada correctamente 🐷')),
    );
    Navigator.pop(context);
  }

  void _agregarParto() {
    setState(() {
      _partos.add({
        'fecha_prez': null,
        'fecha_confirmacion': null,
        'fecha_parto': null,
        'num_lechones': null,
        'observaciones': '',
      });
    });
  }

  void _agregarVacuna() {
    setState(() {
      _vacunas.add({'nombre': '', 'fecha': null});
    });
  }

  Future<void> _seleccionarFecha(
    BuildContext context,
    Map<String, dynamic> item,
    String campo,
  ) async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (fecha != null) {
      setState(() {
        item[campo] = fecha.toIso8601String();
      });
    }
  }

  String _formatearFecha(String? fechaString) {
    if (fechaString == null) return 'Sin fecha';
    try {
      final fecha = DateTime.parse(fechaString);
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    } catch (e) {
      return fechaString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.cerdaExistente == null
              ? 'Agregar Cerda 🐖'
              : 'Detalles de Cerda 🐷',
        ),
        backgroundColor: Colors.pink,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Ingrese un nombre' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _identificacionCtrl,
                decoration: const InputDecoration(labelText: 'Identificación'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _estadoReproductivo,
                decoration: const InputDecoration(
                  labelText: 'Estado reproductivo',
                ),
                items: const [
                  DropdownMenuItem(value: 'Preñada', child: Text('Preñada')),
                  DropdownMenuItem(
                    value: 'No preñada',
                    child: Text('No preñada'),
                  ),
                ],
                onChanged: (v) => setState(() => _estadoReproductivo = v),
              ),
              const SizedBox(height: 20),

              // 🐖 Partos
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Historial de Partos 🐷',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: _agregarParto,
                    icon: const Icon(Icons.add_circle, color: Colors.pink),
                  ),
                ],
              ),
              ..._partos.asMap().entries.map((entry) {
                final i = entry.key;
                final parto = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Text(
                          'Parto ${i + 1} 🐽',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.pink,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => _seleccionarFecha(
                                  context,
                                  parto,
                                  'fecha_prez',
                                ),
                                child: Text(
                                  'Preñez: ${_formatearFecha(parto['fecha_prez'])}',
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextButton(
                                onPressed: () => _seleccionarFecha(
                                  context,
                                  parto,
                                  'fecha_confirmacion',
                                ),
                                child: Text(
                                  'Confirmación: ${_formatearFecha(parto['fecha_confirmacion'])}',
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => _seleccionarFecha(
                                  context,
                                  parto,
                                  'fecha_parto',
                                ),
                                child: Text(
                                  'Parto: ${_formatearFecha(parto['fecha_parto'])}',
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                initialValue:
                                    parto['num_lechones']?.toString() ?? '',
                                decoration: const InputDecoration(
                                  labelText: 'Lechones nacidos',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) => parto['num_lechones'] =
                                    int.tryParse(v) ?? 0,
                              ),
                            ),
                          ],
                        ),
                        TextFormField(
                          initialValue: parto['observaciones'] ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Observaciones',
                          ),
                          onChanged: (v) => parto['observaciones'] = v,
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => _partos.removeAt(i)),
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Eliminar parto'),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 20),

              // 💉 Vacunas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Vacunas 💉',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: _agregarVacuna,
                    icon: const Icon(Icons.add_circle, color: Colors.pink),
                  ),
                ],
              ),
              ..._vacunas.asMap().entries.map((entry) {
                final i = entry.key;
                final vacuna = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        TextFormField(
                          initialValue: vacuna['nombre'] ?? '',
                          decoration: const InputDecoration(
                            labelText: 'Nombre vacuna',
                          ),
                          onChanged: (v) => vacuna['nombre'] = v,
                        ),
                        TextButton(
                          onPressed: () =>
                              _seleccionarFecha(context, vacuna, 'fecha'),
                          child: Text(
                            'Fecha: ${_formatearFecha(vacuna['fecha'])}',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() => _vacunas.removeAt(i)),
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Eliminar vacuna'),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _guardarCerda,
                icon: const Icon(Icons.save),
                label: const Text('Guardar Cerda'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
