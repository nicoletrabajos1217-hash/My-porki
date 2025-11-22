import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_porki/backend/services/sync_service.dart';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart';
import 'package:my_porki/frotend/screens/cerda_screen.dart';
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

  late final SyncService _syncService;
  Timer? _syncTimer;
  StreamSubscription<dynamic>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firebaseSubscription;

  List<Map<String, dynamic>> _notificaciones = [];
  int _cantidadNotificaciones = 0;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _iniciarFirebaseListener();
    _cargarDatos();
    _iniciarSincronizacionAutomatica();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _firebaseSubscription?.cancel();
    super.dispose();
  }

  DateTime? _parseFechaSafe(dynamic fecha) {
    if (fecha == null) return null;
    try {
      return DateTime.parse(fecha.toString());
    } catch (_) {
      return null;
    }
  }

  void _iniciarFirebaseListener() {
    try {
      final firestore = FirebaseFirestore.instance;
      
      _firebaseSubscription = firestore
          .collection('sows')
          .snapshots()
          .listen((snapshot) async {
        try {
          final box = await Hive.openBox('porki_data');

          print('🔄 Firebase listener: ${snapshot.docs.length} documentos detectados');

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final sowId = doc.id;
            final sowData = {
              ...data,
              'id': sowId,
              'type': 'sow',
              'synced': true,
              'lastSync': DateTime.now().toIso8601String(),
            };

            bool encontrado = false;
            for (var key in box.keys) {
              final item = box.get(key);
              if (item is Map && item['id'] == sowId) {
                final Map<dynamic, dynamic> itemLocal = item;
                final Map<String, dynamic> convertedItem = {};
                itemLocal.forEach((k, v) {
                  convertedItem[k.toString()] = v;
                });
                sowData['historial'] = convertedItem['historial'] ?? [];
                sowData['vacunas'] = convertedItem['vacunas'] ?? [];
                sowData['partos'] = convertedItem['partos'] ?? [];
                await box.put(key, sowData);
                encontrado = true;
                print('✅ Actualizada cerda: ${sowData['nombre']}');
                break;
              }
            }

            if (!encontrado) {
              await box.put(sowId, sowData);
              print('✅ Nueva cerda agregada: ${sowData['nombre']}');
            }
          }

          final remoteIds = snapshot.docs.map((d) => d.id).toSet();
          for (var key in box.keys.toList()) {
            final item = box.get(key);
            if (item is Map && item['type'] == 'sow') {
              final localSowId = item['id'];
              if (localSowId != null && !remoteIds.contains(localSowId)) {
                await box.delete(key);
                print('🗑️ Cerda eliminada de local: $localSowId');
              }
            }
          }

          if (mounted) {
            await _cargarDatos();
            setState(() => _isLoading = false);
          }
        } catch (e) {
          print('❌ Error procesando snapshot: $e');
        }
      }, onError: (error) {
        print('❌ Error en Firebase listener: $error');
      });
    } catch (e) {
      print('❌ Fallo al iniciar Firebase listener: $e');
    }
  }

  void _iniciarSincronizacionAutomatica() {
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (!_sincronizando) await _sincronizarEnBackground();
    });

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none && !_sincronizando) {
        await _sincronizarEnBackground();
      }
    });
  }

  Future<void> _sincronizarEnBackground() async {
    if (mounted) setState(() => _sincronizando = true);
    try {
      bool tieneConexion = await _syncService.checkConnection();
      if (tieneConexion) {
        await _syncService.syncAllPending();
        await _cargarDatos();
        print('✅ Sincronización automática completada');
      }
    } catch (e) {
      print('❌ Error sincronizando: $e');
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _cargarDatos() async {
    try {
      final cerdas = await SowService.obtenerCerdas();
      final partosProximos = await SowService.obtenerPartosProximos();
      
      print('📊 Datos cargados: ${cerdas.length} cerdas, ${partosProximos.length} partos próximos');
      
      if (mounted) {
        setState(() {
          _notificaciones = partosProximos;
          _cantidadNotificaciones = partosProximos.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('❌ Error cargando datos: $e');
    }
  }

  Future<void> _sincronizarManualmente() async {
    if (_sincronizando) return;
    
    setState(() => _sincronizando = true);
    
    try {
      final box = await Hive.openBox('porki_data');
      final firestore = FirebaseFirestore.instance;
      
      await _syncService.syncAllPending();
      
      final snapshot = await firestore.collection('sows').get();
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final sowData = {
          ...data,
          'id': doc.id,
          'type': 'sow',
          'synced': true,
          'lastSync': DateTime.now().toIso8601String(),
        };
        await box.put(doc.id, sowData);
      }
      
      await _cargarDatos();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sincronización completada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Error en sincronización manual: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.userData['username'] ?? 'Usuario';
    final role = widget.userData['role'] ?? 'colaborador';

    return Scaffold(
      appBar: AppBar(
        title: Text('My Porki - $username'),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: _sincronizando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.sync),
            onPressed: _sincronizarManualmente,
            tooltip: 'Sincronizar',
          ),
          ValueListenableBuilder<Box>(
            valueListenable: Hive.box('porki_data').listenable(),
            builder: (context, boxNotif, _) {
              int notCount = 0;
              final ahora = DateTime.now();
              for (var data in boxNotif.values) {
                if (data is Map && data['type'] == 'sow') {
                  final fechaParto = _parseFechaSafe(data['fecha_parto_calculado']);
                  if (fechaParto != null) {
                    final diff = fechaParto.difference(ahora).inDays;
                    if (diff >= 0 && diff <= 7) notCount++;
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
          Text('Cargando datos...', style: TextStyle(color: Colors.grey)),
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
                Image.asset('assets/images/LogoAlex.png', width: 70, height: 70),
                const SizedBox(height: 10),
                Text(username,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(role.toUpperCase(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white)),
                        ),
                        SizedBox(width: 4),
                        Text('Sincronizando...',
                            style: TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.pink),
            title: const Text('Inicio'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle, color: Colors.green),
            title: const Text('Agregar Cerda'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AgregarCerdaScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.pets, color: Colors.blue),
            title: const Text('Ver Cerdas'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CerdaScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.orange),
            title: const Text('Historial'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const HistorialScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications, color: Colors.purple),
            title: const Text('Notificaciones'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const NotificacionesScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync, color: Colors.blue),
            title: const Text('Sincronizar Ahora'),
            onTap: () {
              Navigator.pop(context);
              _sincronizarManualmente();
            },
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.pink),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.pink)),
            onTap: () {
              _syncTimer?.cancel();
              _connectivitySubscription?.cancel();
              _firebaseSubscription?.cancel();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
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
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildActionCard(context, 'Agregar Cerda', Icons.add_circle, Colors.green, () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AgregarCerdaScreen()));
              }),
              _buildActionCard(context, 'Ver Cerdas', Icons.pets, Colors.blue, () {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CerdaScreen()));
              }),
              _buildActionCard(context, 'Historial', Icons.history, Colors.orange, () {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const HistorialScreen()));
              }),
              _buildActionCard(context, 'Notificaciones', Icons.notifications, Colors.purple, () {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const NotificacionesScreen()));
              }),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildResumenGeneral()),
        ],
      ),
    );
  }

  Widget _buildResumenGeneral() {
    return FutureBuilder(
      future: Hive.openBox('porki_data'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.pink));
        }

        final box = snapshot.data as Box;

        return ValueListenableBuilder<Box>(
          valueListenable: box.listenable(),
          builder: (context, listenedBox, _) {
            final cerdas = <Map<String, dynamic>>[];

            for (var data in listenedBox.values) {
              if (data is Map && data['type'] == 'sow') {
                final cerda = <String, dynamic>{};
                data.forEach((k, v) => cerda[k.toString()] = v);
                cerdas.add(cerda);
              }
            }

            int totalCerdas = cerdas.length;
            int prenadas = cerdas.where((c) {
              final estado = (c['estado'] ?? c['estado_cerda'] ?? '').toString().toLowerCase();
              return estado.contains('pre') || estado.contains('gest');
            }).length;

            int totalLechones = 0;
            int partosHoy = 0;
            int partosPendientes = 0;
            int vacunasHoy = 0;
            final ahora = DateTime.now();

            for (var cerda in cerdas) {
              totalLechones += ((cerda['lechones_nacidos'] ??
                      cerda['numero_lechones'] ??
                      0) as int? ?? 0);

              final fechaParto = cerda['fecha_parto_calculado'] ??
                  cerda['fechaPartoCalculado'] ??
                  cerda['fecha_parto'];
              final fecha = _parseFechaSafe(fechaParto);
              if (fecha != null) {
                if (fecha.year == ahora.year &&
                    fecha.month == ahora.month &&
                    fecha.day == ahora.day) {
                  partosHoy++;
                } else if (fecha.isAfter(ahora)) {
                  partosPendientes++;
                }
              }

              final vacunas = cerda['vacunas'];
              if (vacunas is List) {
                for (var vac in vacunas) {
                  if (vac is Map) {
                    final fVac = _parseFechaSafe(vac['fecha']);
                    if (fVac != null &&
                        fVac.year == ahora.year &&
                        fVac.month == ahora.month &&
                        fVac.day == ahora.day) {
                      vacunasHoy++;
                    }
                  }
                }
              }
            }

            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text('Resumen General',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoItem('Total Cerdas', totalCerdas.toString(), '🐖', totalCerdas),
                        _buildInfoItem('Preñadas', prenadas.toString(), '🐷', prenadas),
                        _buildInfoItem('Lechones', totalLechones.toString(), '🐽', totalLechones),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoItem('Partos Hoy', partosHoy.toString(), '📅', partosHoy),
                        _buildInfoItem('Pendientes', partosPendientes.toString(), '⏰', partosPendientes),
                        _buildInfoItem('Vacunas Hoy', vacunasHoy.toString(), '💉', vacunasHoy),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoItem(String title, String value, String emoji, int numero) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: numero > 0 ? Colors.pink : Colors.grey)),
        Text(title, style: TextStyle(fontSize: 12, color: numero > 0 ? Colors.black87 : Colors.grey)),
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}