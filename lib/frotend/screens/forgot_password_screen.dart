import 'package:flutter/material.dart';
import '../../backend/services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _message = null;
        _isSuccess = false;
      });

      // ✅ ACTUALIZADO: Usar el nuevo método que retorna Map
      final result = await AuthService.sendPasswordResetEmail(
        _emailController.text.trim(),
      );

      setState(() {
        _isLoading = false;
        _isSuccess = result['success'] ?? false;
        _message = result['message'] ?? 'Error desconocido';
      });

      // ✅ Mostrar información adicional si fue exitoso
      if (_isSuccess) {
        _showSuccessInfo();
      }
    }
  }

  void _showSuccessInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('✅ Revisa tu bandeja de entrada y carpeta de spam'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  // ✅ NUEVO: Método para reparar usuario huérfano (solo para testing)
  Future<void> _tryFixUser() async {
    if (_emailController.text.trim().isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _message = null;
    });

    final result = await AuthService.fixOrphanedUser(_emailController.text.trim());
    
    setState(() {
      _isLoading = false;
      _isSuccess = result['success'] ?? false;
      _message = '🔧 ${result['message']}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar Contraseña'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                '¿Olvidaste tu contraseña?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              
              // Campo de email
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo Electrónico',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                  hintText: 'ejemplo@correo.com',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor ingresa tu correo electrónico';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                    return 'Por favor ingresa un correo válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              
              // Mensaje de resultado
              if (_message != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isSuccess ? Colors.green[100] : Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isSuccess ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isSuccess ? Icons.check_circle : Icons.error,
                            color: _isSuccess ? Colors.green[800] : Colors.red[800],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _message!,
                              style: TextStyle(
                                color: _isSuccess ? Colors.green[800] : Colors.red[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // ✅ Información adicional para éxito - CORREGIDO
                      if (_isSuccess) ...[
                        const SizedBox(height: 8),
                        Text(
                          '💡 Si no ves el email, revisa tu carpeta de spam o solicita otro enlace.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700]!, // ✅ CORREGIDO: Agregado !
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              
              // Botón principal
              ElevatedButton(
                onPressed: _isLoading ? null : _sendResetEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Enviar Enlace de Recuperación',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
              
              // ✅ NUEVO: Botón para reparar usuario (solo para testing/diagnóstico)
              if (!_isSuccess && _message?.contains('Firebase Authentication') == true) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _isLoading ? null : _tryFixUser,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    '🔧 Intentar Reparar Usuario',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
              
              const SizedBox(height: 15),
              
              // Información adicional
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Información importante:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• El enlace expira en 1 hora',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      '• Revisa tu carpeta de spam',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      '• El email puede tardar unos minutos',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Botón para volver
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Volver al Inicio de Sesión',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}