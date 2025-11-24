import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'connectivity_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final ConnectivityService _connectivityService = ConnectivityService();

  /// ✅ Verificar si el usuario está logueado
  static Future<bool> isLoggedIn() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        return true;
      }

      final box = await Hive.openBox('porki_users');
      final localUser = box.get('current_user');
      return localUser != null;
    } catch (e) {
      developer.log(
        '❌ Error verificando autenticación: $e',
        name: 'my_porki.auth',
      );
      return false;
    }
  }

  /// ✅ Login con email o username - CON SOPORTE OFFLINE
  static Future<Map<String, dynamic>> loginUser({
    required String input,
    required String password,
  }) async {
    try {
      final tieneInternet = await _connectivityService.checkConnection();

      if (tieneInternet) {
        return await _loginWithFirebase(input, password);
      } else {
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

      final credential = await _auth.signInWithEmailAndPassword(
        email: userEmail,
        password: password,
      );
      user = credential.user;

      if (user == null) throw Exception('Error al iniciar sesión');

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        throw Exception('Datos de usuario no encontrados');
      }

      final userData = doc.data()!;
      final userDataForHive = Map<String, dynamic>.from(userData);

      await _saveUserLocally(userDataForHive, user.uid);

      developer.log(
        '✅ Usuario logueado con Firebase: ${userData['username']}',
        name: 'my_porki.auth',
      );
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
      Map<String, dynamic>? foundUser;

      for (var key in box.keys) {
        final user = box.get(key);
        if (user is Map) {
          final email = user['email']?.toString() ?? '';
          final username = user['username']?.toString() ?? '';
          final storedPassword = user['password_hash']?.toString() ?? '';

          if ((email == input || username == input) &&
              storedPassword.isNotEmpty) {
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

      foundUser['lastLogin'] = DateTime.now().millisecondsSinceEpoch;
      await box.put('current_user', foundUser);

      developer.log(
        '✅ Usuario logueado OFFLINE: ${foundUser['username']}',
        name: 'my_porki.auth',
      );
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
      final usernameQuery = await _firestore
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        throw Exception('El nombre de usuario ya está en uso');
      }

      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userData = {
        'username': username,
        'email': email,
        'role': role,
        'uid': cred.user!.uid,
        'createdAt': Timestamp.now(),
        'isActive': true,
      };

      await _firestore.collection('users').doc(cred.user!.uid).set(userData);

      final userDataWithPassword = {
        ...userData,
        'password_hash': _hashPassword(password),
      };
      await _saveUserLocally(userDataWithPassword, cred.user!.uid);

      developer.log('✅ Usuario registrado: $username', name: 'my_porki.auth');
    } catch (e) {
      developer.log('❌ Error en registro: $e', name: 'my_porki.auth');
      throw Exception(e.toString());
    }
  }

  /// ✅ Guardar usuario localmente en Hive
  static Future<void> _saveUserLocally(
    Map<String, dynamic> userData,
    String uid,
  ) async {
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
      developer.log(
        '❌ Error guardando usuario local: $e',
        name: 'my_porki.auth',
      );
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
      final box = await Hive.openBox('porki_users');
      final localUser = box.get('current_user');

      if (localUser != null) {
        developer.log('✅ Usuario obtenido localmente', name: 'my_porki.auth');
        return Map<String, dynamic>.from(localUser);
      }

      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final userData = doc.data()!;
          await _saveUserLocally(userData, user.uid);
          developer.log(
            '✅ Usuario obtenido de Firebase',
            name: 'my_porki.auth',
          );
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
      developer.log(
        '❌ Error enviando email de verificación: $e',
        name: 'my_porki.auth',
      );
      throw Exception('Error enviando email de verificación');
    }
  }

  /// ✅ RECUPERACIÓN DE CONTRASEÑA - VERSIÓN CON AUTORREPARACIÓN
  static Future<Map<String, dynamic>> sendPasswordResetEmail(
    String email,
  ) async {
    try {
      developer.log(
        '🔄 INICIANDO RECUPERACIÓN PARA: $email',
        name: 'my_porki.auth',
      );

      // 1. Verificar conexión
      final tieneInternet = await _connectivityService.checkConnection();
      if (!tieneInternet) {
        return {
          'success': false,
          'message':
              'Se requiere conexión a internet para recuperar la contraseña',
        };
      }

      // 2. Verificar en Firestore
      developer.log('🔍 Buscando en Firestore: $email', name: 'my_porki.auth');
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (emailQuery.docs.isEmpty) {
        developer.log('❌ NO encontrado en Firestore', name: 'my_porki.auth');
        return {
          'success': false,
          'message': 'No existe una cuenta con este correo electrónico',
        };
      }

      final userData = emailQuery.docs.first.data();
      final username = userData['username'] ?? 'Usuario';
      developer.log(
        '✅ Encontrado en Firestore: $username',
        name: 'my_porki.auth',
      );

      // 3. Intentar enviar email directamente
      developer.log('📧 Intentando enviar email...', name: 'my_porki.auth');

      try {
        await _auth.sendPasswordResetEmail(email: email);
        developer.log('✅ EMAIL ENVIADO EXITOSAMENTE', name: 'my_porki.auth');

        return {
          'success': true,
          'message':
              'Se ha enviado un enlace de recuperación a $email. Revisa tu bandeja de entrada y carpeta de spam.',
          'email': email,
          'username': username,
        };
      } on FirebaseAuthException catch (e) {
        // 4. SI FALLA POR USER-NOT-FOUND -> REPARAR AUTOMÁTICAMENTE
        if (e.code == 'user-not-found') {
          developer.log(
            '⚠️ USUARIO HUÉRFANO DETECTADO. REPARANDO AUTOMÁTICAMENTE...',
            name: 'my_porki.auth',
          );

          final repairResult = await _autoRepairUser(email, userData);

          if (repairResult['success'] == true) {
            developer.log(
              '✅ USUARIO REPARADO. REINTENTANDO ENVÍO DE EMAIL...',
              name: 'my_porki.auth',
            );

            // Reintentar enviar el email después de reparar
            await _auth.sendPasswordResetEmail(email: email);

            return {
              'success': true,
              'message':
                  '✅ Se ha enviado un enlace de recuperación a $email. (Usuario reparado automáticamente)',
              'email': email,
              'username': username,
              'repaired': true,
            };
          } else {
            return {
              'success': false,
              'message':
                  '❌ El usuario necesita ser reparado manualmente. Error: ${repairResult['message']}',
            };
          }
        }

        // Para otros errores de Firebase
        String errorMessage;
        switch (e.code) {
          case 'invalid-email':
            errorMessage = 'El formato del email no es válido';
            break;
          case 'network-request-failed':
            errorMessage = 'Error de conexión a internet';
            break;
          case 'too-many-requests':
            errorMessage = 'Demasiados intentos. Espera unos minutos';
            break;
          case 'operation-not-allowed':
            errorMessage =
                'La recuperación de contraseña no está habilitada para esta aplicación';
            break;
          default:
            errorMessage = 'Error al enviar el email: ${e.message}';
        }

        return {'success': false, 'message': errorMessage};
      }
    } catch (e) {
      developer.log('❌ ERROR INESPERADO: $e', name: 'my_porki.auth');
      return {'success': false, 'message': 'Error inesperado: $e'};
    }
  }

  /// 🔧 REPARACIÓN AUTOMÁTICA DE USUARIO HUÉRFANO
  static Future<Map<String, dynamic>> _autoRepairUser(
    String email,
    Map<String, dynamic> userData,
  ) async {
    try {
      developer.log(
        '🛠️ REPARACIÓN AUTOMÁTICA PARA: $email',
        name: 'my_porki.auth',
      );

      final username = userData['username'] ?? 'Usuario';
      final tempPassword = _generateTempPassword();

      // Crear usuario en Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );

      final newUid = userCredential.user!.uid;

      // Actualizar Firestore con nuevo UID
      await _firestore.collection('users').doc(newUid).set({
        ...userData,
        'uid': newUid,
        'updatedAt': Timestamp.now(),
        'authRepaired': true,
      });

      developer.log(
        '✅ USUARIO REPARADO: $email -> $newUid',
        name: 'my_porki.auth',
      );

      return {'success': true, 'message': 'Usuario reparado exitosamente'};
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // El usuario ya existe en Auth (caso raro)
        developer.log('ℹ️ Usuario ya existe en Auth', name: 'my_porki.auth');
        return {'success': true, 'message': 'Usuario ya existía en Auth'};
      }

      developer.log(
        '❌ Error reparando usuario: ${e.code}',
        name: 'my_porki.auth',
      );
      return {'success': false, 'message': 'Error: ${e.code}'};
    } catch (e) {
      developer.log('❌ Error inesperado reparando: $e', name: 'my_porki.auth');
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  /// ✅ Restablecer contraseña (método existente - manteniendo compatibilidad)
  static Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      developer.log(
        '✅ Email de restablecimiento enviado',
        name: 'my_porki.auth',
      );
    } catch (e) {
      developer.log(
        '❌ Error restableciendo contraseña: $e',
        name: 'my_porki.auth',
      );
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

        await _firestore.collection('users').doc(user.uid).update({
          if (displayName != null) 'displayName': displayName,
          if (photoURL != null) 'photoURL': photoURL,
          'updatedAt': Timestamp.now(),
        });

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
        await _firestore.collection('users').doc(user.uid).delete();

        final box = await Hive.openBox('porki_users');
        await box.delete('current_user');

        await user.delete();

        developer.log(
          '✅ Cuenta eliminada correctamente',
          name: 'my_porki.auth',
        );
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

        final box = await Hive.openBox('porki_users');
        final localUser = box.get('current_user');
        if (localUser != null) {
          final updatedUser = Map<String, dynamic>.from(localUser);
          updatedUser['lastLogin'] = DateTime.now().millisecondsSinceEpoch;
          await box.put('current_user', updatedUser);
        }
      }
    } catch (e) {
      developer.log(
        '❌ Error actualizando último acceso: $e',
        name: 'my_porki.auth',
      );
    }
  }

  /// ✅ Verificar si un email existe en el sistema
  static Future<bool> checkEmailExists(String email) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      developer.log('❌ Error verificando email: $e', name: 'my_porki.auth');
      return false;
    }
  }

  /// 🔧 MÉTODO PARA REPARAR USUARIOS HUÉRFANOS (Para administradores)
  static Future<Map<String, dynamic>> fixOrphanedUser(String email) async {
    try {
      developer.log(
        '🛠️ REPARANDO USUARIO HUÉRFANO: $email',
        name: 'my_porki.auth',
      );

      final firestoreQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (firestoreQuery.docs.isEmpty) {
        return {
          'success': false,
          'message': 'Usuario no encontrado en Firestore',
        };
      }

      final userData = firestoreQuery.docs.first.data();
      final username = userData['username'] ?? 'Usuario';
      final tempPassword = _generateTempPassword();

      try {
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: tempPassword,
        );

        final newUid = userCredential.user!.uid;

        await _firestore.collection('users').doc(newUid).set({
          ...userData,
          'uid': newUid,
          'updatedAt': Timestamp.now(),
          'authFixed': true,
        });

        await _auth.sendPasswordResetEmail(email: email);

        developer.log(
          '✅ USUARIO REPARADO: $email -> $newUid',
          name: 'my_porki.auth',
        );

        return {
          'success': true,
          'message':
              'Usuario reparado exitosamente. Se ha enviado email de recuperación.',
          'email': email,
          'username': username,
        };
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // El usuario ya existe en Auth, solo enviar email
          await _auth.sendPasswordResetEmail(email: email);
          return {
            'success': true,
            'message':
                'El usuario ya existe en Auth. Se ha enviado email de recuperación.',
            'email': email,
            'username': username,
          };
        }
        rethrow;
      }
    } catch (e) {
      developer.log('❌ ERROR REPARANDO USUARIO: $e', name: 'my_porki.auth');
      return {'success': false, 'message': 'Error reparando usuario: $e'};
    }
  }

  /// 🔑 Generar contraseña temporal
  static String _generateTempPassword() {
    final random = Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%';
    return String.fromCharCodes(
      Iterable.generate(
        16,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }
}
