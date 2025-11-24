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
  List<bool> _prenezExpandida = []; // Para controlar qué preñez está expandida

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
          SnackBar(
            content: Text("Error cargando cerda: $e"),
            backgroundColor: Colors.red,
          ),
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
        final doc = await _firestore
            .collection('sows')
            .doc(widget.cerdaId)
            .get();
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
          _cerda!['vacunas'] =
              localCerda['vacunas'] ?? _cerda!['vacunas'] ?? [];
          _cerda!['historial'] =
              localCerda['historial'] ?? _cerda!['historial'] ?? [];
        } else {
          _cerda!['partos'] ??= [];
          _cerda!['vacunas'] ??= [];
          _cerda!['historial'] ??= [];
        }

        // VERIFICAR SI HAY PREÑEZ INICIAL Y AGREGARLA SI NO EXISTE
        _verificarYAgregarPrenezInicial();

        // INICIALIZAR ESTADO DE EXPANSIÓN - TODAS EXPANDIDAS POR DEFECTO
        _prenezExpandida = List.generate(
          _cerda!['partos'].length,
          (index) => true,
        );

        print('✅ Cerda cargada: ${_cerda!['nombre']}');
      } else {
        print('❌ Cerda no encontrada');
      }
    } catch (e) {
      print('❌ Error en _cargarCerdaIndividual: $e');
    }
  }

  // NUEVA FUNCIÓN: Verificar y agregar preñez inicial si existe fecha_prenez
  void _verificarYAgregarPrenezInicial() {
    if (_cerda == null) return;

    final fechaPrenez = _cerda!['fecha_prenez'];
    final partos = _cerda!['partos'] as List<dynamic>;

    // Si hay fecha de preñez pero no hay preñeces registradas, crear la preñez inicial
    if (fechaPrenez != null && partos.isEmpty) {
      final fechaPrenezDate = DateTime.tryParse(fechaPrenez);
      if (fechaPrenezDate != null) {
        final fechaPartoCalculado = fechaPrenezDate.add(
          const Duration(days: 114),
        );

        setState(() {
          _cerda!['partos'].add({
            "fecha_prenez": fechaPrenez,
            "fecha_parto": null,
            "fecha_parto_calculado": fechaPartoCalculado.toIso8601String(),
            "num_lechones": 0,
            "estado": "Preñada",
            "observaciones": "Preñez inicial",
            "es_preñez_inicial": true,
          });
          // Agregar estado de expansión para la nueva preñez (expandida por defecto)
          _prenezExpandida.add(true);
        });

        print('✅ Preñez inicial agregada automáticamente');
      }
    }
  }

  // NUEVA FUNCIÓN: Calcular días restantes para el parto
  String _calcularProximidadParto(String? fechaPartoCalculado) {
    if (fechaPartoCalculado == null) return 'Sin fecha';

    try {
      final fechaParto = DateTime.parse(fechaPartoCalculado);
      final ahora = DateTime.now();
      final diferencia = fechaParto.difference(ahora).inDays;

      if (diferencia < 0) {
        return 'Parto pasado (${diferencia.abs()} días)';
      } else if (diferencia == 0) {
        return '¡Parto hoy!';
      } else if (diferencia <= 7) {
        return '¡En $diferencia días!';
      } else {
        return 'En $diferencia días';
      }
    } catch (e) {
      return 'Error en fecha';
    }
  }

  // NUEVA FUNCIÓN: Obtener color según proximidad del parto
  Color _obtenerColorProximidad(String? fechaPartoCalculado) {
    if (fechaPartoCalculado == null) return Colors.grey;

    try {
      final fechaParto = DateTime.parse(fechaPartoCalculado);
      final ahora = DateTime.now();
      final diferencia = fechaParto.difference(ahora).inDays;

      if (diferencia < 0) {
        return Colors.orange;
      } else if (diferencia == 0) {
        return Colors.red;
      } else if (diferencia <= 7) {
        return Colors.orange;
      } else {
        return Colors.green;
      }
    } catch (e) {
      return Colors.grey;
    }
  }

  int get totalLechones {
    final partos = (_cerda?['partos'] as List<dynamic>?) ?? [];
    int total = 0;

    for (var parto in partos) {
      final numLechones = parto['num_lechones'];
      total += (numLechones is int
          ? numLechones
          : int.tryParse('$numLechones') ?? 0);
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
        await _firestore
            .collection('sows')
            .doc(id)
            .set(_cerda!, SetOptions(merge: true));

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
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error al guardar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar: $e"),
            backgroundColor: Colors.red,
          ),
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
        content: Text(
          '¿Deseas eliminar a "${_cerda!['nombre']}"?\n\nEsta acción no se puede deshacer.',
        ),
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

  // CAMBIO: Ahora es "Agregar Preñez" en lugar de "Agregar Parto"
  void _agregarPrenez() {
    setState(() {
      (_cerda!['partos'] as List).add({
        "fecha_prenez": null, // Fecha de preñez
        "fecha_parto": null, // Fecha real del parto (se llena después)
        "fecha_parto_calculado": null, // Fecha calculada (prenez + 114 días)
        "num_lechones": 0, // Número de lechones
        "estado": "Preñada", // Estado de esta preñez
        "observaciones": "", // Observaciones adicionales
      });
      // Agregar estado de expansión para la nueva preñez (expandida por defecto)
      _prenezExpandida.add(true);
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

  void _eliminarPrenez(int index) {
    setState(() {
      (_cerda!['partos'] as List).removeAt(index);
      _prenezExpandida.removeAt(index);
    });
  }

  void _eliminarVacuna(int index) {
    setState(() {
      (_cerda!['vacunas'] as List).removeAt(index);
    });
  }

  String _mostrarFecha(String? fecha) {
    if (fecha == null) return 'No especificada';
    try {
      return _fechaFormat.format(DateTime.parse(fecha));
    } catch (_) {
      return fecha;
    }
  }

  // CAMBIO: Nueva función para seleccionar fecha de preñez
  Future<void> _seleccionarFechaPrenez(int index) async {
    final current = (_cerda!['partos'] as List)[index]['fecha_prenez'] != null
        ? DateTime.tryParse((_cerda!['partos'] as List)[index]['fecha_prenez'])
        : DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha != null) {
      setState(() {
        (_cerda!['partos'] as List)[index]['fecha_prenez'] = fecha
            .toIso8601String();
        // Calcular fecha de parto (prenez + 114 días)
        final fechaPartoCalculado = fecha.add(const Duration(days: 114));
        (_cerda!['partos'] as List)[index]['fecha_parto_calculado'] =
            fechaPartoCalculado.toIso8601String();
      });
    }
  }

  // CAMBIO: Nueva función para seleccionar fecha real de parto
  Future<void> _seleccionarFechaParto(int index) async {
    final current = (_cerda!['partos'] as List)[index]['fecha_parto'] != null
        ? DateTime.tryParse((_cerda!['partos'] as List)[index]['fecha_parto'])
        : DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (fecha != null) {
      setState(() {
        (_cerda!['partos'] as List)[index]['fecha_parto'] = fecha
            .toIso8601String();
      });
    }
  }

  // NUEVA FUNCIÓN: Alternar expansión de preñez
  void _alternarExpansionPrenez(int index) {
    setState(() {
      _prenezExpandida[index] = !_prenezExpandida[index];
    });
  }

  // NUEVA FUNCIÓN: Mostrar información como texto simple
  Widget _buildInfoItem(String titulo, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          valor.isEmpty ? "No especificado" : valor,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Cargando...'),
          backgroundColor: Colors.pink,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.pink),
        ),
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
                    const Text(
                      'No hay cerdas disponibles',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Agrega cerdas desde el menú principal',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        setState(() => _cargando = true);
                        await _cargarListaCerdas();
                        setState(() => _cargando = false);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recargar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                      ),
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
                      title: Text(
                        nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: $id', style: const TextStyle(fontSize: 12)),
                          Text('Estado: $estado'),
                          if (numPartos > 0) Text('Preñeces: $numPartos'),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CerdaScreen(cerdaId: id),
                          ),
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
                decoration: const InputDecoration(
                  labelText: "ID / Número de cerda",
                ),
                enabled: false,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),

              // Nombre
              TextFormField(
                initialValue: _cerda!['nombre'],
                decoration: const InputDecoration(labelText: "Nombre 🐷"),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Ingrese nombre' : null,
                onSaved: (val) => _cerda!['nombre'] = val!.trim(),
              ),
              const SizedBox(height: 12),

              // Estado reproductivo - CORREGIDO
              Row(
                children: [
                  const Text(
                    "Estado: ",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _cerda!['estado'] ?? 'No preñada',
                    items: ['No preñada', 'Preñada', 'Gestante']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) async {
                      setState(() {
                        _cerda!['estado'] = val!;
                      });

                      // GUARDAR AUTOMÁTICAMENTE cuando cambia el estado
                      print(
                        '🔄 Estado cambiado a: $val - Guardando automáticamente...',
                      );
                      await _guardarCerda();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // CAMBIO: Ahora es "PREÑEZES" en lugar de "PARTOS" - CON NUEVO EMOJI Y COLOR
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Preñeces 🐽",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _agregarPrenez,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Agregar Preñez"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 212, 86, 191),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if ((_cerda!['partos'] as List).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    "Total preñeces: ${(_cerda!['partos'] as List).length} | Total lechones: $totalLechones 🐷",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ...(_cerda!['partos'] as List).asMap().entries.map((entry) {
                final index = entry.key;
                final prenez = entry.value;
                final fechaPartoCalculado = prenez['fecha_parto_calculado'];
                final proximidadParto = _calcularProximidadParto(
                  fechaPartoCalculado,
                );
                final colorProximidad = _obtenerColorProximidad(
                  fechaPartoCalculado,
                );
                final estaExpandida = _prenezExpandida[index];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 3,
                  child: Column(
                    children: [
                      // CABECERA DESPLEGABLE
                      ListTile(
                        leading: Icon(
                          estaExpandida ? Icons.expand_less : Icons.expand_more,
                          color: const Color.fromARGB(255, 212, 86, 191),
                        ),
                        title: Row(
                          children: [
                            Text(
                              'Prenez #${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (prenez['es_prenez_inicial'] == true)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: const Text(
                                  'Inicial',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          'Fecha prenez: ${_mostrarFecha(prenez['fecha_prenez'])}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorProximidad.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorProximidad),
                              ),
                              child: Text(
                                proximidadParto,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorProximidad,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _eliminarPrenez(index),
                            ),
                          ],
                        ),
                        onTap: () => _alternarExpansionPrenez(index),
                      ),

                      // CONTENIDO DESPLEGABLE - SIEMPRE VISIBLE CUANDO EXPANDIDO
                      if (estaExpandida)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // INFORMACIÓN VISIBLE DIRECTAMENTE
                              _buildInfoItem(
                                "Fecha de prenez",
                                _mostrarFecha(prenez['fecha_prenez']),
                              ),
                              const SizedBox(height: 16),

                              if (fechaPartoCalculado != null)
                                Column(
                                  children: [
                                    _buildInfoItem(
                                      "Fecha parto calculada",
                                      _mostrarFecha(fechaPartoCalculado),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),

                              _buildInfoItem(
                                "Fecha real de parto",
                                _mostrarFecha(prenez['fecha_parto']),
                              ),
                              const SizedBox(height: 16),

                              _buildInfoItem(
                                "Número de lechones",
                                "${prenez['num_lechones'] ?? 0} lechones",
                              ),
                              const SizedBox(height: 16),

                              if (prenez['observaciones'] != null &&
                                  prenez['observaciones'].isNotEmpty)
                                Column(
                                  children: [
                                    _buildInfoItem(
                                      "Observaciones",
                                      prenez['observaciones'],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),

                              // BOTONES PARA EDITAR
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _seleccionarFechaPrenez(index),
                                      icon: const Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                      ),
                                      label: const Text("Editar fecha prenez"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                          255,
                                          212,
                                          86,
                                          191,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _seleccionarFechaParto(index),
                                      icon: const Icon(
                                        Icons.calendar_today,
                                        size: 16,
                                      ),
                                      label: const Text("Editar fecha parto"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color.fromARGB(
                                          255,
                                          86,
                                          156,
                                          212,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // CAMPO PARA EDITAR NÚMERO DE LECHONES
                              TextFormField(
                                initialValue: prenez['num_lechones']
                                    ?.toString(),
                                decoration: const InputDecoration(
                                  labelText: "Número de lechones nacidos",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) => prenez['num_lechones'] =
                                    int.tryParse(val) ?? 0,
                              ),
                              const SizedBox(height: 16),

                              // CAMPO PARA OBSERVACIONES
                              TextFormField(
                                initialValue: prenez['observaciones'],
                                decoration: const InputDecoration(
                                  labelText: "Observaciones",
                                  border: OutlineInputBorder(),
                                ),
                                maxLines: 2,
                                onChanged: (val) =>
                                    prenez['observaciones'] = val,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 20),

              // VACUNAS (sin cambios)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Vacunas 💉",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _agregarVacuna,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Agregar"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(255, 212, 86, 191),
                    ),
                  ),
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
                                validator: (val) => val == null || val.isEmpty
                                    ? 'Ingrese nombre'
                                    : null,
                                onChanged: (val) =>
                                    vacuna['nombre'] = val.trim(),
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
                                initialValue: vacuna['frecuencia_dias']
                                    ?.toString(),
                                decoration: const InputDecoration(
                                  labelText: "Frecuencia (días)",
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (val) => vacuna['frecuencia_dias'] =
                                    int.tryParse(val) ?? 30,
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
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
