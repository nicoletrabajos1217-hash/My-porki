import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_porki/backend/services/notification_service.dart';
import 'package:my_porki/backend/services/sync_service.dart';
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
  // Variables para almacenar los datos
  // ✅ COMENTADO: Estas variables se calculan en tiempo real desde Hive
  // int _totalCerdas = 0;
  // int _cerdasPrenadas = 0;
  // int _totalLechones = 0;
  // int _totalVacunas = 0;
  // Ya no usamos _partosHoy como estado global (se calcula en tiempo real desde Hive)
  bool _isLoading = true;
  bool _sincronizando = false;
  
  // ✅ NUEVO: Variables para sincronización automática
  late final SyncService _syncService;
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?_firebaseSubscription;

  // Variables para notificaciones
  List<Map<String, dynamic>> _notificaciones = [];
  int _cantidadNotificaciones = 0;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _iniciarFirebaseListener(); // ✅ PRIMERO: Iniciar listener de Firestore
    _cargarDatos();
    _iniciarSincronizacionAutomatica(); // ✅ NUEVO: Sincronización automática
    print('🏠 HomeScreen initState called');
  }

  @override
  void dispose() {
    // ✅ NUEVO: Limpiar timers y subscriptions
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _firebaseSubscription?.cancel();
    super.dispose();
  }

  // Escuchar cambios en Firebase y aplicarlos a Hive en tiempo real (MEJORADO)
  void _iniciarFirebaseListener() {
    try {
      final firestore = FirebaseFirestore.instance;
      print('🌐 === INICIANDO FIREBASE LISTENER ===');
      print('🎯 Escuchando colección "cerdas"...');
      
      _firebaseSubscription = firestore
          .collection('cerdas')
          .snapshots()
          .listen(
            (snapshot) async {
              try {
                print('📥 ✅ SNAPSHOT RECIBIDO de Firebase: ${snapshot.docs.length} documentos');
                
                // Abrir la caja local
                final box = await Hive.openBox('porki_data');
                print('🗃️ Caja Hive abierta: ${box.values.length} items antes de actualizar');

                // Procesar documentos añadidos/actualizados
                for (var doc in snapshot.docs) {
                  try {
                    final data = doc.data();
                    final sowId = doc.id;
                    print('  📄 Procesando documento: $sowId - ${data['nombre'] ?? 'sin nombre'}');

                    final sowData = {
                      ...data,
                      'sowId': sowId,
                      'type': 'sow',
                      'synced': true,
                      'lastSync': DateTime.now().toIso8601String(),
                    };

                    // Buscar por sowId en la caja local
                    bool encontrado = false;
                    for (var key in box.keys) {
                      final item = box.get(key);
                      if (item is Map && item['sowId'] == sowId) {
                        // Merge: mantener historial local si existe
                        final itemLocal = Map<String, dynamic>.from(item);
                        sowData['historial'] = itemLocal['historial'] ?? [];
                        
                        await box.put(key, sowData);
                        encontrado = true;
                        print('    🔄 Cerda ACTUALIZADA en Hive (key=$key): $sowId');
                        break;
                      }
                    }

                    if (!encontrado) {
                      await box.add(sowData);
                      print('    ✨ Nueva cerda AGREGADA a Hive: $sowId');
                    }
                  } catch (e) {
                    print('    ❌ Error procesando documento: $e');
                  }
                }

                // Procesar documentos eliminados: eliminar locales que ya no existen remotamente
                final remoteIds = snapshot.docs.map((d) => d.id).toSet();
                for (var key in box.keys.toList()) {
                  final item = box.get(key);
                  if (item is Map && item['type'] == 'sow') {
                    final localSowId = item['sowId'];
                    if (localSowId != null && !remoteIds.contains(localSowId)) {
                      await box.delete(key);
                      print('  🗑️ Cerda ELIMINADA de Hive (ya no en Firebase): $localSowId');
                    }
                  }
                }

                print('✅ === SNAPSHOT PROCESADO CORRECTAMENTE ===');
                print('📊 Hive ahora tiene: ${box.values.length} items');
                // ValueListenableBuilder se actualiza automáticamente gracias a box.listenable()
              } catch (e) {
                print('❌ Error procesando snapshot de Firebase: $e');
              }
            },
            onError: (e) {
              print('❌ ERROR EN FIREBASE LISTENER: $e');
            },
            onDone: () {
              print('⚠️ Firebase listener cerrado/completado');
            },
          );
      print('✅ === FIREBASE LISTENER INICIADO CORRECTAMENTE ===');
    } catch (e) {
      print('❌ FALLO AL INICIAR FIREBASE LISTENER: $e');
    }
  }

  // ✅ NUEVO: Iniciar sincronización automática
  void _iniciarSincronizacionAutomatica() {
    // Sincronizar cada 2 minutos
    _syncTimer = Timer.periodic(Duration(minutes: 2), (timer) async {
      if (!_sincronizando) {
        print('🔄 Sincronización automática desde Home...');
        await _sincronizarEnBackground();
      }
    });

    // Escuchar cambios de conexión
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) async {
      if (results.isNotEmpty && results.first != ConnectivityResult.none && !_sincronizando) {
        print('🌐 Conexión restaurada - Sincronizando desde Home...');
        await _sincronizarEnBackground();
      }
    });
  }

  // ✅ NUEVO: Sincronización en background (sin UI blocking)
  Future<void> _sincronizarEnBackground() async {
    try {
      setState(() {
        _sincronizando = true;
      });

      bool tieneConexion = await _syncService.checkConnection();
      if (tieneConexion) {
        print('🔄 Sincronización automática en progreso...');
        await _syncService.syncAllPending();
        
        // Verificar estado de sincronización
        final syncStatus = await _syncService.getSyncStatus();
        print('📊 Estado sync automático: $syncStatus');
        
        // Recargar datos si hubo cambios
        if (syncStatus['pendingSync'] == 0) {
          await _cargarDatos();
        }
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

  // Método mejorado para cargar datos desde Hive y sincronizar con Firebase
  Future<void> _cargarDatos() async {
    try {
      print('🔄 Iniciando carga de datos desde Hive...');
      final box = await Hive.openBox('porki_data');
      final allData = box.values.toList();
      
      print('📦 Total de registros en Hive: ${allData.length}');
      
      final cerdas = allData.where((data) => data is Map && data['type'] == 'sow').cast<Map<String, dynamic>>().toList();
      
      print('🐷 Cerdas encontradas en Hive: ${cerdas.length}');
      
      // Si Hive está vacío, descargar desde Firestore
      if (cerdas.isEmpty) {
        print('📥 Hive vacío, descargando cerdas desde Firestore...');
        try {
          await _syncService.downloadAllSowsFromFirebase();
          print('✅ Descarga completada desde Firestore');
        } catch (e) {
          print('❌ Error descargando desde Firestore: $e');
        }
      }

      // ✅ CORREGIDO: Usar el método que SÍ existe en tu NotificationService
      final partosProximos = await NotificationService.getPartosProximos();

      setState(() {
        _notificaciones = partosProximos;
        _cantidadNotificaciones = partosProximos.length;
        _isLoading = false;
      });
      
      print('✅ Datos cargados: ${cerdas.length} cerdas, ${partosProximos.length} notificaciones');
      
    } catch (e) {
      print('❌ Error cargando datos en Home: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Método para sincronizar manualmente - MEJORADO
  Future<void> _sincronizarManual() async {
    setState(() {
      _sincronizando = true;
    });
    
    try {
      print('🔄 Iniciando sincronización manual...');
      
      bool tieneConexion = await _syncService.checkConnection();
      if (tieneConexion) {
        await _syncService.syncAllPending();
        
        // Verificar estado
        final syncStatus = await _syncService.getSyncStatus();
        print('📊 Estado sync manual: $syncStatus');
        
        // Recargar datos después de sincronizar
        await _cargarDatos();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Sincronización completada (${syncStatus['syncedCerdas']}/${syncStatus['totalCerdas']})"),
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
      setState(() {
        _sincronizando = false;
      });
    }
  }

  // ✅ NUEVO: Método para ver estado de sincronización
  Future<void> _verEstadoSync() async {
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
              Text('✅ Cerdas sincronizadas: ${syncStatus['syncedCerdas']}/${syncStatus['totalCerdas']}'),
              Text('📋 Pendientes: ${syncStatus['pendingSync']}'),
              Text('📊 Porcentaje: ${syncStatus['syncPercentage']}%'),
              const SizedBox(height: 16),
              if (syncStatus['pendingSync'] > 0)
                const Text('ℹ️ Los datos pendientes se sincronizarán automáticamente', 
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
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
          // ✅ MEJORADO: Botón de estado de sincronización
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _verEstadoSync,
            tooltip: 'Estado de sincronización',
          ),
          
          // Botón de sincronización
          if (_sincronizando)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _sincronizarManual,
              tooltip: 'Sincronizar manualmente',
            ),
          
          // Badge de notificaciones (calcula en tiempo real desde Hive)
          ValueListenableBuilder<Box>(
            valueListenable: Hive.box('porki_data').listenable(),
            builder: (context, boxNotif, _) {
              final cerdas = boxNotif.values.where((data) => data is Map && data['type'] == 'sow').cast<Map<String, dynamic>>().toList();
              // Calcular recordatorios (partos próximos) — similar a NotificationService
              final ahora = DateTime.now();
              int notCount = 0;
              for (var cerda in cerdas) {
                final fechaEstim = cerda['fecha_estim_parto'];
                if (fechaEstim != null) {
                  try {
                    final fecha = DateTime.parse(fechaEstim);
                    final diff = fecha.difference(ahora).inDays;
                    if (diff <= 7 && diff >= 0) notCount++;
                  } catch (e) {}
                }
              }

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificacionesScreen()),
                      ).then((_) {
                        _cargarDatos();
                      });
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              print('🔄 Botón Refresh presionado manualmente');
              setState(() {
                _isLoading = true;
              });
              _cargarDatos().then((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Datos actualizados ✅")),
                );
              });
            },
          ),
          
          // ✅ NUEVO: Botón para descargar datos de Firestore manualmente
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Descargar de Firestore',
            onPressed: () async {
              print('📥 Descargando datos desde Firestore...');
              try {
                await _syncService.downloadAllSowsFromFirebase();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Datos descargados desde Firestore ✅")),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Error descargando: $e")),
                );
              }
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, username, role),
      body: _isLoading 
          ? _buildLoadingScreen()
          : _buildBody(context),
      // Se removió el FloatingActionButton '+' por solicitud (se usa 'Agregar Cerda' en el menú)
    );
  }

  // Pantalla de carga
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
                // Logo
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
                // ✅ NUEVO: Estado de sync en drawer
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
          // Item de notificaciones en el drawer (dinámico desde Hive)
          ValueListenableBuilder<Box>(
            valueListenable: Hive.box('porki_data').listenable(),
            builder: (context, boxNotif, _) {
              final cerdas = boxNotif.values.where((data) => data is Map && data['type'] == 'sow').cast<Map<String, dynamic>>().toList();
              final ahora = DateTime.now();
              int notCount = 0;
              for (var cerda in cerdas) {
                final fechaEstim = cerda['fecha_estim_parto'];
                if (fechaEstim != null) {
                  try {
                    final fecha = DateTime.parse(fechaEstim);
                    final diff = fecha.difference(ahora).inDays;
                    if (diff <= 7 && diff >= 0) notCount++;
                  } catch (e) {}
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
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificacionesScreen()),
                  );
                },
              );
            },
          ),
          const Divider(),
          // ✅ MEJORADO: Opción para sincronización manual
          ListTile(
            leading: Icon(
              Icons.sync,
              color: _sincronizando ? Colors.grey : Colors.blue,
            ),
            title: _sincronizando 
                ? const Text('Sincronizando...')
                : const Text('Sincronizar ahora'),
            trailing: _sincronizando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _sincronizando ? null : _sincronizarManual,
          ),
          // ✅ NUEVO: Estado de sincronización
          ListTile(
            leading: const Icon(Icons.info, color: Colors.green),
            title: const Text('Estado Sync'),
            onTap: _verEstadoSync,
          ),
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
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Cerrar Sesión'),
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
          // Tarjeta de bienvenida - ACTUALIZADA
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
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      // ✅ MEJORADO: Indicador de sync automático
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
                              style: TextStyle(fontSize: 10, color: Colors.grey),
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
                      builder: (context) => AgregarCerdaScreen(),
                    ),
                  ).then((_) {
                    _cargarDatos();
                  });
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
                  ).then((_) {
                    _cargarDatos();
                  });
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
                return const Center(child: CircularProgressIndicator(color: Colors.pink));
              }

              final box = snapshot.data as Box;

              // Escuchar cambios en la caja para actualizar el resumen en tiempo real
              return ValueListenableBuilder<Box>(
                valueListenable: box.listenable(),
                builder: (context, Box listenedBox, _) {
                  // ✅ DEBUG: Mostrar estado en logs
                  print('📊 ValueListenableBuilder rebuild - Hive tiene ${listenedBox.values.length} items');
                  
                  final cerdas = listenedBox
                      .values
                      .where((data) => data is Map && data['type'] == 'sow')
                      .cast<Map<String, dynamic>>()
                      .toList();

                  print('🐷 Calculando resumen: ${cerdas.length} cerdas detectadas');

                  int prenadas = cerdas.where((cerda) => cerda['embarazada'] == true).length;

                  int totalLechones = 0;
                  int partosHoy = 0;
                  int partosPendientes = 0;
                  int vacunasHoy = 0;

                  final ahora = DateTime.now();

                  for (var cerda in cerdas) {
                    totalLechones += (cerda['lechones_nacidos'] as int? ?? 0);

                    // Contar partos de hoy y pendientes por cerda
                    final partos = List<Map<String, dynamic>>.from(cerda['partos'] ?? []);
                    for (var parto in partos) {
                      if (parto['fecha_parto'] != null) {
                        try {
                          final fechaParto = DateTime.parse(parto['fecha_parto']);
                          if (fechaParto.year == ahora.year && 
                              fechaParto.month == ahora.month && 
                              fechaParto.day == ahora.day) {
                            partosHoy++;
                          } else if (fechaParto.isAfter(ahora)) {
                            // Partos pendientes (futuros)
                            partosPendientes++;
                          }
                        } catch (e) {
                          // Fecha inválida, continuar
                        }
                      }
                    }

                    // Contar vacunas de hoy (fecha = hoy)
                    final vacunas = List<Map<String, dynamic>>.from(cerda['vacunas'] ?? []);
                    for (var vacuna in vacunas) {
                      if (vacuna['fecha'] != null) {
                        try {
                          final fechaVacuna = DateTime.parse(vacuna['fecha']);
                          if (fechaVacuna.year == ahora.year && 
                              fechaVacuna.month == ahora.month && 
                              fechaVacuna.day == ahora.day) {
                            vacunasHoy++;
                          }
                        } catch (e) {
                          // Fecha inválida, continuar
                        }
                      }
                    }
                  }

                  // Actualizar estado local opcional (no obligatorio)
                  // if (mounted) setState(() => _partosHoy = partosHoy);

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
                              const Icon(Icons.analytics, color: Colors.pink),
                              const SizedBox(width: 8),
                              const Text(
                                'Resumen General 🐷',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              // ✅ NUEVO: Indicador de que está escuchando Firestore
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green[100],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cloud_done, color: Colors.green, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'En tiempo real',
                                      style: TextStyle(fontSize: 10, color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildInfoItem('Total Cerdas', _formatNumber(cerdas.length), '🐖', cerdas.length),
                                  _buildInfoItem('Preñas', _formatNumber(prenadas), '🐷', prenadas),
                                  _buildInfoItem('Lechones', _formatNumber(totalLechones), '🐽', totalLechones),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildInfoItem('Partos Hoy', partosHoy.toString(), '📅', partosHoy),
                                  _buildInfoItem('Partos Pendientes', partosPendientes.toString(), '⏰', partosPendientes),
                                  _buildInfoItem('Vacunas Hoy', vacunasHoy.toString(), '💉', vacunasHoy),
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
                                const Icon(Icons.child_care, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '¡$partosHoy parto${partosHoy == 1 ? '' : 's'} hoy! 🎊',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
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
          // Panel de notificaciones calculado en tiempo real desde Hive
          ValueListenableBuilder<Box>(
            valueListenable: Hive.box('porki_data').listenable(),
            builder: (context, boxNotif, _) {
              final cerdas = boxNotif.values.where((data) => data is Map && data['type'] == 'sow').cast<Map<String, dynamic>>().toList();
              final ahora = DateTime.now();
              final notifs = <Map<String, dynamic>>[];

              for (var cerda in cerdas) {
                final fechaEstim = cerda['fecha_estim_parto'];
                if (fechaEstim != null) {
                  try {
                    final fecha = DateTime.parse(fechaEstim);
                    final diff = fecha.difference(ahora).inDays;
                    if (diff <= 7 && diff >= 0) {
                      notifs.add({
                        'mensaje': 'Parto próximo',
                        'cerda': cerda,
                        'prioridad': diff <= 1 ? 'alta' : 'media',
                      });
                    }
                  } catch (e) {}
                }
              }

              if (notifs.isEmpty) return const SizedBox();

              return Column(
                children: [
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '¡${notifs.length} recordatorio${notifs.length == 1 ? '' : 's'} de partos! ⏰',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // Widget para panel de notificaciones
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            ..._notificaciones.take(3).map((notif) => _buildItemNotificacion(notif)),
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
                  ).then((_) {
                    _cargarDatos();
                  });
                },
                child: const Text('Ver todas las notificaciones'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget para item de notificación
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
          Icon(
            Icons.pregnant_woman,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notificacion['mensaje'] ?? 'Parto próximo',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cerda: ${notificacion['cerda']?['nombre'] ?? 'Sin nombre'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (prioridad == 'alta') ...[
            const SizedBox(width: 8),
            const Icon(Icons.warning, color: Colors.red, size: 16),
          ],
        ],
      ),
    );
  }

  // Acción rápida
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
            title.contains('Ver Cerdas')
                ? const Text('🐷', style: TextStyle(fontSize: 40))
                : Icon(icon, size: 40, color: color),
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

  // Item de información
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
            color: numero > 0 ? Colors.black87 : Colors.grey
          ),
        ),
      ],
    );
  }

  // Cierre de sesión
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
          TextButton(
            onPressed: () {
              // ✅ NUEVO: Limpiar sync antes de cerrar sesión
              _syncTimer?.cancel();
              _connectivitySubscription?.cancel();
              
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) => false,
              );
            },
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}