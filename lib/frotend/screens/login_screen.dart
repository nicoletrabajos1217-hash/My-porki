import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:my_porki/backend/services/auth_service.dart';
import 'register_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    // Ocultar teclado
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      final input = _userController.text.trim();
      final password = _passwordController.text.trim();

      if (input.isEmpty || password.isEmpty) {
        _showMessage('Por favor, completa todos los campos.');
        setState(() => _isLoading = false);
        return;
      }

      if (password.length < 6) {
        _showMessage('La contraseña debe tener al menos 6 caracteres.');
        setState(() => _isLoading = false);
        return;
      }

      // Solo abrir Hive, no limpiar
      final box = await Hive.openBox('porki_users');

      // Intentar login usando AuthService
      final userData = await _authService.loginUser(
        input: input,
        password: password,
      );

      if (!mounted) return;
      
      _showMessage('Bienvenido, ${userData["username"] ?? "Usuario"} 🐷');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(userData: userData),
        ),
      );

    } catch (e) {
      _showMessage(_getErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorString = error.toString();
    
    if (errorString.contains('user-not-found')) {
      return 'Usuario no encontrado. Verifica tus datos.';
    } else if (errorString.contains('wrong-password')) {
      return 'Contraseña incorrecta. Intenta nuevamente.';
    } else if (errorString.contains('network-request-failed')) {
      return 'Error de conexión. Verifica tu internet.';
    } else if (errorString.contains('too-many-requests')) {
      return 'Demasiados intentos. Espera un momento.';
    } else if (errorString.contains('invalid-email')) {
      return 'El formato del correo no es válido.';
    } else {
      return 'Error: ${errorString.replaceAll('Exception:', '').trim()}';
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.pink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // LOGO FIJO - SIN DEPENDENCIAS EXTERNAS
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.pink[50],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.pink, width: 2),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.pets,
                      size: 60,
                      color: Colors.pink,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'My Porki',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Gestión Porcina Inteligente',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 40),

                // Campo de usuario/correo
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico o usuario',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) {
                    FocusScope.of(context).nextFocus();
                  },
                ),
                const SizedBox(height: 20),

                // Campo de contraseña
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 30),

                // Botón de login o loading
                _isLoading
                    ? const Column(
                        children: [
                          CircularProgressIndicator(color: Colors.pink),
                          SizedBox(height: 16),
                          Text(
                            'Iniciando sesión...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          // Botón de inicio de sesión
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.pink,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('INICIAR SESIÓN'),
                            ),
                          ),
                          const SizedBox(height: 20),
                          
                          // Enlace a registro
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                '¿No tienes cuenta?',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const RegisterScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Regístrate aquí',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.pink,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          
                          // Información adicional
                          Container(
                            margin: const EdgeInsets.only(top: 20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Column(
                              children: [
                                Text(
                                  '💡 ¿Primera vez?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.pink,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Puedes registrarte con cualquier correo electrónico válido. Todos los usuarios tienen acceso completo a todas las funciones de la app.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}