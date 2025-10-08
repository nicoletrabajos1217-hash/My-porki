import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:my_porki/backend/firebase_options.dart';
import 'frotend/screens/login_screen.dart';
import 'backend/services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 INICIANDO APP CON LIMPIEZA COMPLETA...');
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔥 LIMPIEZA NUCLEAR - FORZAR
  await Hive.initFlutter();
  
  // ELIMINAR TODAS LAS BOXES EXISTENTES
  try {
    await Hive.close(); // Cerrar todas las boxes primero
    await Hive.deleteBoxFromDisk('porki_users');
    print('✅ porki_users eliminado');
  } catch (e) {
    print('⚠️ Error eliminando porki_users: $e');
  }
  
  try {
    await Hive.deleteBoxFromDisk('porki_data');
    print('✅ porki_data eliminado');
  } catch (e) {
    print('⚠️ Error eliminando porki_data: $e');
  }

  // ELIMINAR TODO EL DIRECTORIO HIVE
  try {
    await Hive.deleteFromDisk();
    print('✅ Directorio Hive completo eliminado');
  } catch (e) {
    print('⚠️ Error eliminando directorio Hive: $e');
  }

  // REINICIALIZAR COMPLETAMENTE
  await Hive.initFlutter();
  
  // CREAR NUEVAS BOXES LIMPIAS
  await Hive.openBox('porki_data');
  await Hive.openBox('porki_users');
  
  print('🎉 HIVE COMPLETAMENTE LIMPIO - INICIANDO APP');

  
  runApp(const MyPorkiApp());
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
      home: const ConnectionHandler(),
    );
  }
}

class ConnectionHandler extends StatefulWidget {
  const ConnectionHandler({super.key});

  @override
  State<ConnectionHandler> createState() => _ConnectionHandlerState();
}

class _ConnectionHandlerState extends State<ConnectionHandler> {
  bool _isConnected = true;
  late final SyncService _syncService;

  @override
  void initState() {
    super.initState();
    _syncService = SyncService();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = result != ConnectivityResult.none;
    });

    if (_isConnected) {
      await _syncService.syncLocalData();
    }

    Connectivity().onConnectivityChanged.listen((status) async {
      final connected = status != ConnectivityResult.none;
      setState(() => _isConnected = connected);

      if (connected) {
        await _syncService.syncLocalData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isConnected
          ? const LoginScreen()
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.wifi_off, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    'Sin conexión a internet',
                    style: TextStyle(fontSize: 20),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Puedes seguir usando los datos guardados en tu dispositivo 🐷',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}