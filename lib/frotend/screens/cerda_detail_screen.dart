import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // 👈 importante: NO 'hive.dart'
import 'package:my_porki/backend/services/sync_service.dart';
import 'package:my_porki/backend/services/sow_service.dart';

/// ✅ Pantalla principal: lista de cerdas + detalle individual
class CerdasScreen extends StatefulWidget {
  final Map<String, dynamic>? openCerda;
  final int? openKey;

  const CerdasScreen({super.key, this.openCerda, this.openKey});

  @override
  State<CerdasScreen> createState() => _CerdasScreenState();
}

class _CerdasScreenState extends State<CerdasScreen> {
  late Box box;
  bool _loading = true;
  bool _soloActuales = false;

  @override
  void initState() {
    super.initState();
    _abrirHive();
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
    setState(() => _loading = false);

    if (widget.openCerda != null) {
      // Abrir detalle inmediato
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _abrirDetalle(cerda: widget.openCerda, key: widget.openKey);
      });
    }
  }

  void _abrirDetalle({Map<String, dynamic>? cerda, int? key}) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CerdaDetailScreen(cerdaExistente: cerda, hiveKey: key),
      ),
    );

    // Refrescar lista si hubo cambios
    if (resultado == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cerdas 🐷'),
        actions: [
          IconButton(
            tooltip: _soloActuales ? 'Mostrar todas' : 'Mostrar solo actuales',
            icon: Icon(
              _soloActuales ? Icons.filter_alt_off : Icons.filter_alt,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _soloActuales = !_soloActuales),
          ),
        ],
        backgroundColor: Colors.pink,
      ),
      // Se removió el FloatingActionButton '+' en 'Mis Cerdas' por solicitud.
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.pink))
          : ValueListenableBuilder(
              valueListenable: Hive.box('porki_data').listenable(),
              builder: (context, Box box, _) {
                final all = box.values
                    .where((item) => item is Map && item['type'] == 'sow')
                    .cast<Map>()
                    .toList();

                List cerdas = all;
                if (_soloActuales) {
                  cerdas = all.where((item) {
                    final cerda = Map<String, dynamic>.from(item);
                    final estado = (cerda['estado_reproductivo'] ?? '')
                        .toString()
                        .toLowerCase();
                    // Considerar no actuales si fueron retiradas/muertas/vendidas
                    return !(estado.contains('retir') ||
                        estado.contains('muert') ||
                        estado.contains('vend'));
                  }).toList();
                }

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
                    // obtener hive key buscando la posición real
                    final key = box.keys.firstWhere(
                      (k) => box.get(k) == cerda,
                      orElse: () => null,
                    );
                    final nombre = cerda['nombre'] ?? 'Sin nombre';
                    final id = cerda['identificacion'] ?? 'Sin ID';
                    final embarazada = cerda['embarazada'] ?? false;
                    final lechonesEnVientre = cerda['lechones_en_vientre'] ?? 0;
                    final lechonesNacidos = cerda['lechones_nacidos'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      color: embarazada ? Colors.blue[50] : Colors.white,
                      child: ListTile(
                        leading: Text(
                          '🐷',
                          style: const TextStyle(fontSize: 28),
                        ),
                        title: Text(
                          nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ID: $id'),
                            if (embarazada) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🐷 Preña • $lechonesEnVientre lechones',
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            if (lechonesNacidos > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🐽 $lechonesNacidos lechones nacidos',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: embarazada || lechonesNacidos > 0
                            ? true
                            : false,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Eliminar cerda',
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final confirmar = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Eliminar Cerda'),
                                    content: Text(
                                      '¿Deseas eliminar "$nombre"? Esta acción se eliminará localmente y se marcará para sincronizar la eliminación.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text(
                                          'Eliminar',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmar == true) {
                                  try {
                                    // Eliminar localmente por clave Hive (si existe)
                                    if (key != null) await box.delete(key);

                                    // Si la cerda tiene sowId, usar SowService para manejar eliminación y sync
                                    final sowId = cerda['sowId'];
                                    if (sowId != null) {
                                      await SowService.eliminarCerda(
                                        sowId.toString(),
                                      );
                                    }

                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Cerda "$nombre" eliminada',
                                        ),
                                      ),
                                    );
                                    setState(() {});
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error al eliminar: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.pink,
                              ),
                              onPressed: () => _abrirDetalle(
                                cerda: Map<String, dynamic>.from(cerda),
                                key: key,
                              ),
                            ),
                          ],
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
  final SyncService _syncService = SyncService();

  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _identificacionCtrl = TextEditingController();
  final TextEditingController _lechonesCtrl = TextEditingController(text: '0');
  String? _estadoReproductivo;
  bool _embarazada = false;
  int _lechonesEnVientre = 0;
  int _lechonesNacidos = 0;
  bool _guardando = false;

  List<Map<String, dynamic>> _partos = [];
  List<Map<String, dynamic>> _vacunas = [];
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _abrirHive();

    if (widget.cerdaExistente != null) {
      final cerda = widget.cerdaExistente!;
      _nombreCtrl.text = cerda['nombre'] ?? '';
      _identificacionCtrl.text = cerda['identificacion'] ?? '';
      _estadoReproductivo = cerda['estado_reproductivo'];
      _embarazada = cerda['embarazada'] ?? false;
      _lechonesEnVientre = cerda['lechones_en_vientre'] ?? 0;
      _lechonesNacidos = cerda['lechones_nacidos'] ?? 0;
      _lechonesCtrl.text = _lechonesNacidos.toString();
      _partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
      _vacunas = List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []);
      _historial = List<Map<String, dynamic>>.from(cerda['historial'] ?? []);
    }
  }

  Future<void> _abrirHive() async {
    box = await Hive.openBox('porki_data');
  }

  Future<void> _guardarCerda() async {
    if (!_formKey.currentState!.validate()) return;
    if (_guardando) return;

    setState(() => _guardando = true);

    try {
      // Detectar cambios y agregar al historial
      Map<String, dynamic> cambios = {};
      if (widget.cerdaExistente != null) {
        if (widget.cerdaExistente!['embarazada'] != _embarazada) {
          cambios['embarazada'] = _embarazada
              ? 'Preñada ahora'
              : 'Ya no preñada';
        }
        if (widget.cerdaExistente!['lechones_nacidos'] != _lechonesNacidos) {
          cambios['lechones_nacidos'] =
              'De ${widget.cerdaExistente!['lechones_nacidos'] ?? 0} a $_lechonesNacidos';
        }
        if (widget.cerdaExistente!['lechones_en_vientre'] !=
            _lechonesEnVientre) {
          cambios['lechones_en_vientre'] =
              'De ${widget.cerdaExistente!['lechones_en_vientre'] ?? 0} a $_lechonesEnVientre';
        }
      }

      // Agregar al historial si hay cambios
      if (cambios.isNotEmpty) {
        _historial.add({
          'tipo': 'edicion_prenez',
          'fecha': DateTime.now().toIso8601String(),
          'cambios': cambios,
        });
      }

      final nuevaCerda = {
        'type': 'sow',
        'nombre': _nombreCtrl.text.trim(),
        'identificacion': _identificacionCtrl.text.trim(),
        'estado_reproductivo': _estadoReproductivo ?? 'No preñada',
        'embarazada': _embarazada,
        'lechones_en_vientre': _lechonesEnVientre,
        'lechones_nacidos': _lechonesNacidos,
        'partos': _partos,
        'vacunas': _vacunas,
        'historial': _historial,
        'updatedAt': DateTime.now().toIso8601String(),
        'sowId':
            widget.cerdaExistente?['sowId'] ??
            'sow_${DateTime.now().millisecondsSinceEpoch}',
      };

      // Guardar en Hive
      int? hiveKey;
      if (widget.hiveKey != null) {
        hiveKey = widget.hiveKey!;
        await box.put(hiveKey, nuevaCerda);
        print('💾 Cerda actualizada en Hive: ${_nombreCtrl.text}');
      } else {
        hiveKey = await box.add(nuevaCerda);
        print('💾 Cerda guardada en Hive: ${_nombreCtrl.text}');
      }

      // Sincronizar con Firebase
      await _syncService.syncSowSafe(nuevaCerda, localKey: hiveKey);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Cerda guardada correctamente 🐷'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(
        context,
        true,
      ); // Retorna true para indicar que hubo cambios
    } catch (e) {
      if (!mounted) return;
      print('❌ Error guardando cerda: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
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
        elevation: 4,
      ),
      backgroundColor: Colors.white,
      body: _guardando
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.pink),
                  const SizedBox(height: 16),
                  const Text('Guardando cambios...'),
                ],
              ),
            )
          : SingleChildScrollView(
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
                      decoration: const InputDecoration(
                        labelText: 'Identificación',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _estadoReproductivo,
                      decoration: const InputDecoration(
                        labelText: 'Estado reproductivo',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Preñada',
                          child: Text('Preñada'),
                        ),
                        DropdownMenuItem(
                          value: 'No preñada',
                          child: Text('No preñada'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _estadoReproductivo = v),
                    ),
                    const SizedBox(height: 20),

                    // 🐷 Información General
                    Card(
                      color: Colors.pink[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Información General 🐷',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.pink,
                              ),
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _lechonesCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cerditos que parió 🐷',
                                hintText: '0',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) =>
                                  _lechonesNacidos = int.tryParse(v) ?? 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 🐷 Resumen de Cerditos
                    if (_lechonesNacidos > 0)
                      Card(
                        color: Colors.green[50],
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resumen de Cerditos 🐷',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.green[200] ?? Colors.green,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Total:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '$_lechonesNacidos 🐷',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // 💉 Vacunas
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Vacunas 💉',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: _agregarVacuna,
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.pink,
                          ),
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
                                onPressed: () =>
                                    setState(() => _vacunas.removeAt(i)),
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                label: const Text('Eliminar vacuna'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 30),

                    // 📋 NUEVA SECCIÓN: Historial de Cambios
                    if (_historial.isNotEmpty ||
                        _embarazada ||
                        _lechonesNacidos > 0) ...[
                      Card(
                        color: Colors.amber[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.history,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Historial de Cambios 📋',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Mostrar estado actual como primer item
                              if (_embarazada || _lechonesNacidos > 0) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.green[200] ?? Colors.green,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Estado Actual 📊',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (_embarazada)
                                        Text(
                                          '• Preñada: SÍ (${_lechonesEnVientre} lechones esperados)',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      if (_lechonesNacidos > 0)
                                        Text(
                                          '• Lechones Nacidos: $_lechonesNacidos',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                              ],

                              // Mostrar historial de cambios previos
                              if (_historial.isNotEmpty) ...[
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text(
                                  'Cambios Previos',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ..._historial.asMap().entries.map((entry) {
                                  final cambio = entry.value;
                                  final cambios =
                                      cambio['cambios'] as Map<String, dynamic>;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color:
                                            Colors.amber[200] ?? Colors.amber,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _formatearFecha(cambio['fecha']),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        ...cambios.entries.map(
                                          (c) => Text(
                                            '• ${c.key}: ${c.value}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ] else if (_embarazada ||
                                  _lechonesNacidos > 0) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Sin cambios previos registrados',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

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
