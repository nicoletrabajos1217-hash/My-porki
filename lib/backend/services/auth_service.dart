import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> loginUser({
    required String input,
    required String password,
  }) async {
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
      
      return userDataForHive;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> registerUser({
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
      
      await _saveUserLocally(userData, cred.user!.uid);

    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> _saveUserLocally(Map<String, dynamic> userData, String uid) async {
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
      };
      
      await box.put('current_user', userMap);
    } catch (e) {
      print('Error guardando usuario local: $e');
    }
  }

  Future<void> logout() async {
    try {
      final box = await Hive.openBox('porki_users');
      await box.delete('current_user');
      await _auth.signOut();
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final box = await Hive.openBox('porki_users');
      final localUser = box.get('current_user');
      
      if (localUser != null) {
        return Map<String, dynamic>.from(localUser);
      }

      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final userData = doc.data()!;
          await _saveUserLocally(userData, user.uid);
          return userData;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}