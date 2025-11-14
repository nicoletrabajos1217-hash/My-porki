import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:my_porki/backend/services/sync_service.dart';
import 'package:my_porki/backend/services/connectivity_service.dart';

class AgregarCerdaScreen extends StatefulWidget {
  final Map? cerdaExistente;
  final int? hiveKey;
  const AgregarCerdaScreen({super.key, this.cerdaExistente, this.hiveKey});

  @override
  State<AgregarCerdaScreen> createState() => _AgregarCerdaScreenState();
}

class _AgregarCerdaScreenState extends State<AgregarCerdaScreen> {
  final _nombreController = TextEditingController();
  final _idController = TextEditingController();
  String _estado = 'No preñada';
  DateTime? _fechaPrenez;
  List<Map> _vacunas = [];
  bool _guardando = false;
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    if (widget.cerdaExistente != null) _cargarDatos();
  }

  void _cargarDatos() {
    final cerda = widget.cerdaExistente!;
    _nombreController.text = cerda['nombre'] ?? '';
    _idController.text = cerda['identificacion'] ?? '';
    _estado = cerda['estado_reproductivo'] ?? 'No preñada';
    _vacunas = List<Map>.from(cerda['vacunas'] ?? []);
    if (cerda['fecha_prenez_actual'] != null) {
      _fechaPrenez = DateTime.parse(cerda['fecha_prenez_actual']);
    }
  }

  Future<void> _guardarCerda() async {
    if (_guardando) return;
    if (_nombreController.text.isEmpty) {
      _mostrarError("Nombre es obligatorio 🐷");
      return;
    }

    setState(() => _guardando = true);

    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 10),
              Text("Guardando cerda..."),
            ],
          ),
        );
      },
    );

    try {
      final box = await Hive.openBox('porki_data');
      final fechaParto = _fechaPrenez?.add(const Duration(days: 114));
      
      // Datos de la cerda
      final cerdaData = {
        'nombre': _nombreController.text,
        'identificacion': _idController.text,
        'estado_reproductivo': _estado,
        'vacunas': _vacunas,
        'fecha_prenez_actual': _fechaPrenez?.toIso8601String(),
        'fecha_parto_calculado': fechaParto?.toIso8601String(),
        'sowId': widget.cerdaExistente?['sowId'] ?? 'sow_${DateTime.now().millisecondsSinceEpoch}',
        'updatedAt': DateTime.now().toIso8601String(),
        'type': 'sow',
        'synced': false, // Inicialmente no sincronizado
        'createdAt': DateTime.now().toIso8601String(),
      };

      // 1. GUARDAR EN HIVE (LOCAL)
      int? hiveKey;
      if (widget.cerdaExistente != null && widget.hiveKey != null) {
        hiveKey = widget.hiveKey!;
        await box.put(hiveKey, cerdaData);
        print('💾 Cerda actualizada en Hive: ${_nombreController.text}');
      } else {
        hiveKey = await box.add(cerdaData);
        print('💾 Cerda guardada en Hive: ${_nombreController.text}');
      }

      // 2. SINCRONIZACIÓN SEGURA CON FIREBASE
      bool tieneConexion = await ConnectivityService().checkConnection();
      
      if (tieneConexion) {
        bool syncExitoso = await _syncService.syncSowSafe(cerdaData, localKey: hiveKey);
        
        if (syncExitoso) {
          _mostrarExito("✅ Cerda guardada y sincronizada");
        } else {
          _mostrarExito("✅ Cerda guardada (sincronización pendiente)");
        }
      } else {
        // Guardar como pendiente para cuando haya conexión
        await _syncService.syncSowSafe(cerdaData, localKey: hiveKey);
        _mostrarExito("✅ Cerda guardada (sin conexión, se sincronizará después)");
      }

      // Cerrar loading y regresar
      Navigator.of(context).pop(); // Cerrar loading
      Navigator.pop(context, true); // Regresar a pantalla anterior

    } catch (e) {
      Navigator.of(context).pop(); // Cerrar loading
      _mostrarError("❌ Error al guardar: $e");
    } finally {
      setState(() => _guardando = false);
    }
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ... (tus métodos _agregarVacuna, build, _solicitarFechaPrenez se mantienen IGUAL)
  void _agregarVacuna() {
    final nombreCtrl = TextEditingController();
    final dosisCtrl = TextEditingController(text: '1');
    final intervaloCtrl = TextEditingController(text: '0');
    DateTime? fechaPrimera;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Agregar Vacuna 💉"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: "Nombre")),
            TextField(controller: dosisCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Dosis")),
            TextField(controller: intervaloCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Intervalo días")),
            ElevatedButton(
              onPressed: () async {
                final fecha = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (fecha != null) fechaPrimera = fecha;
              },
              child: Text(fechaPrimera != null ? "Fecha: ${fechaPrimera!.toString().split(' ')[0]}" : "Seleccionar fecha"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
            onPressed: () {
              if (nombreCtrl.text.isEmpty || fechaPrimera == null) return;
              
              final dosisTotal = int.tryParse(dosisCtrl.text) ?? 1;
              final intervalo = int.tryParse(intervaloCtrl.text) ?? 0;
              final dosisProgramadas = List.generate(dosisTotal, (i) => {
                'numero_dosis': i + 1,
                'fecha_programada': fechaPrimera!.add(Duration(days: i * intervalo)).toIso8601String(),
                'aplicada': false,
              });

              setState(() => _vacunas.add({
                'nombre': nombreCtrl.text,
                'dosis_total': dosisTotal,
                'dosis_programadas': dosisProgramadas,
              }));
              
              Navigator.pop(context);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cerdaExistente != null ? "Editar Cerda 🐷" : "Nueva Cerda 🐖"),
        backgroundColor: Colors.pink,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Campos básicos
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nombreController, 
                      decoration: const InputDecoration(labelText: "Nombre 🐷")
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _idController, 
                      decoration: const InputDecoration(labelText: "Identificación")
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // Estado reproductivo
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownButtonFormField(
                      value: _estado,
                      items: ['No preñada', 'Preñada'].map((e) => 
                        DropdownMenuItem(value: e, child: Text(e))
                      ).toList(),
                      onChanged: (value) => setState(() {
                        _estado = value!;
                        if (_estado == 'Preñada' && _fechaPrenez == null) {
                          _solicitarFechaPrenez();
                        }
                      }),
                      decoration: const InputDecoration(labelText: "Estado reproductivo"),
                    ),
                    
                    // Mostrar fecha de preñez si está preñada
                    if (_estado == 'Preñada' && _fechaPrenez != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.pink[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: Colors.pink),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Preñez: ${_fechaPrenez!.toString().split(' ')[0]}"),
                                  Text("Parto estimado: ${_fechaPrenez!.add(const Duration(days: 114)).toString().split(' ')[0]}"),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Vacunas
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text("Vacunas 💉", style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _agregarVacuna, 
                          child: const Text("Agregar"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    if (_vacunas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text("No hay vacunas registradas", style: TextStyle(color: Colors.grey)),
                      ),
                    
                    ..._vacunas.map((v) => ListTile(
                      leading: Icon(Icons.vaccines, color: Colors.green),
                      title: Text(v['nombre']),
                      subtitle: Text("${v['dosis_total'] ?? 1} dosis"),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => _vacunas.remove(v)),
                      ),
                    )),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Botón guardar
            ElevatedButton(
              onPressed: _guardando ? null : _guardarCerda,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _guardando 
                  ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                  : const Text("Guardar Cerda", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _solicitarFechaPrenez() async {
    final fecha = await showDatePicker(
      context: context, 
      initialDate: DateTime.now(), 
      firstDate: DateTime(2020), 
      lastDate: DateTime(2100)
    );
    if (fecha != null) setState(() => _fechaPrenez = fecha);
  }
}