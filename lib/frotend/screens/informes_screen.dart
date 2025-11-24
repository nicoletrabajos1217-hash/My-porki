import 'package:flutter/material.dart';
import 'package:my_porki/backend/services/export_service.dart';
import 'package:open_file/open_file.dart';

class InformesScreen extends StatefulWidget {
  const InformesScreen({super.key});

  @override
  State<InformesScreen> createState() => _InformesScreenState();
}

class _InformesScreenState extends State<InformesScreen> {
  bool _exportando = false;
  Map<String, dynamic> _estadisticas = {};
  String _ultimoError = '';

  @override
  void initState() {
    super.initState();
    _cargarEstadisticas();
  }

  Future<void> _cargarEstadisticas() async {
    try {
      final stats = await ExportService.generarEstadisticas();
      if (mounted) {
        setState(() {
          _estadisticas = stats;
          _ultimoError = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ultimoError = 'Error cargando estadísticas: $e';
        });
      }
    }
  }

  Future<void> _exportarInforme() async {
    setState(() {
      _exportando = true;
      _ultimoError = '';
    });
    
    try {
      print('🟡 Iniciando exportación desde la UI...');
      final filePath = await ExportService.exportCerdasToExcel();
      
      if (filePath != null && mounted) {
        print('✅ Archivo generado: $filePath');
        
        // Intentar abrir el archivo
        final result = await OpenFile.open(filePath);
        print('🔍 Resultado de abrir archivo: $result');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('✅ Informe exportado correctamente'),
                Text(
                  'Archivo: ${filePath.split('/').last}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: () => OpenFile.open(filePath),
            ),
          ),
        );
      } else if (mounted) {
        setState(() {
          _ultimoError = 'El servicio de exportación retornó null';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al exportar el informe (null)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ Error en exportarInforme: $e');
      if (mounted) {
        setState(() {
          _ultimoError = 'Error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _buildEstadisticaCard(String titulo, dynamic valor, String emoji) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(
              '$valor',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.pink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes y Exportación'),
        backgroundColor: Colors.pink,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mostrar error si existe
            if (_ultimoError.isNotEmpty)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _ultimoError,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Tarjeta de exportación principal
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Icon(Icons.analytics, size: 60, color: Colors.pink),
                    const SizedBox(height: 16),
                    const Text(
                      'Generar Informe Completo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Exporta todos los datos de tus cerdas a un archivo Excel para análisis externo, backup o compartir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    
                    // Información de debug
                    if (_estadisticas.isNotEmpty)
                      Card(
                        color: Colors.blue[50],
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            '📊 ${_estadisticas['totalCerdas'] ?? 0} cerdas listas para exportar',
                            style: const TextStyle(fontSize: 12, color: Colors.blue),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 12),
                    
                    ElevatedButton.icon(
                      onPressed: _exportando ? null : _exportarInforme,
                      icon: _exportando 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.file_download),
                      label: Text(_exportando ? 'Exportando...' : 'Descargar Excel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                    
                    // Botón de debug para ver logs
                    TextButton(
                      onPressed: () {
                        print('🔍 DEBUG: Estadísticas actuales: $_estadisticas');
                        print('🔍 DEBUG: Último error: $_ultimoError');
                      },
                      child: const Text(
                        'Ver logs en consola',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Estadísticas rápidas
            const Text(
              'Estadísticas Actuales',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                _buildEstadisticaCard(
                  'Total Cerdas', 
                  _estadisticas['totalCerdas'] ?? '0', 
                  '🐖'
                ),
                _buildEstadisticaCard(
                  'Preñadas', 
                  _estadisticas['prenadas'] ?? '0', 
                  '🐷'
                ),
                _buildEstadisticaCard(
                  'Total Lechones', 
                  _estadisticas['totalLechones'] ?? '0', 
                  '🐽'
                ),
                _buildEstadisticaCard(
                  'Vacunas Pendientes', 
                  _estadisticas['vacunasPendientes'] ?? '0', 
                  '💉'
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}