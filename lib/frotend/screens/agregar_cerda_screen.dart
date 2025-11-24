import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_porki/backend/services/sow_service.dart';

class AgregarCerdaScreen extends StatefulWidget {
  final Map<String, dynamic>? cerdaExistente;

  const AgregarCerdaScreen({super.key, this.cerdaExistente});

  @override
  State<AgregarCerdaScreen> createState() => _AgregarCerdaScreenState();
}

class _AgregarCerdaScreenState extends State<AgregarCerdaScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _idCtrl;
  late String _nombre;
  DateTime? _fechaPrenez;
  List<Map<String, dynamic>> _partos = [];
  List<Map<String, dynamic>> _vacunas = [];
  bool _guardando = false;
  String _estadoReproductivo = 'No preñada';

  final DateFormat _fechaFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    if (widget.cerdaExistente != null) {
      _idCtrl = widget.cerdaExistente!['id'] ?? '';
      _nombre = widget.cerdaExistente!['nombre'] ?? '';
      _fechaPrenez = widget.cerdaExistente!['fecha_prenez'] != null
          ? DateTime.tryParse(widget.cerdaExistente!['fecha_prenez'])
          : null;
      _partos = List<Map<String, dynamic>>.from(
        widget.cerdaExistente!['partos'] ?? [],
      );
      _vacunas = List<Map<String, dynamic>>.from(
        widget.cerdaExistente!['vacunas'] ?? [],
      );
      _estadoReproductivo = widget.cerdaExistente!['estado'] ?? 'No preñada';
    } else {
      _idCtrl = '';
      _nombre = '';
    }
  }

  Future<void> _guardarCerda() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _guardando = true);

    try {
      // Generar ID único si no se ingresó
      final id = _idCtrl.isNotEmpty
          ? _idCtrl
          : 'sow_${DateTime.now().millisecondsSinceEpoch}';

      // CORREGIDO: Procesar partos para asegurar formato correcto
      final partosProcesados = _partos.map((p) {
        return {
          "fecha": p['fecha']?.toString().isNotEmpty == true
              ? p['fecha']
              : null,
          "num_lechones": p['num_lechones'] is int
              ? p['num_lechones']
              : int.tryParse(p['num_lechones']?.toString() ?? '0') ?? 0,
        };
      }).toList();

      // CORREGIDO: Procesar vacunas para asegurar formato correcto
      final vacunasProcesadas = _vacunas.map((v) {
        return {
          "nombre": v['nombre']?.toString() ?? '',
          "dosis": v['dosis'] is int
              ? v['dosis']
              : int.tryParse(v['dosis']?.toString() ?? '1') ?? 1,
          "frecuencia_dias": v['frecuencia_dias'] is int
              ? v['frecuencia_dias']
              : int.tryParse(v['frecuencia_dias']?.toString() ?? '30') ?? 30,
          "dosis_programadas": v['dosis_programadas'] ?? [],
        };
      }).toList();

      if (widget.cerdaExistente != null) {
        await SowService.actualizarCerda(
          id: id,
          nombre: _nombre,
          fechaPrenez: _fechaPrenez,
          partos: partosProcesados,
          vacunas: vacunasProcesadas,
          estado: _estadoReproductivo,
        );
      } else {
        await SowService.agregarCerda(
          idCtrl: id,
          nombre: _nombre,
          fechaPrenez: _fechaPrenez,
          partos: partosProcesados,
          vacunas: vacunasProcesadas,
          estado: _estadoReproductivo,
        );
      }

      _mostrarExito("🐷 Cerda guardada correctamente");

      // CORREGIDO: Esperar un momento antes de navegar para asegurar que se guarde
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _mostrarError("❌ Error al guardar: $e");
      print('❌ ERROR DETALLADO: $e');
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  void _seleccionarFechaPrenez() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaPrenez ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha != null) setState(() => _fechaPrenez = fecha);
  }

  void _agregarParto() =>
      setState(() => _partos.add({"fecha": null, "num_lechones": 0}));

  void _agregarVacuna() => setState(
    () => _vacunas.add({
      "nombre": "",
      "dosis": 1,
      "frecuencia_dias": 30,
      "dosis_programadas": [],
    }),
  );

  void _mostrarExito(String mensaje) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
      );

  void _mostrarError(String mensaje) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: Colors.red));

  String _mostrarFecha(DateTime? fecha) =>
      fecha != null ? _fechaFormat.format(fecha) : 'Seleccionar 🐷';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.cerdaExistente != null ? "Editar Cerda 🐷" : "Nueva Cerda 🐷",
        ),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _guardando ? null : _guardarCerda,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ID manual
              TextFormField(
                initialValue: _idCtrl,
                decoration: const InputDecoration(
                  labelText: "ID / Número de la cerda (Manual)",
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Ingrese el ID' : null,
                onSaved: (val) => _idCtrl = val!.trim(),
              ),
              const SizedBox(height: 12),

              // Nombre
              TextFormField(
                initialValue: _nombre,
                decoration: const InputDecoration(labelText: "Nombre 🐷"),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Ingrese nombre' : null,
                onSaved: (val) => _nombre = val!.trim(),
              ),
              const SizedBox(height: 12),

              // Estado reproductivo
              Row(
                children: [
                  const Text("Estado reproductivo: "),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _estadoReproductivo,
                    items: ['No preñada', 'Preñada']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _estadoReproductivo = val!;
                        if (val == 'Preñada' && _fechaPrenez == null)
                          _seleccionarFechaPrenez();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Fecha de preñez
              Row(
                children: [
                  const Icon(Icons.pets, color: Colors.pink),
                  const SizedBox(width: 8),
                  Text("Fecha preñez: ${_mostrarFecha(_fechaPrenez)}"),
                  const Spacer(),
                  TextButton(
                    onPressed: _seleccionarFechaPrenez,
                    child: const Text("Seleccionar fecha"),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // PARTOS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Partos 🐷",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _agregarParto,
                    icon: const Icon(Icons.add),
                    label: const Text("Agregar parto"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._partos.asMap().entries.map((entry) {
                final index = entry.key;
                final parto = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextFormField(
                          initialValue: parto['fecha'],
                          decoration: const InputDecoration(
                            labelText: "Fecha parto (dd/mm/yyyy)",
                          ),
                          onSaved: (val) => parto['fecha'] =
                              val?.isNotEmpty == true ? val : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: parto['num_lechones']?.toString(),
                          decoration: const InputDecoration(
                            labelText: "Número de lechones",
                          ),
                          keyboardType: TextInputType.number,
                          // CORREGIDO: Asegurar que sea int
                          onSaved: (val) => parto['num_lechones'] =
                              int.tryParse(val ?? '0') ?? 0,
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 20),

              // VACUNAS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Vacunas 💉",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _agregarVacuna,
                    icon: const Icon(Icons.add),
                    label: const Text("Agregar vacuna"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._vacunas.asMap().entries.map((entry) {
                final index = entry.key;
                final vacuna = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextFormField(
                          initialValue: vacuna['nombre'],
                          decoration: const InputDecoration(
                            labelText: "Nombre vacuna",
                          ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Ingrese nombre de la vacuna'
                              : null,
                          onSaved: (val) => vacuna['nombre'] = val!.trim(),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: vacuna['dosis']?.toString(),
                          decoration: const InputDecoration(
                            labelText: "Número de dosis",
                          ),
                          keyboardType: TextInputType.number,
                          // CORREGIDO: Asegurar que sea int
                          onSaved: (val) =>
                              vacuna['dosis'] = int.tryParse(val ?? '1') ?? 1,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: vacuna['frecuencia_dias']?.toString(),
                          decoration: const InputDecoration(
                            labelText: "Frecuencia (días)",
                          ),
                          keyboardType: TextInputType.number,
                          // CORREGIDO: Asegurar que sea int
                          onSaved: (val) => vacuna['frecuencia_dias'] =
                              int.tryParse(val ?? '30') ?? 30,
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 20),

              // BOTONES DE CONFIRMAR PREÑEZ / PARTO
              if (_estadoReproductivo == 'Preñada' && _fechaPrenez != null)
                Builder(
                  builder: (context) {
                    final diasDesdePrenez = DateTime.now()
                        .difference(_fechaPrenez!)
                        .inDays;
                    return Column(
                      children: [
                        if (diasDesdePrenez >= 21)
                          ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                _estadoReproductivo = 'Preñada';
                              });
                              await _guardarCerda(); // Guardar cambios
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Preñez confirmada'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text("Confirmar preñez"),
                          ),
                        if (diasDesdePrenez >= 114)
                          ElevatedButton(
                            onPressed: () async {
                              int? numLechones = await showDialog<int>(
                                context: context,
                                builder: (context) {
                                  int tempLechones = 0;
                                  return AlertDialog(
                                    title: const Text("Número de lechones 🐷"),
                                    content: TextField(
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        hintText: "Ingrese número de lechones",
                                      ),
                                      onChanged: (val) =>
                                          tempLechones = int.tryParse(val) ?? 0,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text("Cancelar"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(
                                          context,
                                          tempLechones,
                                        ),
                                        child: const Text("Guardar"),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (numLechones != null) {
                                setState(() {
                                  _partos.add({
                                    "fecha": _fechaPrenez!.toIso8601String(),
                                    "num_lechones": numLechones,
                                  });
                                  _estadoReproductivo = 'No preñada';
                                  _fechaPrenez = null;
                                });
                                await _guardarCerda(); // Guardar cambios
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '✅ Parto confirmado con $numLechones lechones',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text("Confirmar parto"),
                          ),
                      ],
                    );
                  },
                ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _guardando ? null : _guardarCerda,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 24,
                  ),
                ),
                child: Text(
                  _guardando ? "Guardando..." : "Guardar Cerda",
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
