import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:my_porki/backend/firebase_options.dart';
import 'frotend/screens/login_screen.dart';
import 'frotend/screens/home_screen.dart';
import 'backend/services/sync_service.dart';
import 'backend/services/notification_service.dart';
import 'backend/services/sow_service.dart';
import 'backend/services/auth_service.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔹 Inicialización básica
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await Hive.initFlutter();
  await Hive.openBox('porki_data');
  await Hive.openBox('porki_users');
  await Hive.openBox('porki_sync'); // ✅ NUEVO: Box para sincronización
  
  // 🔹 Inicializar servicios
  await NotificationService.initialize();
  await SowService.initialize();
  
  // ✅ NUEVO: Iniciar sincronización automática en background
  _startBackgroundSync();
  
  // Mostrar errores en pantalla (temporal) para depuración de UI
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Error inesperado en la UI:\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  runApp(const MyPorkiApp());
}

// ✅ NUEVO: Sincronización automática en background
void _startBackgroundSync() {
  final SyncService syncService = SyncService();
  
  // Sincronizar 10 segundos después de iniciar
  Timer(Duration(seconds: 10), () async {
    bool tieneConexion = await syncService.checkConnection();
    if (tieneConexion) {
      print('🔄 Sincronización automática al iniciar...');
      await syncService.syncAllPending();
      
      // Verificar estado de sincronización
      final syncStatus = await syncService.getSyncStatus();
      print('📊 Estado de sincronización: $syncStatus');
    }
  });
  
  // Sincronizar cada 1 minuto
  Timer.periodic(Duration(minutes: 1), (timer) async {
    bool tieneConexion = await syncService.checkConnection();
    if (tieneConexion) {
      print('🔄 Sincronización periódica automática...');
      await syncService.syncAllPending();
    }
  });
  
  // Sincronizar cuando cambia la conexión
  Connectivity().onConnectivityChanged.listen((result) async {
    if (result != ConnectivityResult.none) {
      print('🌐 Conexión restaurada - Sincronizando...');
      await syncService.syncAllPending();
      await NotificationService.scheduleBirthNotifications();
    }
  });
}

class MyPorkiApp extends StatelessWidget {
  const MyPorkiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Porki',
      theme: ThemeData(
        primarySwatch: Colors.pink,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AppEntryPoint(),
    );
  }
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  bool _checkingAuth = true;
  late final SyncService _syncService;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _initializeApp();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  // 🔹 Inicialización completa de la app
  Future<void> _initializeApp() async {
    // Verificar autenticación y conexión en paralelo
    await Future.wait([
      _checkAuthentication(),
      _initializeBackgroundServices(),
    ]);
  }

  // 🔹 Verificar autenticación
  Future<void> _checkAuthentication() async {
    // ✅ AHORA FUNCIONA: Método estático
    final isLoggedIn = await AuthService.isLoggedIn();
    
    // Pequeña pausa para mostrar el splash
    await Future.delayed(const Duration(milliseconds: 1500));
    
    if (mounted) {
      setState(() {
        _checkingAuth = false;
      });
      print('🔑 Auth checked: isLoggedIn=$isLoggedIn');
      
      // Navegar a la pantalla correspondiente
      if (isLoggedIn) {
        // Obtener datos del usuario
        final userData = await AuthService.getCurrentUser();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              userData: userData ?? {
                'username': 'Usuario',
                'email': '',
                'role': 'usuario'
              },
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
      }
    }
  }

  // 🔹 Inicialización en segundo plano
  Future<void> _initializeBackgroundServices() async {
    try {
      // ✅ NUEVO: Sincronización inicial más robusta
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      
      if (result.isNotEmpty && result.first != ConnectivityResult.none) {
        print('🔄 Iniciando sincronización inicial...');
        // 📥 Descargar cerdas desde Firebase primero
        await _syncService.downloadAllSowsFromFirebase();
        // 📤 Luego sincronizar cambios locales
        await _syncService.syncAllPending();
      } else {
        print('📴 Sin conexión - Datos guardados localmente');
      }
      
      // Programar notificaciones existentes
      await NotificationService.scheduleBirthNotifications();
      await _scheduleExistingVaccines();
      
      // ✅ MEJORADO: Escuchar cambios de conexión
      _connectivitySubscription = connectivity.onConnectivityChanged.listen((results) async {
        if (results.isNotEmpty && results.first != ConnectivityResult.none) {
          print('🌐 Conexión detectada - Sincronizando...');
          await _syncService.syncAllPending();
          await NotificationService.scheduleBirthNotifications();
          await _scheduleExistingVaccines();
          
          // Mostrar snackbar si la app está visible
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Sincronización completada'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      });
    } catch (e) {
      print('❌ Error en inicialización de servicios: $e');
    }
  }

  // 🔹 Programar notificaciones para vacunas existentes
  Future<void> _scheduleExistingVaccines() async {
    try {
      final box = await Hive.openBox('porki_data');
      final allData = box.values.toList();
      
      final vacunas = allData.where((data) => 
        data is Map && data['type'] == 'vaccine'
      ).cast<Map<String, dynamic>>().toList();
      
      for (var vacuna in vacunas) {
        await NotificationService.scheduleVaccineReminders(vacuna);
      }
      
      print('💉 Notificaciones de vacunas programadas: ${vacunas.length}');
    } catch (e) {
      print('❌ Error programando vacunas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _checkingAuth 
        ? const SplashScreen()
        : const LoginScreen();
  }
}

// 🔹 Splash Screen mejorado con info de sync
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _syncStatus = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _checkSyncStatus();
  }

  Future<void> _checkSyncStatus() async {
    try {
      final syncService = SyncService();
      final status = await syncService.getSyncStatus();
      
      if (mounted) {
        setState(() {
          _syncStatus = 'Sincronizado: ${status['syncPercentage']}%';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = 'Preparando...';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pets, size: 60, color: Colors.pink),
            const SizedBox(height: 20),
            const Text(
              'My Porki',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.pink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _syncStatus,
              style: TextStyle(
                fontSize: 14,
                color: Colors.pink[700],
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.pink),
          ],
        ),
      ),
    );
  }
}