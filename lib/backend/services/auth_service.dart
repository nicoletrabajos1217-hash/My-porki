import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ✅ Verificar si el usuario está logueado
  static Future<bool> isLoggedIn() async {
    try {
      // Verificar si hay usuario en Firebase Auth
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        return true;
      }
      
      // Verificar si hay usuario guardado localmente
      final box = await Hive.openBox('porki_users');
      final localUser = box.get('current_user');
      return localUser != null;
    } catch (e) {
      developer.log('❌ Error verificando autenticación: $e', name: 'my_porki.auth');
      return false;
    }
  }

  /// ✅ Login con email o username - CON SOPORTE OFFLINE
  static Future<Map<String, dynamic>> loginUser({
    required String input,
    required String password,
  }) async {
    try {
      // Verificar conexión a internet
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      final tieneInternet = result.isNotEmpty && result.first != ConnectivityResult.none;

      if (tieneInternet) {
        // ✅ CON INTERNET: Usar Firebase
        return await _loginWithFirebase(input, password);
      } else {
        // ✅ SIN INTERNET: Usar Hive local
        return await _loginOffline(input, password);
      }
    } catch (e) {
      developer.log('❌ Error en login: $e', name: 'my_porki.auth');
      throw Exception(e.toString());
    }
  }

  /// ✅ Login usando Firebase (requiere internet)
  static Future<Map<String, dynamic>> _loginWithFirebase(
    String input,
    String password,
  ) async {
    try {
      User? user;
      String userEmail = input;

      // Si el input no es un email, buscar username
      if (!input.contains('@')) {
        final query = await _firestore
            .collection('users')
            .where('username', isEqualTo: input)
            .limit(1)
            .get();

        if (query.docs.isEmpty) {
          throw Exception('Usuario no encontrado');
        }

        userEmail = query.docs.first.data()['email'];
      }

      // Iniciar sesión con Firebase Auth
      final credential = await _auth.signInWithEmailAndPassword(
        email: userEmail,
        password: password,
      );
      user = credential.user;

      if (user == null) throw Exception('Error al iniciar sesión');

      // Obtener datos del usuario de Firestore
      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        throw Exception('Datos de usuario no encontrados');
      }

      final userData = doc.data()!;
      final userDataForHive = Map<String, dynamic>.from(userData);

      // Guardar usuario localmente para login offline futuro
      await _saveUserLocally(userDataForHive, user.uid);

      developer.log('✅ Usuario logueado con Firebase: ${userData['username']}', name: 'my_porki.auth');
      return userDataForHive;
    } catch (e) {
      developer.log('❌ Error en login Firebase: $e', name: 'my_porki.auth');
      throw Exception(e.toString());
    }
  }

  /// ✅ Login offline usando Hive (sin internet)
  static Future<Map<String, dynamic>> _loginOffline(
    String input,
    String password,
  ) async {
    try {
      final box = await Hive.openBox('porki_users');

      // Buscar usuario en Hive por email o username
      Map<String, dynamic>? foundUser;

      for (var key in box.keys) {
        final user = box.get(key);
        if (user is Map) {
          final email = user['email']?.toString() ?? '';
          final username = user['username']?.toString() ?? '';
          final storedPassword = user['password_hash']?.toString() ?? '';

          // Verificar si coincide email o username
          if ((email == input || username == input) && storedPassword.isNotEmpty) {
            // Verificar contraseña (simple comparación SHA256)
            final passwordHash = _hashPassword(password);
            if (storedPassword == passwordHash) {
              foundUser = Map<String, dynamic>.from(user);
              break;
            }
          }
        }
      }

      if (foundUser == null) {
        throw Exception('Usuario o contraseña incorrectos (modo offline)');
      }

      // Actualizar último login
      foundUser['lastLogin'] = DateTime.now().millisecondsSinceEpoch;
      await box.put('current_user', foundUser);

      developer.log('✅ Usuario logueado OFFLINE: ${foundUser['username']}', name: 'my_porki.auth');
      return foundUser;
    } catch (e) {
      developer.log('❌ Error en login offline: $e', name: 'my_porki.auth');
      throw Exception('Error en autenticación offline: ${e.toString()}');
    }
  }

  /// ✅ Hash de contraseña (SHA256)
  static String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// ✅ Registrar nuevo usuario
  static Future<void> registerUser({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      // Verificar si el username ya existe
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        throw Exception('El nombre de usuario ya está en uso');
      }

      // Crear usuario en Firebase Auth
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Preparar datos del usuario
      final userData = {
        'username': username,
        'email': email,
        'role': role,
        'uid': cred.user!.uid,
        'createdAt': Timestamp.now(),
        'isActive': true,
      };

      // Guardar en Firestore
      await _firestore.collection('users').doc(cred.user!.uid).set(userData);

      // Guardar localmente con hash de contraseña
      final userDataWithPassword = {
        ...userData,
        'password_hash': _hashPassword(password), // Guardar hash para login offline
      };
      await _saveUserLocally(userDataWithPassword, cred.user!.uid);

      developer.log('✅ Usuario registrado: $username', name: 'my_porki.auth');
    } catch (e) {
      developer.log('❌ Error en registro: $e', name: 'my_porki.auth');
      throw Exception(e.toString());
    }
  }

  /// ✅ Guardar usuario localmente en Hive
  static Future<void> _saveUserLocally(Map<String, dynamic> userData, String uid) async {
    try {
      final box = await Hive.openBox('porki_users');
      
      final userMap = {
        'id': uid,
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'role': userData['role'] ?? 'colaborador',
        'createdAt': userData['createdAt'] != null 
            ? (userData['createdAt'] as Timestamp).millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
        'isActive': userData['isActive'] ?? true,
        'synced': true,
        'lastLogin': DateTime.now().millisecondsSinceEpoch,
      };
      
      await box.put('current_user', userMap);
      developer.log('✅ Usuario guardado localmente', name: 'my_porki.auth');
    } catch (e) {
      developer.log('❌ Error guardando usuario local: $e', name: 'my_porki.auth');
      throw Exception('Error guardando datos locales');
    }
  }

  /// ✅ Cerrar sesión
  static Future<void> logout() async {
    try {
      final box = await Hive.openBox('porki_users');
      await box.delete('current_user');
      await _auth.signOut();
      developer.log('✅ Sesión cerrada correctamente', name: 'my_porki.auth');
    } catch (e) {
      developer.log('❌ Error cerrando sesión: $e', name: 'my_porki.auth');
      throw Exception('Error cerrando sesión');
    }
  }

  /// ✅ Obtener usuario actual
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      // Primero buscar localmente
      final box = await Hive.openBox('porki_users');
      final localUser = box.get('current_user');
      
      if (localUser != null) {
        developer.log('✅ Usuario obtenido localmente', name: 'my_porki.auth');
        return Map<String, dynamic>.from(localUser);
      }

      // Si no hay local, buscar en Firebase
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final userData = doc.data()!;
          await _saveUserLocally(userData, user.uid);
          developer.log('✅ Usuario obtenido de Firebase', name: 'my_porki.auth');
          return userData;
        }
      }

      developer.log('ℹ️ No hay usuario logueado', name: 'my_porki.auth');
      return null;
    } catch (e) {
      developer.log('❌ Error obteniendo usuario: $e', name: 'my_porki.auth');
      return null;
    }
  }

  /// ✅ Enviar email de verificación
  static Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        developer.log('✅ Email de verificación enviado', name: 'my_porki.auth');
      }
    } catch (e) {
      developer.log('❌ Error enviando email de verificación: $e', name: 'my_porki.auth');
      throw Exception('Error enviando email de verificación');
    }
  }

  /// ✅ Restablecer contraseña
  static Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      developer.log('✅ Email de restablecimiento enviado', name: 'my_porki.auth');
    } catch (e) {
      developer.log('❌ Error restableciendo contraseña: $e', name: 'my_porki.auth');
      throw Exception('Error restableciendo contraseña');
    }
  }

  /// ✅ Actualizar perfil de usuario
  static Future<void> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await user.updatePhotoURL(photoURL);
        
        // Actualizar también en Firestore
        await _firestore.collection('users').doc(user.uid).update({
          if (displayName != null) 'displayName': displayName,
          if (photoURL != null) 'photoURL': photoURL,
          'updatedAt': Timestamp.now(),
        });

        // Actualizar localmente
        final currentUser = await getCurrentUser();
        if (currentUser != null) {
          await _saveUserLocally({
            ...currentUser,
            if (displayName != null) 'displayName': displayName,
            if (photoURL != null) 'photoURL': photoURL,
          }, user.uid);
        }

        developer.log('✅ Perfil actualizado', name: 'my_porki.auth');
      }
    } catch (e) {
      developer.log('❌ Error actualizando perfil: $e', name: 'my_porki.auth');
      throw Exception('Error actualizando perfil');
    }
  }

  /// ✅ Verificar si el email está verificado
  static bool isEmailVerified() {
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// ✅ Obtener el UID del usuario actual
  static String? getCurrentUID() {
    return _auth.currentUser?.uid;
  }

  /// ✅ Eliminar cuenta de usuario
  static Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Eliminar de Firestore
        await _firestore.collection('users').doc(user.uid).delete();
        
        // Eliminar localmente
        final box = await Hive.openBox('porki_users');
        await box.delete('current_user');
        
        // Eliminar cuenta de Firebase Auth
        await user.delete();
        
        developer.log('✅ Cuenta eliminada correctamente', name: 'my_porki.auth');
      }
    } catch (e) {
      developer.log('❌ Error eliminando cuenta: $e', name: 'my_porki.auth');
      throw Exception('Error eliminando cuenta');
    }
  }

  /// ✅ Escuchar cambios de autenticación
  static Stream<User?> get authStateChanges {
    return _auth.authStateChanges();
  }

  /// ✅ Verificar si el usuario es administrador
  static Future<bool> isAdmin() async {
    try {
      final user = await getCurrentUser();
      return user != null && user['role'] == 'admin';
    } catch (e) {
      developer.log('❌ Error verificando rol: $e', name: 'my_porki.auth');
      return false;
    }
  }

  /// ✅ Actualizar último acceso
  static Future<void> updateLastAccess() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'lastAccess': Timestamp.now(),
        });

        // Actualizar localmente
        final box = await Hive.openBox('porki_users');
        final localUser = box.get('current_user');
        if (localUser != null) {
          final updatedUser = Map<String, dynamic>.from(localUser);
          updatedUser['lastLogin'] = DateTime.now().millisecondsSinceEpoch;
          await box.put('current_user', updatedUser);
        }
      }
    } catch (e) {
      developer.log('❌ Error actualizando último acceso: $e', name: 'my_porki.auth');
    }
  }
}