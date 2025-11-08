import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:my_porki/backend/services/sync_service.dart';

class AgregarCerdaScreen extends StatefulWidget {
  final Map<String, dynamic>? cerdaExistente;
  final int? hiveKey;

  const AgregarCerdaScreen({super.key, this.cerdaExistente, this.hiveKey});

  @override
  State<AgregarCerdaScreen> createState() => _AgregarCerdaScreenState();
}

class _AgregarCerdaScreenState extends State<AgregarCerdaScreen> {
  final _nombreController = TextEditingController();
  final _identificacionController = TextEditingController();
  final _observacionController = TextEditingController();

  String _estadoReproductivo = 'No preñada';
  List<Map<String, dynamic>> _partos = [];
  List<Map<String, dynamic>> _vacunas = [];

  @override
  void initState() {
    super.initState();
    if (widget.cerdaExistente != null) _cargarDatosExistente();
  }

  void _cargarDatosExistente() {
    final cerda = widget.cerdaExistente!;
    _nombreController.text = cerda['nombre'] ?? '';
    _identificacionController.text = cerda['identificacion'] ?? '';
    _observacionController.text = cerda['observacion'] ?? '';
    _estadoReproductivo = cerda['estado_reproductivo'] ?? 'No preñada';
    _partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
    _vacunas = List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []);
  }

  void _agregarParto({Map<String, dynamic>? partoExistente, int? index}) {
    final TextEditingController lechonesCtrl = TextEditingController(
      text: partoExistente?['num_lechones']?.toString() ?? '',
    );
    final TextEditingController observacionCtrl = TextEditingController(
      text: partoExistente?['observaciones'] ?? '',
    );

    DateTime? fechaPrez = partoExistente?['fecha_prez'] != null
        ? DateTime.parse(partoExistente!['fecha_prez'])
        : null;
    DateTime? fechaConfirm = partoExistente?['fecha_confirmacion'] != null
        ? DateTime.parse(partoExistente!['fecha_confirmacion'])
        : null;
    DateTime? fechaParto = partoExistente?['fecha_parto'] != null
        ? DateTime.parse(partoExistente!['fecha_parto'])
        : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          partoExistente != null ? "Editar parto 🐷" : "Agregar nuevo parto 🐷",
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFechaButton(
                label: "Fecha de preñez",
                fecha: fechaPrez,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: fechaPrez ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => fechaPrez = picked);
                },
              ),
              _buildFechaButton(
                label: "Fecha de confirmación",
                fecha: fechaConfirm,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: fechaConfirm ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => fechaConfirm = picked);
                },
              ),
              _buildFechaButton(
                label: "Fecha de parto",
                fecha: fechaParto,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: fechaParto ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => fechaParto = picked);
                },
              ),
              TextField(
                controller: lechonesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "N° de lechones"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: observacionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Observaciones (opcional)",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () {
              final parto = {
                'fecha_prez': fechaPrez?.toIso8601String(),
                'fecha_confirmacion': fechaConfirm?.toIso8601String(),
                'fecha_parto': fechaParto?.toIso8601String(),
                'num_lechones': int.tryParse(lechonesCtrl.text) ?? 0,
                'observaciones': observacionCtrl.text,
              };
              setState(() {
                if (index != null) {
                  _partos[index] = parto;
                } else {
                  _partos.add(parto);
                }
              });
              Navigator.pop(context);
            },
            child: const Text("Guardar", style: TextStyle(color: Colors.pink)),
          ),
        ],
      ),
    );
  }

  void _agregarVacuna({Map<String, dynamic>? vacunaExistente, int? index}) {
    final TextEditingController nombreCtrl = TextEditingController(
      text: vacunaExistente?['nombre'] ?? '',
    );
    DateTime? fecha = vacunaExistente?['fecha'] != null
        ? DateTime.parse(vacunaExistente!['fecha'])
        : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          vacunaExistente != null ? "Editar vacuna 💉" : "Agregar vacuna 💉",
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: "Nombre vacuna"),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: fecha ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => fecha = picked);
              },
              icon: const Icon(Icons.calendar_today, color: Colors.white),
              label: Text(
                fecha != null
                    ? "Fecha: ${fecha!.toLocal().toString().split(' ')[0]}"
                    : "Seleccionar fecha",
              ),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
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
              if (nombreCtrl.text.isEmpty || fecha == null) return;
              final vacuna = {
                'nombre': nombreCtrl.text,
                'fecha': fecha!.toIso8601String(),
              };
              setState(() {
                if (index != null) {
                  _vacunas[index] = vacuna;
                } else {
                  _vacunas.add(vacuna);
                }
              });
              Navigator.pop(context);
            },
            child: const Text("Guardar", style: TextStyle(color: Colors.pink)),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarCerda() async {
    final nombre = _nombreController.text.trim();
    final id = _identificacionController.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El nombre es obligatorio 🐷")),
      );
      return;
    }

    final cerdaData = {
      'nombre': nombre,
      'identificacion': id,
      'estado_reproductivo': _estadoReproductivo,
      'observacion': _observacionController.text,
      'partos': _partos,
      'vacunas': _vacunas,
      'type': 'sow',
      'localId': 'sow_${DateTime.now().millisecondsSinceEpoch}',
    };

    try {
      final box = await Hive.openBox('porki_data');
      final existingKey = box.keys.firstWhere((key) {
        final data = box.get(key);
        return data['nombre'] == nombre || data['identificacion'] == id;
      }, orElse: () => null);

      if (existingKey != null) {
        await box.put(existingKey, cerdaData);
      } else {
        await box.add(cerdaData);
      }

      await SyncService().syncData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cerda guardada correctamente 🐖")),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error al guardar: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.cerdaExistente != null ? "Editar Cerda 🐷" : "Nueva Cerda 🐖",
        ),
        backgroundColor: Colors.pink,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildTextCard(),
            _buildEstadoCard(),
            _buildPartosCard(),
            _buildVacunasCard(),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _guardarCerda,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text("Guardar Cerda"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildTextCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: "Nombre 🐷"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _identificacionController,
              decoration: const InputDecoration(labelText: "Identificación"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _estadoReproductivo,
              items: [
                'No preñada',
                'Preñada',
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _estadoReproductivo = v!),
              decoration: const InputDecoration(
                labelText: "Estado reproductivo",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacionController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: "Observaciones"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartosCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Historial de partos 🍼",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => _agregarParto(),
                  icon: const Icon(Icons.add),
                  label: const Text("Agregar"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_partos.isEmpty)
              const Text(
                "No hay partos registrados 🐖",
                style: TextStyle(color: Colors.grey),
              ),
            if (_partos.isNotEmpty)
              ..._partos.asMap().entries.map((entry) {
                final i = entry.key;
                final parto = entry.value;
                return ListTile(
                  leading: const Text("🐷", style: TextStyle(fontSize: 26)),
                  title: Text(
                    "Parto ${i + 1} - ${parto['fecha_parto']?.toString().split('T').first ?? 'Sin fecha'}",
                  ),
                  subtitle: Text(
                    "Lechones: ${parto['num_lechones'] ?? 0}\nObs: ${parto['observaciones'] ?? ''}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _agregarParto(partoExistente: parto, index: i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => _partos.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildVacunasCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Vacunas 💉",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => _agregarVacuna(),
                  icon: const Icon(Icons.add),
                  label: const Text("Agregar"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_vacunas.isEmpty)
              const Text(
                "No hay vacunas registradas 🐷",
                style: TextStyle(color: Colors.grey),
              ),
            if (_vacunas.isNotEmpty)
              ..._vacunas.asMap().entries.map((entry) {
                final i = entry.key;
                final vacuna = entry.value;
                return ListTile(
                  leading: const Icon(Icons.vaccines, color: Colors.green),
                  title: Text(vacuna['nombre']),
                  subtitle: Text(
                    "Fecha: ${DateTime.parse(vacuna['fecha']).toLocal().toString().split(' ')[0]}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _agregarVacuna(vacunaExistente: vacuna, index: i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => _vacunas.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildFechaButton({
    required String label,
    DateTime? fecha,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.calendar_today, color: Colors.white),
        label: Text(
          fecha != null
              ? "$label: ${fecha.toLocal().toString().split(' ')[0]}"
              : label,
        ),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
      ),
    );
  }
}
