import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_porki/backend/services/sync_service.dart';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart';
import 'package:my_porki/frotend/screens/cerda_screen.dart';
import 'package:my_porki/frotend/screens/historial_screen.dart';
import 'package:my_porki/frotend/screens/informes_screen.dart';
import 'package:my_porki/frotend/screens/login_screen.dart';
import 'package:my_porki/frotend/screens/notificaciones_screen.dart';
import 'package:my_porki/frotend/screens/settings_screen.dart';
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
  int _cantidadNotificaciones = 0;
  late Box _porkiBox;

  // Manejo de nombre/rol actualizado
  late Map<String, dynamic> _currentUserData;

  late final SyncService _syncService;
  Timer? _syncTimer;

  StreamSubscription<dynamic>? _connectivitySubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _firebaseSubscription;

  // === NUEVO: listener del historial global (collectionGroup) ===
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historialSub;

  static const Duration _syncInterval = Duration(minutes: 2);
  static const int _notificationDaysThreshold = 7;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _currentUserData = Map<String, dynamic>.from(widget.userData);
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      _porkiBox = await Hive.openBox('porki_data');
      print('✅ Caja porki_data abierta en HomeScreen');

      _iniciarFirebaseListener(); // sows
      _iniciarHistorialListener(); // historial (subcolecciones)
      _iniciarSincronizacionAutomatica();

      await _cargarDatosIniciales();
    } catch (e) {
      print('❌ Error en inicialización: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final partosProximos = await SowService.obtenerPartosProximos();
      if (mounted) {
        setState(() {
          _cantidadNotificaciones = partosProximos.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando datos iniciales: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // === A) Parser de fechas ROBUSTO (Timestamp, DateTime, int ms, String ISO) ===
  DateTime? _parseFechaSafe(dynamic v) {
    try {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate(); // Firestore
      if (v is int) {
        // Asumimos milisegundos; si tus enteros están en segundos, cambia a v * 1000.
        return DateTime.fromMillisecondsSinceEpoch(v);
      }
      if (v is String) {
        return DateTime.tryParse(v);
      }
      if (v is Map && v['_seconds'] != null) {
        final seconds = v['_seconds'] as int;
        final nanos = (v['_nanoseconds'] ?? 0) as int;
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + (nanos ~/ 1000000),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // === Firestore: listener de cerdas (documentos de 'sows') ===
  void _iniciarFirebaseListener() {
    try {
      final firestore = FirebaseFirestore.instance;

      _firebaseSubscription = firestore
          .collection('sows')
          // .where('ownerId', isEqualTo: _currentUserData['uid']) // opcional si multi-tenant
          .snapshots()
          .listen(
            _procesarSnapshotFirebase,
            onError: (error) {
              print('❌ Error en Firebase listener (sows): $error');
            },
          );
    } catch (e) {
      print('❌ Fallo al iniciar Firebase listener (sows): $e');
    }
  }

  Future<void> _procesarSnapshotFirebase(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    try {
      final remoteIds = <String>{};

      for (var doc in snapshot.docs) {
        remoteIds.add(doc.id);
        await _actualizarCerdaDesdeFirebase(doc);
      }

      await _limpiarCerdasLocales(remoteIds);
    } catch (e) {
      print('❌ Error procesando snapshot sows: $e');
    }
  }

  // === B) Precedencia REMOTA al fusionar datos sow (lo remoto manda) ===
  Future<void> _actualizarCerdaDesdeFirebase(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final sowId = doc.id;

    final sowData = {
      ...data,
      'id': sowId,
      'type': 'sow',
      'synced': true,
      'lastSync': DateTime.now().toIso8601String(),
    };

    final localItem = await _obtenerItemLocal(sowId);

    // Si el remoto no trae estos campos (porque están en subcolecciones),
    // conservamos los del local; pero si el remoto sí los trae, se usan los remotos.
    if (localItem != null) {
      sowData['historial'] =
          sowData['historial'] ?? localItem['historial'] ?? [];
      sowData['vacunas'] = sowData['vacunas'] ?? localItem['vacunas'] ?? [];
      sowData['partos'] = sowData['partos'] ?? localItem['partos'] ?? [];
    }

    await _porkiBox.put(sowId, sowData);
    print('✅ Actualizada desde Firebase: ${sowData['nombre']} ($sowId)');
  }

  Future<Map<String, dynamic>?> _obtenerItemLocal(String sowId) async {
    try {
      final localItem = await _porkiBox.values.firstWhere(
        (it) => it is Map && (it['id'] == sowId || it['hiveKey'] == sowId),
        orElse: () => null,
      );

      if (localItem is Map) {
        final convertedLocal = <String, dynamic>{};
        localItem.forEach((k, v) => convertedLocal[k.toString()] = v);
        return convertedLocal;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _limpiarCerdasLocales(Set<String> remoteIds) async {
    for (var key in _porkiBox.keys.toList()) {
      final item = _porkiBox.get(key);
      if (item is Map && item['type'] == 'sow') {
        final localSowId = item['id'];
        if (localSowId != null && !remoteIds.contains(localSowId)) {
          await _porkiBox.delete(key);
          print('🗑️ Cerda eliminada localmente: $localSowId');
        }
      }
    }
  }

  // === C) Listener del HISTORIAL global de todas las cerdas con collectionGroup ===
  void _iniciarHistorialListener() {
    try {
      final firestore = FirebaseFirestore.instance;

      _historialSub = firestore
          .collectionGroup('historial') // subcolección en sows/{id}/historial
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen(
            (snap) async {
              final cambios = <Map<String, dynamic>>[];

              for (final d in snap.docs) {
                final data = d.data();
                final parent = d.reference.parent.parent; // sows/{sowId}
                final sowId = data['cerdaId'] ?? parent?.id ?? '';
                final fecha =
                    _parseFechaSafe(data['timestamp']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);

                // Resolver nombre de la cerda desde Hive (si existe)
                String? sowName;
                final localSow = (sowId.isNotEmpty)
                    ? _porkiBox.get(sowId)
                    : null;
                if (localSow is Map && localSow['nombre'] != null) {
                  sowName = localSow['nombre']?.toString();
                }

                cambios.add({
                  'id': d.id,
                  'sowId': sowId,
                  'sowName': sowName ?? sowId,
                  'tipo': data['tipo'] ?? '',
                  'descripcion': data['descripcion'] ?? '',
                  'autorId': data['autorId'] ?? '',
                  'timestamp': fecha.millisecondsSinceEpoch,
                  'datos': (data['datos'] is Map)
                      ? Map<String, dynamic>.from(data['datos'] as Map)
                      : null,
                });
              }

              // Persistir historial en Hive (clave fija)
              await _porkiBox.put('global_historial', cambios);
              // No hace falta setState: ValueListenableBuilder del Box se encargará
            },
            onError: (e) {
              print('❌ Error historial listener: $e');
            },
          );
    } catch (e) {
      print('❌ Fallo al iniciar historial listener: $e');
    }
  }

  void _iniciarSincronizacionAutomatica() {
    _syncTimer = Timer.periodic(_syncInterval, (timer) async {
      if (!_sincronizando) await _sincronizarEnBackground();
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      if (result != ConnectivityResult.none && !_sincronizando) {
        await _sincronizarEnBackground();
      }
    });
  }

  Future<void> _sincronizarEnBackground() async {
    if (mounted) setState(() => _sincronizando = true);

    try {
      final tieneConexion = await _syncService.checkConnection();
      if (tieneConexion) {
        await _syncService.syncAllPending();
        print('✅ Sincronización automática completada');
      }
    } catch (e) {
      print('❌ Error sincronizando: $e');
    } finally {
      if (mounted) setState(() => _sincronizando = false);
    }
  }

  Future<void> _sincronizarManualmente() async {
    if (_sincronizando) return;

    setState(() => _sincronizando = true);

    try {
      await _syncService.syncAllPending();

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

  // Actualizar nombre/rol en UI
  void _actualizarDatosUsuario(Map<String, dynamic> nuevosDatos) {
    if (mounted) {
      setState(() {
        _currentUserData = Map<String, dynamic>.from(nuevosDatos);
      });
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _firebaseSubscription?.cancel();
    _historialSub?.cancel(); // === importante ===
    super.dispose();
  }

  // Acciones / navegación
  void _navegarACerdas() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CerdaScreen()),
    );
  }

  Future<void> _recargarDatos() async {
    final partosProximos = await SowService.obtenerPartosProximos();
    if (mounted) {
      setState(() {
        _cantidadNotificaciones = partosProximos.length;
      });
    }
  }

  // Obtener cerdas desde Hive (síncrono)
  List<Map<String, dynamic>> _obtenerCerdasDesdeHive() {
    final cerdas = <Map<String, dynamic>>[];

    for (var item in _porkiBox.values) {
      if (item is Map && item['type'] == 'sow') {
        final cerda = Map<String, dynamic>.from(item);
        cerdas.add(cerda);
      }
    }

    return cerdas;
  }

  // Resumen general
  Map<String, int> _calcularResumen(List<Map<String, dynamic>> cerdas) {
    int totalCerdas = cerdas.length;
    int prenadas = 0;
    int totalLechones = 0;
    int partosHoy = 0;
    int partosPendientes = 0;
    int vacunasHoy = 0;
    final ahora = DateTime.now();

    for (var cerda in cerdas) {
      // Preñadas
      final estado = (cerda['estado'] ?? '').toString().toLowerCase();
      if (estado.contains('preñ') || estado.contains('pregnant')) {
        prenadas++;
      } else if (cerda['fecha_prenez'] != null) {
        prenadas++;
      } else {
        final fechaPartoCalc = _parseFechaSafe(cerda['fecha_parto_calculado']);
        if (fechaPartoCalc != null && fechaPartoCalc.isAfter(DateTime.now())) {
          prenadas++;
        }
      }

      // Lechones
      final partos = cerda['partos'] as List<dynamic>? ?? [];
      for (var parto in partos) {
        if (parto is Map) {
          final numLechones = parto['num_lechones'];
          totalLechones += (numLechones is int
              ? numLechones
              : int.tryParse('$numLechones') ?? 0);
        }
      }

      // Partos hoy
      for (var parto in partos) {
        if (parto is Map) {
          final fechaParto = _parseFechaSafe(parto['fecha']);
          if (fechaParto != null &&
              fechaParto.year == ahora.year &&
              fechaParto.month == ahora.month &&
              fechaParto.day == ahora.day) {
            partosHoy++;
          }
        }
      }

      // Partos pendientes
      final fechaPartoCalculado = _parseFechaSafe(
        cerda['fecha_parto_calculado'],
      );
      if (fechaPartoCalculado != null && !fechaPartoCalculado.isBefore(ahora)) {
        partosPendientes++;
      }

      // Vacunas hoy
      final vacunas = cerda['vacunas'] as List<dynamic>? ?? [];
      for (var vac in vacunas) {
        if (vac is Map) {
          final dosisProgramadas =
              vac['dosis_programadas'] as List<dynamic>? ?? [];
          for (var dosis in dosisProgramadas) {
            if (dosis is Map) {
              final fVac = _parseFechaSafe(dosis['fecha']);
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
    }

    return {
      'totalCerdas': totalCerdas,
      'prenadas': prenadas,
      'totalLechones': totalLechones,
      'partosHoy': partosHoy,
      'partosPendientes': partosPendientes,
      'vacunasHoy': vacunasHoy,
    };
  }

  // ==== UI ====

  @override
  Widget build(BuildContext context) {
    final username = _currentUserData['username'] ?? 'Usuario';
    final role = _currentUserData['role'] ?? 'colaborador';

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
          _buildNotificationBadge(),
        ],
      ),
      drawer: _buildDrawer(context),
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
              _buildActionCard(
                context,
                'Agregar Cerda',
                Icons.add_circle,
                Colors.green,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AgregarCerdaScreen(),
                    ),
                  ).then((_) => _recargarDatos());
                },
              ),
              _buildActionCard(
                context,
                'Ver Cerdas',
                Icons.pets,
                Colors.blue,
                () => _navegarACerdas(),
              ),
              _buildActionCard(
                context,
                'Historial',
                Icons.history,
                Colors.orange,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistorialScreen()),
                  );
                },
              ),
              _buildActionCard(
                context,
                'Informes',
                Icons.analytics,
                Colors.purple,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InformesScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _porkiBox.listenable(),
              builder: (context, Box box, _) {
                final cerdas = _obtenerCerdasDesdeHive();
                final resumen = _calcularResumen(cerdas);
                final List<dynamic> cambios =
                    (box.get('global_historial') as List?) ?? [];

                return Column(
                  children: [
                    _buildResumenContent(resumen),
                    const SizedBox(height: 16),
                    Expanded(child: _buildHistorialList(cambios)),
                  ],
                );
              },
            ),
          ),
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

  Widget _buildResumenContent(Map<String, int> resumen) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Resumen General',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(
                  'Total Cerdas',
                  resumen['totalCerdas'].toString(),
                  '🐖',
                  resumen['totalCerdas']!,
                ),
                _buildInfoItem(
                  'Preñadas',
                  resumen['prenadas'].toString(),
                  '🐷',
                  resumen['prenadas']!,
                ),
                _buildInfoItem(
                  'Lechones',
                  resumen['totalLechones'].toString(),
                  '🐽',
                  resumen['totalLechones']!,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(
                  'Partos Hoy',
                  resumen['partosHoy'].toString(),
                  '📅',
                  resumen['partosHoy']!,
                ),
                _buildInfoItem(
                  'Pendientes',
                  resumen['partosPendientes'].toString(),
                  '⏰',
                  resumen['partosPendientes']!,
                ),
                _buildInfoItem(
                  'Vacunas Hoy',
                  resumen['vacunasHoy'].toString(),
                  '💉',
                  resumen['vacunasHoy']!,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorialList(List<dynamic> cambios) {
    if (cambios.isEmpty) {
      return const Card(
        elevation: 2,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('Sin cambios recientes')),
        ),
      );
    }

    return Card(
      elevation: 3,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cambios.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = cambios[i] as Map;
          final ts = c['timestamp'];
          final fecha =
              _parseFechaSafe(ts) ??
              DateTime.fromMillisecondsSinceEpoch((ts is int ? ts : 0));

          return ListTile(
            leading: _iconoCambio((c['tipo'] ?? '').toString()),
            title: Text(_tituloCambio(Map<String, dynamic>.from(c))),
            subtitle: Text('${c['descripcion'] ?? ''}\n${_fmtFecha(fecha)}'),
            isThreeLine: true,
            trailing: Text('#${c['sowName'] ?? c['sowId'] ?? '-'}'),
          );
        },
      ),
    );
  }

  Icon _iconoCambio(String tipo) {
    switch (tipo) {
      case 'peso_actualizado':
        return const Icon(Icons.monitor_weight, color: Colors.blueGrey);
      case 'celo':
        return const Icon(Icons.favorite_border, color: Colors.pink);
      case 'parto':
        return const Icon(Icons.pregnant_woman, color: Colors.purple);
      case 'vacuna':
        return const Icon(Icons.vaccines, color: Colors.teal);
      case 'estado':
        return const Icon(Icons.info_outline, color: Colors.indigo);
      default:
        return const Icon(Icons.change_circle_outlined, color: Colors.orange);
    }
  }

  String _tituloCambio(Map<String, dynamic> c) {
    final tipo = (c['tipo'] ?? '').toString();
    switch (tipo) {
      case 'peso_actualizado':
        final peso = (c['datos']?['peso']) ?? '';
        return (peso != '')
            ? 'Peso actualizado a $peso kg'
            : 'Peso actualizado';
      case 'celo':
        return 'Registro de celo';
      case 'parto':
        return 'Registro de parto';
      case 'vacuna':
        return 'Vacunación registrada';
      case 'estado':
        return 'Cambio de estado';
      default:
        return 'Cambio en la cerda';
    }
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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

  Widget _buildNotificationBadge() {
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
        if (_cantidadNotificaciones > 0)
          _buildBadgeCounter(_cantidadNotificaciones),
      ],
    );
  }

  Widget _buildBadgeCounter(int count) {
    return Positioned(
      right: 8,
      top: 8,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
        child: Text(
          count > 9 ? '9+' : count.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 10),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    final username = _currentUserData['username'] ?? 'Usuario';
    final role = _currentUserData['role'] ?? 'colaborador';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildDrawerHeader(username, role),

          _buildDrawerItem(
            context,
            Icons.home,
            'Inicio',
            Colors.pink,
            () => Navigator.pop(context),
          ),
          _buildDrawerItem(
            context,
            Icons.add_circle,
            'Agregar Cerda',
            Colors.green,
            () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AgregarCerdaScreen()),
              ).then((_) => _recargarDatos());
            },
          ),
          _buildDrawerItem(context, Icons.pets, 'Ver Cerdas', Colors.blue, () {
            Navigator.pop(context);
            _navegarACerdas();
          }),
          _buildDrawerItem(
            context,
            Icons.history,
            'Historial',
            Colors.orange,
            () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistorialScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            Icons.notifications,
            'Notificaciones',
            Colors.purple,
            () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificacionesScreen()),
              );
            },
          ),
          const Divider(),
          _buildDrawerItem(
            context,
            Icons.sync,
            'Sincronizar Ahora',
            Colors.blue,
            _sincronizarManualmente,
          ),
          _buildDrawerItem(
            context,
            Icons.settings,
            'Configuración',
            Colors.grey[700]!,
            () async {
              Navigator.pop(context);
              final updatedData = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SettingsScreen(userData: _currentUserData),
                ),
              );

              if (updatedData != null && updatedData['username'] != null) {
                _actualizarDatosUsuario(updatedData);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Usuario actualizado: ${updatedData['username']}',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
                setState(() {});
              }
            },
          ),
          _buildDrawerItem(
            context,
            Icons.exit_to_app,
            'Cerrar Sesión',
            Colors.pink,
            _cerrarSesion,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(String username, String role) {
    return DrawerHeader(
      decoration: const BoxDecoration(color: Colors.pink),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/images/LogoAlex.png', width: 70, height: 70),
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
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      onTap: onTap,
    );
  }

  void _cerrarSesion() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _firebaseSubscription?.cancel();
    _historialSub?.cancel();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
