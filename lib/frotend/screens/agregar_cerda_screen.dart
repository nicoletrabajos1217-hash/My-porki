import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:my_porki/backend/services/sync_service.dart';

class AgregarCerdaScreen extends StatefulWidget {
  final Map<String, dynamic>? cerdaExistente; // Para editar
  final int? hiveKey; // Key de Hive para editar

  const AgregarCerdaScreen({super.key, this.cerdaExistente, this.hiveKey});

  @override
  State<AgregarCerdaScreen> createState() => _AgregarCerdaScreenState();
}

class _AgregarCerdaScreenState extends State<AgregarCerdaScreen> {
  final _nombreController = TextEditingController();
  final _identificacionController = TextEditingController();
  final _observacionController = TextEditingController();
  final _numLechonesController = TextEditingController();

  DateTime? _fechaPrez;
  DateTime? _fechaParto;
  String _estadoReproductivo = 'No preñada';
  List<Map<String, dynamic>> vacunas = [];

  @override
  void initState() {
    super.initState();
    if (widget.cerdaExistente != null) {
      _cargarDatosExistente();
    }
  }

  void _cargarDatosExistente() {
    _nombreController.text = widget.cerdaExistente!['nombre'] ?? '';
    _identificacionController.text = widget.cerdaExistente!['identificacion'] ?? '';
    _observacionController.text = widget.cerdaExistente!['observacion'] ?? '';
    _numLechonesController.text = widget.cerdaExistente!['num_lechones']?.toString() ?? '';
    _estadoReproductivo = widget.cerdaExistente!['estado_reproductivo'] ?? 'No preñada';

    // Convertir strings a DateTime
    if (widget.cerdaExistente!['fecha_prez'] != null) {
      _fechaPrez = DateTime.parse(widget.cerdaExistente!['fecha_prez']);
    }
    if (widget.cerdaExistente!['fecha_real_parto'] != null) {
      _fechaParto = DateTime.parse(widget.cerdaExistente!['fecha_real_parto']);
    }

    // Convertir las vacunas de string a DateTime
    vacunas = List<Map<String, dynamic>>.from(widget.cerdaExistente!['vacunas'] ?? [])
        .map((v) => {
              'nombre': v['nombre'],
              'fecha': DateTime.parse(v['fecha']) // Convertir a DateTime
            })
        .toList();
  }

  void agregarVacuna(String nombre, DateTime fecha) {
    setState(() {
      vacunas.add({'nombre': nombre, 'fecha': fecha});
    });
  }

  void editarVacuna(int index, String nombre, DateTime fecha) {
    setState(() {
      vacunas[index] = {'nombre': nombre, 'fecha': fecha};
    });
  }

  void eliminarVacuna(int index) {
    setState(() {
      vacunas.removeAt(index);
    });
  }

  Future<void> _seleccionarFecha(BuildContext context, bool esPrez) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (esPrez) {
          _fechaPrez = picked;
          // Si se selecciona fecha de preñez, cambiar estado automáticamente
          _estadoReproductivo = 'Preñada';
        } else {
          _fechaParto = picked;
        }
      });
    }
  }

  Future<void> guardarCerda() async {
    final nombre = _nombreController.text;
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El nombre es obligatorio")),
      );
      return;
    }

    // Solo validar fecha de preñez si el estado es "Preñada"
    if (_estadoReproductivo == 'Preñada' && _fechaPrez == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La fecha de preñez es obligatoria para cerdas preñadas")),
      );
      return;
    }

    DateTime? fechaEstimParto;
    if (_fechaPrez != null) {
      fechaEstimParto = _fechaPrez!.add(const Duration(days: 114));
    }

    int numLechones = _numLechonesController.text.isNotEmpty
        ? int.tryParse(_numLechonesController.text) ?? 0
        : 0;

    final cerdaData = {
      'nombre': nombre,
      'identificacion': _identificacionController.text,
      'estado_reproductivo': _estadoReproductivo,
      'observacion': _observacionController.text,
      'fecha_prez': _fechaPrez?.toIso8601String(),
      'fecha_estim_parto': fechaEstimParto?.toIso8601String(),
      'fecha_real_parto': _fechaParto?.toIso8601String(),
      'num_lechones': numLechones,
      'vacunas': vacunas
          .map((v) => {
                'nombre': v['nombre'],
                'fecha': v['fecha'].toIso8601String()
              })
          .toList(),
      'historial_partos': [],
      'type': 'sow',
      'localId': 'sow_${DateTime.now().millisecondsSinceEpoch}',
    };

    try {
      final box = await Hive.openBox('porki_data');

      if (widget.hiveKey != null) {
        await box.put(widget.hiveKey, cerdaData);
      } else {
        await box.add(cerdaData);
      }

      await SyncService().syncData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cerda guardada y sincronizada")),
      );

      _limpiarCampos();
      Navigator.pop(context);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al guardar: $e")),
      );
    }
  }

  void _limpiarCampos() {
    _nombreController.clear();
    _identificacionController.clear();
    _observacionController.clear();
    _numLechonesController.clear();
    _fechaPrez = null;
    _fechaParto = null;
    _estadoReproductivo = 'No preñada';
    vacunas.clear();
    setState(() {});
  }

  void mostrarDialogVacuna({int? index}) {
    final nombreController = TextEditingController();
    DateTime? fechaVacuna;

    if (index != null) {
      nombreController.text = vacunas[index]['nombre'];
      fechaVacuna = vacunas[index]['fecha'];
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index != null ? "Editar Vacuna" : "Agregar Vacuna"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(labelText: "Nombre de la vacuna"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                final fecha = await showDatePicker(
                  context: context,
                  initialDate: fechaVacuna ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (fecha != null) {
                  setState(() {
                    fechaVacuna = fecha;
                  });
                }
              },
              child: Text(fechaVacuna != null
                  ? "Fecha: ${fechaVacuna!.toLocal().toString().split(' ')[0]}"
                  : "Seleccionar fecha"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () {
              if (nombreController.text.isNotEmpty && fechaVacuna != null) {
                if (index != null) {
                  editarVacuna(index, nombreController.text, fechaVacuna!);
                } else {
                  agregarVacuna(nombreController.text, fechaVacuna!);
                }
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Completa todos los campos de la vacuna")),
                );
              }
            },
            child: Text(index != null ? "Guardar" : "Agregar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cerdaExistente != null ? "Editar Cerda" : "Agregar Cerda"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: "Nombre de la cerda*",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _identificacionController,
              decoration: const InputDecoration(
                labelText: "Número de identificación",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _estadoReproductivo,
              items: ['No preñada', 'Preñada', 'Lactante']
                  .map((estado) => DropdownMenuItem(
                        value: estado,
                        child: Text(estado),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _estadoReproductivo = value!),
              decoration: const InputDecoration(
                labelText: "Estado reproductivo",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacionController,
              decoration: const InputDecoration(
                labelText: "Observaciones (opcional)",
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Fecha de preñez (solo para cerdas preñadas)
            if (_estadoReproductivo == 'Preñada') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.pink),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fechaPrez != null
                            ? "Fecha de preñez: ${_fechaPrez!.toLocal().toString().split(' ')[0]}"
                            : "Selecciona fecha de preñez*",
                        style: TextStyle(
                          color: _fechaPrez == null ? Colors.red : Colors.black,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _seleccionarFecha(context, true),
                      child: const Text("Seleccionar"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Fecha de parto (opcional)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _fechaParto != null
                          ? "Fecha de parto: ${_fechaParto!.toLocal().toString().split(' ')[0]}"
                          : "Selecciona fecha de parto (opcional)",
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _seleccionarFecha(context, false),
                    child: const Text("Seleccionar"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _numLechonesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Número de lechones (opcional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Sección de vacunas
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Vacunas",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => mostrarDialogVacuna(),
                          icon: const Icon(Icons.add),
                          label: const Text("Agregar Vacuna"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (vacunas.isEmpty)
                      const Text(
                        "No hay vacunas registradas",
                        style: TextStyle(color: Colors.grey),
                      ),
                    if (vacunas.isNotEmpty)
                      ...vacunas.asMap().entries.map((entry) {
                        final i = entry.key;
                        final vacuna = entry.value;
                        return ListTile(
                          leading: const Icon(Icons.medical_services, color: Colors.green),
                          title: Text(vacuna['nombre']),
                          subtitle: Text("Fecha: ${vacuna['fecha'].toLocal().toString().split(' ')[0]}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => mostrarDialogVacuna(index: i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => eliminarVacuna(i),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: guardarCerda,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(
                widget.cerdaExistente != null ? "Actualizar Cerda" : "Guardar Cerda",
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}