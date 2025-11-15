import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_porki/backend/services/notification_service.dart';
import 'package:my_porki/backend/services/sync_service.dart';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart';
import 'package:my_porki/frotend/screens/cerda_detail_screen.dart';
import 'package:my_porki/frotend/screens/historial_screen.dart';
import 'package:my_porki/frotend/screens/login_screen.dart';
import 'package:my_porki/frotend/screens/notificaciones_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const HomeScreen({super.key, required this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  bool _sincronizando = false;

  // ✅ CORREGIDO: Variables para sincronización
  late final SyncService _syncService;
  Timer? _syncTimer;
  StreamSubscription<dynamic>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _firebaseSubscription;

  // Variables para notificaciones
  List<Map<String, dynamic>> _notificaciones = [];
  int _cantidadNotificaciones = 0;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _iniciarFirebaseListener();
    _cargarDatos();
    // Ejecutar una sincronización inicial automática
    _sincronizarEnBackground();
    _iniciarSincronizacionAutomatica();
    print('🏠 HomeScreen initState called');
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _firebaseSubscription?.cancel();
    super.dispose();
  }

  // ✅ CORREGIDO: Listener de Firebase mejorado
  void _iniciarFirebaseListener() {
    try {
      final firestore = FirebaseFirestore.instance;
      print('🌐 === INICIANDO FIREBASE LISTENER ===');

      _firebaseSubscription = firestore
          .collection('sows') // ✅ CORREGIDO: Usar 'sows' en lugar de 'cerdas'
          .snapshots()
          .listen(
            (snapshot) async {
              try {
                print(
                  '📥 ✅ SNAPSHOT RECIBIDO: ${snapshot.docs.length} documentos',
                );

                final box = await Hive.openBox('porki_data');
                print('🗃️ Caja Hive abierta: ${box.values.length} items');

                // Procesar documentos añadidos/actualizados
                for (var doc in snapshot.docs) {
                  try {
                    final data = doc.data();
                    final sowId = doc.id;

                    // ✅ CORREGIDO: Estructura de datos consistente
                    final sowData = {
                      ...data,
                      'id': sowId, // ✅ Usar 'id' en lugar de 'sowId'
                      'type': 'sow',
                      'synced': true,
                      'lastSync': DateTime.now().toIso8601String(),
                    };

                    // Buscar por id en la caja local
                    bool encontrado = false;
                    for (var key in box.keys) {
                      final item = box.get(key);
                      if (item is Map && item['id'] == sowId) {
                        // ✅ CORREGIDO: Conversión segura sin cast directo
                        final Map<dynamic, dynamic> itemLocal = item;
                        final Map<String, dynamic> convertedItem = {};

                        // Convertir cada clave a String
                        itemLocal.forEach((key, value) {
                          convertedItem[key.toString()] = value;
                        });

                        sowData['historial'] = convertedItem['historial'] ?? [];
                        sowData['vacunas'] = convertedItem['vacunas'] ?? [];

                        await box.put(key, sowData);
                        encontrado = true;
                        print('    🔄 Cerda ACTUALIZADA en Hive: $sowId');
                        break;
                      }
                    }

                    if (!encontrado) {
                      await box.put(sowId, sowData); // ✅ Usar sowId como key
                      print('    ✨ Nueva cerda AGREGADA a Hive: $sowId');
                    }
                  } catch (e) {
                    print('    ❌ Error procesando documento: $e');
                  }
                }

                // ✅ CORREGIDO: Procesar eliminaciones
                final remoteIds = snapshot.docs.map((d) => d.id).toSet();
                for (var key in box.keys.toList()) {
                  final item = box.get(key);
                  if (item is Map && item['type'] == 'sow') {
                    final localSowId = item['id'];
                    if (localSowId != null && !remoteIds.contains(localSowId)) {
                      await box.delete(key);
                      print('  🗑️ Cerda ELIMINADA de Hive: $localSowId');
                    }
                  }
                }

                print('✅ === SNAPSHOT PROCESADO CORRECTAMENTE ===');

                // ✅ ACTUALIZAR UI después de cambios
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              } catch (e) {
                print('❌ Error procesando snapshot: $e');
              }
            },
            onError: (e) {
              print('❌ ERROR EN FIREBASE LISTENER: $e');
            },
          );
      print('✅ === FIREBASE LISTENER INICIADO ===');
    } catch (e) {
      print('❌ FALLO AL INICIAR FIREBASE LISTENER: $e');
    }
  }

  // ✅ CORREGIDO: Sincronización automática
  void _iniciarSincronizacionAutomatica() {
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (!_sincronizando) {
        print('🔄 Sincronización automática...');
        await _sincronizarEnBackground();
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      final tieneConexion = result != ConnectivityResult.none;
      if (tieneConexion && !_sincronizando) {
        print('🌐 Conexión restaurada - Sincronizando...');
        await _sincronizarEnBackground();
      }
    });
  }

  // ✅ CORREGIDO: Sincronización en background
  Future<void> _sincronizarEnBackground() async {
    try {
      if (mounted) {
        setState(() {
          _sincronizando = true;
        });
      }

      bool tieneConexion = await _syncService.checkConnection();
      if (tieneConexion) {
        print('🔄 Sincronización automática en progreso...');
        await _syncService.syncAllPending();

        // Recargar datos locales
        await _cargarDatos();
      }
    } catch (e) {
      print('❌ Error en sincronización automática: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sincronizando = false;
        });
      }
    }
  }

  // ✅ CORREGIDO: Cargar datos
  Future<void> _cargarDatos() async {
    try {
      print('🔄 Iniciando carga de datos...');

      // ✅ USAR SOW SERVICE para obtener datos
      final cerdas = await SowService.obtenerCerdas();
      print('🐷 Cerdas encontradas: ${cerdas.length}');

      // Obtener notificaciones
      final partosProximos = await NotificationService.getPartosProximos();

      if (mounted) {
        setState(() {
          _notificaciones = partosProximos;
          _cantidadNotificaciones = partosProximos.length;
          _isLoading = false;
        });
      }

      print(
        '✅ Datos cargados: ${cerdas.length} cerdas, ${partosProximos.length} notificaciones',
      );
    } catch (e) {
      print('❌ Error cargando datos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ CORREGIDO: Sincronización manual
  Future<void> _sincronizarManual() async {
    if (mounted) {
      setState(() {
        _sincronizando = true;
      });
    }

    try {
      print('🔄 Iniciando sincronización manual...');

      bool tieneConexion = await _syncService.checkConnection();
      if (tieneConexion) {
        await _syncService.syncAllPending();
        await _cargarDatos();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Sincronización completada"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📴 Sin conexión - Sincronización pendiente"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ Error en sincronización manual: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error en sincronización: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sincronizando = false;
        });
      }
    }
  }

  // ✅ CORREGIDO: Ver estado de sincronización
  Future<void> verEstadoSync() async {
    try {
      final syncStatus = await _syncService.getSyncStatus();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estado de Sincronización'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✅ Cerdas sincronizadas: ${syncStatus['syncedCerdas']}/${syncStatus['totalCerdas']}',
              ),
              Text('📋 Pendientes: ${syncStatus['pendingSync']}'),
              Text('📊 Porcentaje: ${syncStatus['syncPercentage']}%'),
              const SizedBox(height: 16),
              if (syncStatus['pendingSync'] > 0)
                const Text(
                  'ℹ️ Los datos pendientes se sincronizarán automáticamente',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            if (syncStatus['pendingSync'] > 0)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _sincronizarManual();
                },
                child: const Text('Sincronizar Ahora'),
              ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error obteniendo estado sync: $e');
    }
  }

  // Método para formatear números grandes
  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }

  @override
  Widget build(BuildContext context) {
    print('🏠 HomeScreen build called');
    final username = widget.userData['username'] ?? 'Usuario';
    final role = widget.userData['role'] ?? 'colaborador';

    return Scaffold(
      appBar: AppBar(
        title: Text('My Porki - $username'),
        backgroundColor: Colors.pink,
        actions: [
          ValueListenableBuilder<Box>(
            valueListenable: Hive.box('porki_data').listenable(),
            builder: (context, boxNotif, _) {
              // ✅ SOLUCIÓN DEFINITIVA - Versión simplificada
              int notCount = 0;
              final ahora = DateTime.now();

              for (var data in boxNotif.values) {
                if (data is Map && data['type'] == 'sow') {
                  // ✅ CORRECCIÓN: Conversión segura sin cast directo
                  final Map<dynamic, dynamic> dynamicMap = data;
                  final fechaParto = dynamicMap['fecha_parto_calculado'];

                  if (fechaParto != null) {
                    try {
                      final fecha = DateTime.parse(fechaParto.toString());
                      final diff = fecha.difference(ahora).inDays;
                      if (diff <= 7 && diff >= 0) notCount++;
                    } catch (e) {
                      print('Error parseando fecha: $e');
                    }
                  }
                }
              }

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificacionesScreen(),
                        ),
                      );
                    },
                  ),
                  if (notCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          notCount > 9 ? '9+' : notCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, username, role),
      body: _isLoading ? _buildLoadingScreen() : _buildBody(context),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.pink),
          SizedBox(height: 16),
          Text('Cargando datos...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, String username, String role) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.pink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/images/LogoAlex.png',
                  width: 70,
                  height: 70,
                ),
                const SizedBox(height: 10),
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  role.toUpperCase(),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (_sincronizando)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Sincronizando...',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.pink),
            title: const Text('Inicio'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.pets, color: Colors.pink),
            title: const Text('Mis Cerdas'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CerdasScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.pink),
            title: const Text('Historial'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HistorialScreen(),
                ),
              );
            },
          ),
          // ✅ CORREGIDO DEFINITIVO: Versión simplificada sin conversión de Map
          ValueListenableBuilder<Box>(
            valueListenable: Hive.box('porki_data').listenable(),
            builder: (context, boxNotif, _) {
              // ✅ SOLUCIÓN DEFINITIVA - Versión simplificada
              int notCount = 0;
              final ahora = DateTime.now();

              for (var data in boxNotif.values) {
                if (data is Map && data['type'] == 'sow') {
                  // ✅ CORRECCIÓN: Conversión segura sin cast directo
                  final Map<dynamic, dynamic> dynamicMap = data;
                  final fechaParto = dynamicMap['fecha_parto_calculado'];

                  if (fechaParto != null) {
                    try {
                      final fecha = DateTime.parse(fechaParto.toString());
                      final diff = fecha.difference(ahora).inDays;
                      if (diff <= 7 && diff >= 0) notCount++;
                    } catch (e) {
                      print('Error parseando fecha: $e');
                    }
                  }
                }
              }

              return ListTile(
                leading: const Icon(Icons.notifications, color: Colors.pink),
                title: const Text('Recordatorios'),
                trailing: notCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          notCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificacionesScreen(),
                    ),
                  );
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: const Text('Configuración'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Configuración - Próximamente")),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.grey),
            title: const Text('Ayuda'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Ayuda - Próximamente")),
              );
            },
          ),
          // ✅ CORREGIDO: Botón de Cerrar Sesión en color rosa
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.pink),
            title: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.pink),
            ),
            onTap: () {
              _mostrarDialogoCerrarSesion(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjeta de bienvenida
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¡Bienvenido a My Porki! 🐷',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gestiona tus cerdas, partos y preñeces de forma fácil y organizada.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Actualizado: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      if (_sincronizando)
                        const Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Sincronizando...',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Panel de notificaciones
          if (_cantidadNotificaciones > 0) ...[
            _buildPanelNotificaciones(),
            const SizedBox(height: 16),
          ],

          // Acciones rápidas
          const Text(
            'Acciones Rápidas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildActionCard(
                context,
                'Agregar Cerda',
                Icons.add_circle,
                Colors.green,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AgregarCerdaScreen(),
                    ),
                  );
                },
              ),
              _buildActionCard(
                context,
                'Ver Cerdas',
                Icons.pets,
                Colors.blue,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => CerdasScreen()),
                  );
                },
              ),
              _buildActionCard(
                context,
                'Historial',
                Icons.history,
                Colors.orange,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HistorialScreen(),
                    ),
                  );
                },
              ),
              _buildActionCard(
                context,
                'Recordatorios',
                Icons.notifications,
                Colors.purple,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificacionesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Información rápida (Resumen General)
          FutureBuilder(
            future: Hive.openBox('porki_data'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.pink),
                );
              }

              final box = snapshot.data as Box;

              return ValueListenableBuilder<Box>(
                valueListenable: box.listenable(),
                builder: (context, Box listenedBox, _) {
                  // ✅ CORREGIDO DEFINITIVO: Conversión segura para el resumen
                  final cerdas = <Map<String, dynamic>>[];

                  for (var data in listenedBox.values) {
                    if (data is Map && data['type'] == 'sow') {
                      try {
                        final Map<dynamic, dynamic> dynamicMap = data;
                        final stringMap = <String, dynamic>{};

                        // ✅ CORRECCIÓN: Conversión segura clave por clave
                        dynamicMap.forEach((key, value) {
                          stringMap[key.toString()] = value;
                        });

                        cerdas.add(stringMap);
                      } catch (e) {
                        print('⚠️ Error convirtiendo mapa en resumen: $e');
                      }
                    }
                  }

                  int prenadas = cerdas
                      .where((cerda) => cerda['estado'] == 'preñada')
                      .length;

                  int totalLechones = 0;
                  int partosHoy = 0;
                  int partosPendientes = 0;
                  int vacunasHoy = 0;

                  final ahora = DateTime.now();

                  for (var cerda in cerdas) {
                    totalLechones += (cerda['lechones_nacidos'] as int? ?? 0);

                    // Contar partos de hoy
                    final fechaParto = cerda['fecha_parto_calculado'];
                    if (fechaParto != null) {
                      try {
                        final fecha = DateTime.parse(fechaParto.toString());
                        if (fecha.year == ahora.year &&
                            fecha.month == ahora.month &&
                            fecha.day == ahora.day) {
                          partosHoy++;
                        } else if (fecha.isAfter(ahora)) {
                          partosPendientes++;
                        }
                      } catch (e) {
                        print('Error parseando fecha parto: $e');
                      }
                    }

                    // Contar vacunas de hoy
                    final vacunas = cerda['vacunas'] ?? [];
                    if (vacunas is List) {
                      for (var vacuna in vacunas) {
                        if (vacuna is Map && vacuna['fecha'] != null) {
                          try {
                            final fechaVacuna = DateTime.parse(
                              vacuna['fecha'].toString(),
                            );
                            if (fechaVacuna.year == ahora.year &&
                                fechaVacuna.month == ahora.month &&
                                fechaVacuna.day == ahora.day) {
                              vacunasHoy++;
                            }
                          } catch (e) {
                            print('Error parseando fecha vacuna: $e');
                          }
                        }
                      }
                    }
                  }

                  return Column(
                    children: [
                      Card(
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.analytics,
                                    color: Colors.pink,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Resumen General 🐷',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.cloud_done,
                                          color: Colors.green,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'En tiempo real',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildInfoItem(
                                    'Total Cerdas',
                                    _formatNumber(cerdas.length),
                                    '🐖',
                                    cerdas.length,
                                  ),
                                  _buildInfoItem(
                                    'Preñadas',
                                    _formatNumber(prenadas),
                                    '🐷',
                                    prenadas,
                                  ),
                                  _buildInfoItem(
                                    'Lechones',
                                    _formatNumber(totalLechones),
                                    '🐽',
                                    totalLechones,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildInfoItem(
                                    'Partos Hoy',
                                    partosHoy.toString(),
                                    '📅',
                                    partosHoy,
                                  ),
                                  _buildInfoItem(
                                    'Partos Pendientes',
                                    partosPendientes.toString(),
                                    '⏰',
                                    partosPendientes,
                                  ),
                                  _buildInfoItem(
                                    'Vacunas Hoy',
                                    vacunasHoy.toString(),
                                    '💉',
                                    vacunasHoy,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (partosHoy > 0) ...[
                        const SizedBox(height: 8),
                        Card(
                          color: Colors.blue[50],
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.child_care,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '¡$partosHoy parto${partosHoy == 1 ? '' : 's'} hoy! 🎊',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPanelNotificaciones() {
    return Card(
      elevation: 4,
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Recordatorios',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_cantidadNotificaciones',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._notificaciones
                .take(3)
                .map((notif) => _buildItemNotificacion(notif)),
            if (_notificaciones.length > 3) ...[
              const SizedBox(height: 8),
              Text(
                '... y ${_notificaciones.length - 3} más',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificacionesScreen(),
                    ),
                  );
                },
                child: const Text('Ver todas las notificaciones'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemNotificacion(Map<String, dynamic> notificacion) {
    final prioridad = notificacion['prioridad'] ?? 'media';
    final color = prioridad == 'alta' ? Colors.red : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.pregnant_woman, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notificacion['mensaje'] ?? 'Parto próximo',
                  style: TextStyle(fontWeight: FontWeight.w500, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cerda: ${notificacion['cerda']?['nombre'] ?? 'Sin nombre'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (prioridad == 'alta')
            const Icon(Icons.warning, color: Colors.red, size: 16),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (title == 'Ver Cerdas')
              _buildCerditoFace() // ✅ NUEVO: Cara de cerdito personalizada
            else
              Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ NUEVO: Widget para dibujar la cara del cerdito
  Widget _buildCerditoFace() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.pink[100],
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.pink, width: 2),
      ),
      child: Stack(
        children: [
          // Orejas
          Positioned(
            top: 5,
            left: 5,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.pink[300],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomRight: Radius.circular(5),
                ),
              ),
            ),
          ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.pink[300],
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomLeft: Radius.circular(5),
                ),
              ),
            ),
          ),
          // Ojos
          Positioned(
            top: 20,
            left: 15,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 15,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // Nariz (hocico)
          Positioned(
            bottom: 15,
            left: 20,
            right: 20,
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                color: Colors.pink[300],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String value, String emoji, int numero) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: numero > 0 ? Colors.pink : Colors.grey,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: numero > 0 ? Colors.black87 : Colors.grey,
          ),
        ),
      ],
    );
  }

  void _mostrarDialogoCerrarSesion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          // ✅ CORREGIDO: Botón de Cerrar Sesión en color rosa
          TextButton(
            onPressed: () {
              _syncTimer?.cancel();
              _connectivitySubscription?.cancel();
              _firebaseSubscription?.cancel();

              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) => false,
              );
            },
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.pink),
            ),
          ),
        ],
      ),
    );
  }
}

// Clase CerdasScreen faltante (añadida para completar el código)
class CerdasScreen extends StatelessWidget {
  const CerdasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cerdas'),
        backgroundColor: Colors.pink,
      ),
      body: const Center(child: Text('Pantalla de Cerdas - En desarrollo')),
    );
  }
}
