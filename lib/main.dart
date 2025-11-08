import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:my_porki/backend/firebase_options.dart';
import 'frotend/screens/login_screen.dart';
import 'backend/services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  developer.log(
    '🚀 INICIANDO APP CON LIMPIEZA COMPLETA...',
    name: 'my_porki.main',
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 🔥 LIMPIEZA NUCLEAR - FORZAR
  await Hive.initFlutter();

  // ELIMINAR TODAS LAS BOXES EXISTENTES
  try {
    await Hive.close(); // Cerrar todas las boxes primero
    await Hive.deleteBoxFromDisk('porki_users');
    developer.log('✅ porki_users eliminado', name: 'my_porki.main');
  } catch (e) {
    developer.log('⚠️ Error eliminando porki_users: $e', name: 'my_porki.main');
  }

  try {
    await Hive.deleteBoxFromDisk('porki_data');
    developer.log('✅ porki_data eliminado', name: 'my_porki.main');
  } catch (e) {
    developer.log('⚠️ Error eliminando porki_data: $e', name: 'my_porki.main');
  }

  // ELIMINAR TODO EL DIRECTORIO HIVE
  try {
    await Hive.deleteFromDisk();
    developer.log(
      '✅ Directorio Hive completo eliminado',
      name: 'my_porki.main',
    );
  } catch (e) {
    developer.log(
      '⚠️ Error eliminando directorio Hive: $e',
      name: 'my_porki.main',
    );
  }

  // REINICIALIZAR COMPLETAMENTE
  await Hive.initFlutter();

  // CREAR NUEVAS BOXES LIMPIAS
  await Hive.openBox('porki_data');
  await Hive.openBox('porki_users');

  developer.log(
    '🎉 HIVE COMPLETAMENTE LIMPIO - INICIANDO APP',
    name: 'my_porki.main',
  );

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
    final dynamic result = await Connectivity().checkConnectivity();
    setState(() {
      if (result is List) {
        _isConnected =
            result.isNotEmpty &&
            result.any((r) => r != ConnectivityResult.none);
      } else {
        _isConnected = result != ConnectivityResult.none;
      }
    });

    if (_isConnected) {
      await _syncService.syncLocalData();
    }

    Connectivity().onConnectivityChanged.listen((dynamic status) async {
      final bool connected;
      if (status is List) {
        connected =
            status.isNotEmpty &&
            status.any((r) => r != ConnectivityResult.none);
      } else {
        connected = status != ConnectivityResult.none;
      }
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
