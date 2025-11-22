import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:my_porki/backend/firebase_options.dart';
import 'frotend/screens/login_screen.dart';
import 'frotend/screens/home_screen.dart';
import 'backend/services/sync_service.dart';
import 'backend/services/notification_service.dart';
import 'backend/services/sow_service.dart';
import 'backend/services/auth_service.dart';
import 'backend/services/connectivity_service.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔹 Inicialización Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔹 Inicialización Hive
  await Hive.initFlutter();
  await Hive.openBox('porki_data');
  await Hive.openBox('porki_users');
  await Hive.openBox('porki_sync');

  // 🔹 Inicializar servicios
  await NotificationService.initialize();
  await SowService.initialize();

  // 🔹 Iniciar sincronización en background
  _startBackgroundSync();

  // 🔹 Error Widget para depuración UI
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Error inesperado:\n${details.exceptionAsString()}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  };

  runApp(const MyPorkiApp());
}

// 🔹 Sincronización background
void _startBackgroundSync() {
  final syncService = SyncService();
  final connectivityService = ConnectivityService();

  // Sincronización inicial
  Timer(const Duration(seconds: 10), () async {
    if (await connectivityService.checkConnection()) {
      print('🔄 Sincronización inicial...');
      await syncService.syncAllPending();
      await NotificationService.scheduleAllNotifications();
    }
  });

  // Sincronización periódica cada 1 minuto
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (await connectivityService.checkConnection()) {
      await syncService.syncAllPending();
      await NotificationService.scheduleAllNotifications();
    }
  });

  // Sincronización al restablecer conexión
  connectivityService.connectionStream.listen((hasConnection) async {
    if (hasConnection) {
      await syncService.syncAllPending();
      await NotificationService.scheduleAllNotifications();
      print('🌐 Conexión restaurada - sincronización completada');
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
  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<bool>? _connectivitySubscription;

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

  Future<void> _initializeApp() async {
    await Future.wait([
      _checkAuthentication(),
      _initializeBackgroundServices(),
    ]);
  }

  Future<void> _checkAuthentication() async {
    final isLoggedIn = await AuthService.isLoggedIn();
    await Future.delayed(const Duration(milliseconds: 800)); // Splash breve

    if (!mounted) return;

    setState(() => _checkingAuth = false);

    if (isLoggedIn) {
      final userData = await AuthService.getCurrentUser();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            userData: userData ?? {'username': 'Usuario', 'email': '', 'role': 'usuario'},
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _initializeBackgroundServices() async {
    try {
      if (await _connectivityService.checkConnection()) {
        await _syncService.downloadAllSowsFromFirebase();
        await _syncService.syncAllPending();
      }

      // 🔹 Programar todas las notificaciones: partos, vacunas y preñez
      await NotificationService.scheduleAllNotifications();

      _connectivitySubscription = _connectivityService.connectionStream.listen((hasConnection) async {
        if (hasConnection) {
          await _syncService.syncAllPending();
          await NotificationService.scheduleAllNotifications();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Sincronización completada'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      });
    } catch (e) {
      print('❌ Error inicializando servicios: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _checkingAuth ? const SplashScreen() : const LoginScreen();
  }
}

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
          _syncStatus = 'Sincronizado: ${status['syncPercentage'] ?? 0}%';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _syncStatus = 'Preparando...');
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.pink),
            ),
            const SizedBox(height: 10),
            Text(
              _syncStatus,
              style: TextStyle(fontSize: 14, color: Colors.pink[700]),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Colors.pink),
          ],
        ),
      ),
    );
  }
}
