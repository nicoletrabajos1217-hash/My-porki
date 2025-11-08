import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> checkConnection() async {
  final dynamic result = await _connectivity.checkConnectivity();
    // La API de connectivity_plus puede devolver un ConnectivityResult
    // o List<ConnectivityResult> dependiendo de la plataforma/version.
    if (result is List) {
      return result.isNotEmpty && result.every((r) => r != ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  Stream<bool> get connectionStream async* {
    await for (final dynamic result in _connectivity.onConnectivityChanged) {
      if (result is List) {
        yield result.isNotEmpty && result.any((r) => r != ConnectivityResult.none);
      } else {
        yield result != ConnectivityResult.none;
      }
    }
  }
}