import 'package:flutter/material.dart';
import 'package:my_porki/frotend/screens/agregar_cerda_screen.dart';
import 'package:my_porki/frotend/screens/cerda_detail_screen.dart';
import 'package:my_porki/frotend/screens/historial_screen.dart';
import 'package:my_porki/frotend/screens/login_screen.dart'; // 👈 Import del login

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const HomeScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final username = userData['username'] ?? 'Usuario';
    final role = userData['role'] ?? 'colaborador';

    return Scaffold(
      appBar: AppBar(
        title: Text('My Porki - $username'),
        backgroundColor: Colors.pink,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Datos actualizados")),
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context, username, role),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AgregarCerdaScreen()),
          );
        },
        backgroundColor: Colors.pink,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, String username, String role) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.pink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo sin círculo
                Image.asset(
                  'assets/images/LogoAlex.png',
                  width: 70,
                  height: 70,
                ),
                const SizedBox(height: 10),
                Text(
                  username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  role.toUpperCase(),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home, color: Colors.pink),
            title: const Text('Inicio'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.pets, color: Colors.pink),
            title: const Text('Mis Cerdas'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CerdasScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.pink),
            title: const Text('Historial'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HistorialScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: const Text('Configuración'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Configuración - Próximamente")),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help, color: Colors.grey),
            title: const Text('Ayuda'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Ayuda - Próximamente")),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Cerrar Sesión'),
            onTap: () {
              _mostrarDialogoCerrarSesion(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjeta de bienvenida
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¡Bienvenido a My Porki! 🐷',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gestiona tus cerdas, partos y preñeces de forma fácil y organizada.',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Acciones rápidas
          const Text(
            'Acciones Rápidas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildActionCard(
                context,
                'Agregar Cerda',
                Icons.add_circle,
                Colors.green,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AgregarCerdaScreen(),
                    ),
                  );
                },
              ),
              _buildActionCard(
                context,
                'Ver Cerdas',
                Icons.pets,
                Colors.blue,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => CerdasScreen()),
                  );
                },
              ),
              _buildActionCard(
                context,
                'Historial',
                Icons.history,
                Colors.orange,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HistorialScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Información rápida (Resumen General)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen General 🐷',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInfoItem('Total Cerdas', '0', '🐖'),
                      _buildInfoItem('Preñadas', '0', '🐷'),
                      _buildInfoItem('Lechones', '0', '🐽'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInfoItem('Partos Hoy', '0', '🐖'),
                      _buildInfoItem('Vacunas', '0', '💉🐷'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🐷 Solo “Ver Cerdas” mostrará cerdito
  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            title.contains('Ver Cerdas')
                ? const Text('🐷', style: TextStyle(fontSize: 40))
                : Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // 🐽 Versión con emojis personalizados
  Widget _buildInfoItem(String title, String value, String emoji) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 30)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.pink,
          ),
        ),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  // ✅ Cierre de sesión funcional → regresa al login
  void _mostrarDialogoCerrarSesion(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cierra el diálogo
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) => false, // Limpia el historial
              );
            },
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
