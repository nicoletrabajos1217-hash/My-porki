import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const SettingsScreen({super.key, required this.userData});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  TextEditingController _usernameController = TextEditingController();
  TextEditingController _displayNameController = TextEditingController();
  TextEditingController _currentPasswordController = TextEditingController();
  TextEditingController _newPasswordController = TextEditingController();
  TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _showPasswordFields = false;
  User? _currentUser;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    print('🟡 INICIANDO _loadUserData()');

    setState(() {
      _isLoading = true;
    });

    try {
      _currentUser = _auth.currentUser;

      if (_currentUser == null) {
        print('❌ No hay usuario autenticado en _loadUserData');
        return;
      }

      print('✅ Usuario autenticado: ${_currentUser!.uid}');
      print('✅ Email: ${_currentUser!.email}');
      print('✅ DisplayName: ${_currentUser!.displayName}');

      // INTENTAR CARGAR DE FIRESTORE
      print('🔍 Cargando datos de Firestore...');
      final userDoc = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists) {
        print('✅ Documento encontrado en Firestore');
        _userData = userDoc.data()!;
        print('📊 Datos cargados: $_userData');

        _usernameController.text = _userData!['username'] ?? '';
        _displayNameController.text =
            _userData!['name'] ?? _currentUser!.displayName ?? '';

        print('📝 Username cargado: ${_usernameController.text}');
        print('📝 DisplayName cargado: ${_displayNameController.text}');
      } else {
        print('⚠️ Documento NO existe en Firestore');
        print('📝 Usando datos del widget: ${widget.userData}');

        _usernameController.text = widget.userData['username'] ?? '';
        _displayNameController.text =
            widget.userData['name'] ?? _currentUser!.displayName ?? '';
      }
    } catch (e) {
      print('❌ Error en _loadUserData: $e');
      print('📝 Usando datos del widget como fallback');

      _usernameController.text = widget.userData['username'] ?? '';
      _displayNameController.text =
          widget.userData['name'] ?? _currentUser?.displayName ?? '';
    } finally {
      print('🏁 FINALIZANDO _loadUserData()');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // MÉTODO ACTUALIZADO CON MANEJO ROBUSTO DE ERRORES
  Future<void> _updateProfile() async {
    print('🟡 INICIANDO _updateProfile()');

    if (!_formKey.currentState!.validate()) {
      print('❌ Validación de formulario falló');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // VERIFICAR USUARIO AUTENTICADO
      print('🔍 Verificando usuario autenticado...');
      if (_currentUser == null) {
        print('❌ _currentUser es NULL');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No hay usuario autenticado'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      print('✅ Usuario autenticado: ${_currentUser!.uid}');
      print('✅ Email: ${_currentUser!.email}');

      final newUsername = _usernameController.text.trim();
      final currentUsername = widget.userData['username'] ?? '';

      print('📝 Username actual: $currentUsername');
      print('📝 Nuevo username: $newUsername');

      if (newUsername.isEmpty) {
        print('❌ Username vacío');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El nombre de usuario no puede estar vacío'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 1. VALIDAR SI USERNAME CAMBIÓ
      if (newUsername != currentUsername) {
        print('🔄 Username cambió, validando unicidad...');

        try {
          final usernameQuery = await _firestore
              .collection('users')
              .where('username', isEqualTo: newUsername)
              .where('uid', isNotEqualTo: _currentUser!.uid)
              .limit(1)
              .get();

          print('📊 Resultado query: ${usernameQuery.docs.length} documentos');

          if (usernameQuery.docs.isNotEmpty) {
            print('❌ Username ya existe');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'El nombre de usuario "$newUsername" ya está en uso',
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
          print('✅ Username disponible');
        } catch (queryError) {
          print('❌ Error en query de validación: $queryError');
          // Continuar a pesar del error en la validación
        }
      }

      // 2. PREPARAR DATOS DE ACTUALIZACIÓN
      final displayName = _displayNameController.text.trim().isEmpty
          ? newUsername
          : _displayNameController.text.trim();

      final updateData = {
        'username': newUsername,
        'name': displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      print('📦 Datos para actualizar:');
      print('  - username: ${updateData['username']}');
      print('  - name: ${updateData['name']}');
      print('  - uid: ${_currentUser!.uid}');
      print('  - email: ${_currentUser!.email}');

      // 3. VERIFICAR QUE EL DOCUMENTO EXISTA
      print('🔍 Verificando existencia del documento...');
      final userDoc = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (!userDoc.exists) {
        print('❌ Documento no existe. Creando...');
        // Si no existe, crear el documento
        await _firestore.collection('users').doc(_currentUser!.uid).set({
          'uid': _currentUser!.uid,
          'email': _currentUser!.email,
          'username': newUsername,
          'name': displayName,
          'role': widget.userData['role'] ?? 'colaborador',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✅ Documento creado exitosamente');
      } else {
        print('✅ Documento existe, actualizando...');
        // Si existe, actualizar
        await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .update(updateData);
        print('✅ Documento actualizado exitosamente');
      }

      // 4. ACTUALIZAR DISPLAYNAME EN AUTH (OPCIONAL)
      try {
        print('🔄 Actualizando displayName en Auth...');
        await _currentUser!.updateDisplayName(displayName);
        print('✅ DisplayName en Auth actualizado');
      } catch (authError) {
        print('⚠️ Error actualizando Auth (no crítico): $authError');
      }

      // 5. MOSTRAR ÉXITO
      print('🎉 Operación completada exitosamente');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Perfil actualizado correctamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // 6. RETORNAR DATOS ACTUALIZADOS
      final resultData = {
        'uid': _currentUser!.uid,
        'email': _currentUser!.email,
        'username': newUsername,
        'name': displayName,
        'role': widget.userData['role'] ?? 'colaborador',
        'isActive': true,
      };

      print('📤 Retornando datos: $resultData');
      Navigator.pop(context, resultData);
    } on FirebaseException catch (e) {
      // ERRORES DE FIREBASE
      print('🔥 FIREBASE EXCEPTION:');
      print('  Código: ${e.code}');
      print('  Mensaje: ${e.message}');
      print('  Detalles: ${e.toString()}');

      String errorMessage = 'Error de Firebase';
      if (e.code == 'permission-denied') {
        errorMessage = 'Permiso denegado. Revisa las reglas de Firestore.';
      } else if (e.code == 'not-found') {
        errorMessage = 'Documento no encontrado.';
      } else if (e.code == 'unavailable') {
        errorMessage = 'Firestore no disponible. Revisa tu conexión.';
      } else {
        errorMessage = 'Error (${e.code}): ${e.message}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      // ERROR GENERAL
      print('❌ ERROR GENERAL:');
      print('  Tipo: ${e.runtimeType}');
      print('  Mensaje: $e');
      print('  Stack: ${e.toString()}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      print('🏁 FINALIZANDO _updateProfile()');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // MÉTODO PARA CAMBIAR CONTRASEÑA
  Future<void> _updatePassword() async {
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Las contraseñas no coinciden'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_newPasswordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('La nueva contraseña debe tener al menos 6 caracteres'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final credential = EmailAuthProvider.credential(
        email: _currentUser!.email!,
        password: _currentPasswordController.text,
      );

      await _currentUser!.reauthenticateWithCredential(credential);

      await _currentUser!.updatePassword(_newPasswordController.text);

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showPasswordFields = false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contraseña actualizada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Error al cambiar contraseña';
      if (e.code == 'wrong-password') {
        errorMessage = 'La contraseña actual es incorrecta';
      } else if (e.code == 'weak-password') {
        errorMessage = 'La nueva contraseña es muy débil';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configuración'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TARJETA DE PERFIL
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundImage: AssetImage(
                            'assets/images/LogoAlex.png',
                          ),
                        ),
                        title: Text(
                          _userData?['name'] ??
                              widget.userData['username'] ??
                              'Usuario',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        subtitle: Text(
                          'Usuario: ${_userData?['username'] ?? widget.userData['username'] ?? ''}\n'
                          'Email: ${_currentUser?.email ?? widget.userData['email'] ?? ''}',
                        ),
                      ),
                    ),

                    SizedBox(height: 30),

                    // SECCIÓN: INFORMACIÓN PERSONAL
                    Text(
                      'Información Personal',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 15),

                    // CAMPO: USERNAME (PARA LOGIN)
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Nombre de usuario (para login)',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[50],
                        helperText:
                            'Este es el nombre que usas para iniciar sesión',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Por favor ingresa tu nombre de usuario';
                        }
                        if (value.length < 3) {
                          return 'Mínimo 3 caracteres';
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: 15),

                    // CAMPO: NOMBRE PARA MOSTRAR (OPCIONAL)
                    TextFormField(
                      controller: _displayNameController,
                      decoration: InputDecoration(
                        labelText: 'Nombre para mostrar (opcional)',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey[50],
                        helperText: 'Este es el nombre que verán los demás',
                      ),
                    ),

                    SizedBox(height: 20),

                    // BOTÓN GUARDAR
                    ElevatedButton.icon(
                      onPressed: _updateProfile,
                      icon: Icon(Icons.save),
                      label: Text('Guardar Cambios'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),

                    SizedBox(height: 40),

                    // SECCIÓN: SEGURIDAD
                    Row(
                      children: [
                        Text(
                          'Seguridad',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Spacer(),
                        IconButton(
                          icon: Icon(
                            _showPasswordFields
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _showPasswordFields = !_showPasswordFields;
                            });
                          },
                          tooltip: _showPasswordFields
                              ? 'Ocultar campos de contraseña'
                              : 'Cambiar contraseña',
                        ),
                      ],
                    ),

                    SizedBox(height: 15),

                    if (_showPasswordFields) ...[
                      TextFormField(
                        controller: _currentPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Contraseña Actual',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (_showPasswordFields &&
                              (value == null || value.isEmpty)) {
                            return 'Ingresa tu contraseña actual';
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: 15),

                      TextFormField(
                        controller: _newPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Nueva Contraseña',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey[50],
                          helperText: 'Mínimo 6 caracteres',
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (_showPasswordFields &&
                              (value == null || value.isEmpty)) {
                            return 'Ingresa la nueva contraseña';
                          }
                          if (_showPasswordFields && value!.length < 6) {
                            return 'Mínimo 6 caracteres';
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: 15),

                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Confirmar Nueva Contraseña',
                          prefixIcon: Icon(Icons.lock_reset),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (_showPasswordFields &&
                              (value == null || value.isEmpty)) {
                            return 'Confirma la nueva contraseña';
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: 20),

                      ElevatedButton.icon(
                        onPressed: _updatePassword,
                        icon: Icon(Icons.security),
                        label: Text('Cambiar Contraseña'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 50),
                          backgroundColor: Colors.orange,
                        ),
                      ),

                      SizedBox(height: 10),

                      TextButton.icon(
                        onPressed: () {
                          _showResetPasswordDialog();
                        },
                        icon: Icon(Icons.help_outline),
                        label: Text('¿Olvidaste tu contraseña actual?'),
                      ),
                    ],

                    SizedBox(height: 40),

                    // INFORMACIÓN DE LA CUENTA
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Información de la Cuenta',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 10),
                            ListTile(
                              leading: Icon(Icons.email, color: Colors.grey),
                              title: Text('Email'),
                              subtitle: Text(
                                _currentUser?.email ??
                                    widget.userData['email'] ??
                                    'No disponible',
                              ),
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.date_range,
                                color: Colors.grey,
                              ),
                              title: Text('Cuenta creada'),
                              subtitle: Text(
                                _currentUser?.metadata.creationTime
                                        ?.toString()
                                        .split(' ')[0] ??
                                    'No disponible',
                              ),
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.verified_user,
                                color: _currentUser?.emailVerified == true
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              title: Text('Verificación de email'),
                              subtitle: Text(
                                _currentUser?.emailVerified == true
                                    ? 'Verificado'
                                    : 'No verificado',
                              ),
                              trailing: _currentUser?.emailVerified == false
                                  ? TextButton(
                                      onPressed: () {
                                        _sendVerificationEmail();
                                      },
                                      child: Text('Verificar'),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // DIÁLOGO RECUPERAR CONTRASEÑA
  void _showResetPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Recuperar Contraseña'),
        content: Text(
          'Se enviará un enlace de recuperación a tu email: ${_currentUser?.email ?? widget.userData['email']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _auth.sendPasswordResetEmail(
                  email: _currentUser?.email ?? widget.userData['email'] ?? '',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Enlace enviado a tu email'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text('Enviar Enlace'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendVerificationEmail() async {
    try {
      await _currentUser!.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Correo de verificación enviado'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar verificación: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
