import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CerdaScreen extends StatefulWidget {
  final String? cerdaId;

  const CerdaScreen({super.key, this.cerdaId});

  @override
  State<CerdaScreen> createState() => _CerdaScreenState();
}

class _CerdaScreenState extends State<CerdaScreen> {
  Map<String, dynamic>? _cerda;
  List<Map<String, dynamic>>? _cerdasList;
  bool _cargando = true;
  bool _guardando = false;

  final _formKey = GlobalKey<FormState>();
  final DateFormat _fechaFormat = DateFormat('dd/MM/yyyy');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    print('🔧 CerdaScreen iniciado con cerdaId: ${widget.cerdaId}');
    _cargarCerda();
  }

  Future<void> _cargarCerda() async {
    setState(() => _cargando = true);

    try {
      // Si no se proporcionó un cerdaId, cargamos la lista de cerdas
      if (widget.cerdaId == null) {
        await _cargarListaCerdas();
        return;
      }
      
      // Cargar cerda específica
      await _cargarCerdaIndividual();
    } catch (e) {
      print('❌ Error cargando cerda: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error cargando cerda: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarListaCerdas() async {
    try {
      print('📦 Cargando lista de cerdas...');
      
      // Usar SowService.obtenerCerdas() en lugar de acceder directamente a Hive
      final cerdas = await SowService.obtenerCerdas();
      
      print('✅ Cerdas cargadas desde servicio: ${cerdas.length}');
      
      if (mounted) {
        setState(() => _cerdasList = cerdas);
      }
    } catch (e) {
      print('❌ Error cargando lista de cerdas: $e');
      if (mounted) {
        setState(() => _cerdasList = []);
      }
    }
  }

  Future<void> _cargarCerdaIndividual() async {
    try {
      // Usar 'porki_data' en lugar de 'cerdas'
      final box = await Hive.openBox('porki_data');
      
      print('🔍 Buscando cerda con ID: ${widget.cerdaId}');
      
      // Buscar en Hive primero
      Map<String, dynamic>? localCerda;
      for (var key in box.keys) {
        final item = box.get(key);
        if (item is Map && item['id'] == widget.cerdaId) {
          localCerda = <String, dynamic>{};
          item.forEach((k, v) => localCerda![k.toString()] = v);
          localCerda['hiveKey'] = key;
          break;
        }
      }

      // Usar colección 'sows' en lugar de 'cerdas'
      Map<String, dynamic>? firestoreCerda;
      try {
        final doc = await _firestore.collection('sows').doc(widget.cerdaId).get();
        if (doc.exists) {
          firestoreCerda = doc.data();
          firestoreCerda?['id'] = doc.id;
        }
      } catch (e) {
        print('⚠️ Error obteniendo cerda de Firestore: $e');
      }

      // Combinar datos (priorizar Firestore pero preservar datos locales)
      _cerda = firestoreCerda ?? localCerda;

      if (_cerda != null) {
        // Preservar datos locales si existen
        if (localCerda != null) {
          _cerda!['hiveKey'] = localCerda['hiveKey'];
          _cerda!['partos'] = localCerda['partos'] ?? _cerda!['partos'] ?? [];
          _cerda!['vacunas'] = localCerda['vacunas'] ?? _cerda!['vacunas'] ?? [];
          _cerda!['historial'] = localCerda['historial'] ?? _cerda!['historial'] ?? [];
        } else {
          _cerda!['partos'] ??= [];
          _cerda!['vacunas'] ??= [];
          _cerda!['historial'] ??= [];
        }
        
        print('✅ Cerda cargada: ${_cerda!['nombre']}');
      } else {
        print('❌ Cerda no encontrada');
      }
    } catch (e) {
      print('❌ Error en _cargarCerdaIndividual: $e');
    }
  }

  int get totalLechones {
    final partos = (_cerda?['partos'] as List<dynamic>?) ?? [];
    int total = 0;

    for (var parto in partos) {
      final numLechones = parto['num_lechones'];
      total += (numLechones is int ? numLechones : int.tryParse('$numLechones') ?? 0);
    }

    return total;
  }

  Future<void> _guardarCerda() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _guardando = true);
    try {
      final id = _cerda!['id'];
      
      // Asegurar que tenga los campos necesarios
      _cerda!['type'] = 'sow';
      _cerda!['fecha_actualizacion'] = DateTime.now().toIso8601String();
      _cerda!['synced'] = false;

      print('💾 Guardando cerda: $id');

      // Guardar en 'porki_data' en lugar de 'cerdas'
      final box = await Hive.openBox('porki_data');
      final hiveKey = _cerda!['hiveKey'] ?? id;
      
      // FORZAR EL GUARDADO PARA NOTIFICAR CAMBIOS
      await box.put(hiveKey, _cerda);
      
      print('✅ Guardado en Hive local - cambios notificados');

      // Guardar en colección 'sows' en lugar de 'cerdas'
      try {
        await _firestore.collection('sows').doc(id).set(_cerda!, SetOptions(merge: true));
        
        // Marcar como sincronizado
        _cerda!['synced'] = true;
        await box.put(hiveKey, _cerda);
        
        print('✅ Sincronizado con Firebase');
      } catch (e) {
        print('⚠️ Error sincronizando con Firebase: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Cerda guardada correctamente 🐷"),
              backgroundColor: Colors.green),
        );
        
        // Opcional: Navegar back después de guardar exitosamente
        // Navigator.pop(context);
      }
    } catch (e) {
      print('❌ Error al guardar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al guardar: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminarCerda() async {
    final confirmacion = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Deseas eliminar a "${_cerda!['nombre']}"?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmacion != true) return;

    try {
      final id = _cerda!['id'];
      final hiveKey = _cerda!['hiveKey'];

      // Eliminar de Hive
      final box = await Hive.openBox('porki_data');
      await box.delete(hiveKey);
      
      // Eliminar de Firebase
      try {
        await _firestore.collection('sows').doc(id).delete();
      } catch (e) {
        print('⚠️ Error eliminando de Firebase: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cerda eliminada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('❌ Error eliminando: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _agregarParto() {
    setState(() {
      (_cerda!['partos'] as List).add({"fecha": null, "num_lechones": 0});
    });
  }

  void _agregarVacuna() {
    setState(() {
      (_cerda!['vacunas'] as List).add({
        "nombre": "",
        "dosis": 1,
        "frecuencia_dias": 30,
        "dosis_programadas": [],
      });
    });
  }

  void _eliminarParto(int index) {
    setState(() {
      (_cerda!['partos'] as List).removeAt(index);
    });
  }

  void _eliminarVacuna(int index) {
    setState(() {
      (_cerda!['vacunas'] as List).removeAt(index);
    });
  }

  String _mostrarFecha(String? fecha) {
    if (fecha == null) return 'Seleccionar 🐷';
    try {
      return _fechaFormat.format(DateTime.parse(fecha));
    } catch (_) {
      return fecha;
    }
  }

  Future<void> _seleccionarFecha(int index) async {
    final current = (_cerda!['partos'] as List)[index]['fecha'] != null
        ? DateTime.tryParse((_cerda!['partos'] as List)[index]['fecha'])
        : DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha != null) {
      setState(() {
        (_cerda!['partos'] as List)[index]['fecha'] = fecha.toIso8601String();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cargando...'),
          backgroundColor: Colors.pink,
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.pink)),
      );
    }

    // Si no se pasó cerdaId, mostramos la lista de cerdas
    if (widget.cerdaId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mis Cerdas 🐷'),
          backgroundColor: Colors.pink,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() => _cargando = true);
                await _cargarListaCerdas();
                setState(() => _cargando = false);
              },
            ),
          ],
        ),
        body: _cerdasList == null || _cerdasList!.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.pets, size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No hay cerdas disponibles',
                        style: TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 8),
                    const Text('Agrega cerdas desde el menú principal',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        setState(() => _cargando = true);
                        await _cargarListaCerdas();
                        setState(() => _cargando = false);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recargar'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _cerdasList!.length,
                itemBuilder: (context, index) {
                  final c = _cerdasList![index];
                  final id = c['id'] ?? 'Sin ID';
                  final nombre = c['nombre'] ?? 'Sin nombre';
                  final estado = c['estado'] ?? 'No preñada';
                  final partos = c['partos'] ?? [];
                  final numPartos = partos is List ? partos.length : 0;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.pink,
                        child: Text('🐷', style: TextStyle(fontSize: 24)),
                      ),
                      title: Text(nombre,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: $id', style: const TextStyle(fontSize: 12)),
                          Text('Estado: $estado'),
                          if (numPartos > 0) Text('Partos: $numPartos'),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CerdaScreen(cerdaId: id)),
                        ).then((_) {
                          // Recargar lista cuando regreses de editar una cerda
                          _cargarListaCerdas();
                        });
                      },
                    ),
                  );
                },
              ),
      );
    }

    // Mostrar formulario de edición
    if (_cerda == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cerda no encontrada'),
          backgroundColor: Colors.pink,
        ),
        body: const Center(
          child: Text('No se pudo cargar la información de la cerda'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("${_cerda!['nombre']} 🐷"),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _eliminarCerda,
            tooltip: 'Eliminar cerda',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _guardando ? null : _guardarCerda,
            tooltip: 'Guardar cambios',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ID
              TextFormField(
                initialValue: _cerda!['id'],
                decoration: const InputDecoration(labelText: "ID / Número de cerda"),
                enabled: false,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),

              // Nombre
              TextFormField(
                initialValue: _cerda!['nombre'],
                decoration: const InputDecoration(labelText: "Nombre 🐷"),
                validator: (val) => val == null || val.isEmpty ? 'Ingrese nombre' : null,
                onSaved: (val) => _cerda!['nombre'] = val!.trim(),
              ),
              const SizedBox(height: 12),

              // Estado reproductivo
              Row(
                children: [
                  const Text("Estado: ", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _cerda!['estado'] ?? 'No preñada',
                    items: ['No preñada', 'Preñada', 'Gestante']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _cerda!['estado'] = val!;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // PARTOS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Partos 🐷",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                      onPressed: _agregarParto,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("Agregar"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
                ],
              ),
              const SizedBox(height: 8),
              if ((_cerda!['partos'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "Total partos: ${(_cerda!['partos'] as List).length} | Total lechones: $totalLechones 🐷",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ),
              ...(_cerda!['partos'] as List).asMap().entries.map((entry) {
                final index = entry.key;
                final parto = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Parto #${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: "Fecha parto",
                                  hintText: _mostrarFecha(parto['fecha']),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.calendar_today, color: Colors.blue),
                              onPressed: () => _seleccionarFecha(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _eliminarParto(index),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: parto['num_lechones']?.toString(),
                          decoration: const InputDecoration(
                            labelText: "Número de lechones",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) =>
                              parto['num_lechones'] = int.tryParse(val) ?? 0,
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
                  const Text("Vacunas 💉",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                      onPressed: _agregarVacuna,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("Agregar"),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 212, 86, 191))),
                ],
              ),
              const SizedBox(height: 12),
              ...(_cerda!['vacunas'] as List).asMap().entries.map((entry) {
                final index = entry.key;
                final vacuna = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: vacuna['nombre'],
                                decoration: const InputDecoration(
                                  labelText: "Nombre vacuna",
                                  border: OutlineInputBorder(),
                                ),
                                validator: (val) =>
                                    val == null || val.isEmpty ? 'Ingrese nombre' : null,
                                onChanged: (val) => vacuna['nombre'] = val.trim(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _eliminarVacuna(index),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: vacuna['dosis']?.toString(),
                                decoration: const InputDecoration(
                                  labelText: "Dosis",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) =>
                                    vacuna['dosis'] = int.tryParse(val) ?? 1,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: vacuna['frecuencia_dias']?.toString(),
                                decoration: const InputDecoration(
                                  labelText: "Frecuencia (días)",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) =>
                                    vacuna['frecuencia_dias'] = int.tryParse(val) ?? 30,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : _guardarCerda,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ))
                      : const Icon(Icons.save),
                  label: Text(
                    _guardando ? "Guardando..." : "Guardar cambios",
                    style: const TextStyle(fontSize: 16),
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