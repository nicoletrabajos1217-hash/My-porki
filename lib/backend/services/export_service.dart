import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:my_porki/backend/services/sow_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

class ExportService {
  // Variable estática para almacenar el estado de permisos
  static bool _permisosConcedidos = false;

  // MÉTODO MEJORADO PARA OBTENER DIRECTORIO PÚBLICO
  static Future<String> _obtenerDirectorioPublico() async {
    try {
      String publicPath = '';

      // PARA ANDROID: Intentar obtener el directorio de Documents público
      if (Platform.isAndroid) {
        // Método 1: Directorio de Documents público
        final externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          // Tomar el primer directorio externo y usar la carpeta Documents
          publicPath = '${externalDirs.first.path}/Documents';
          print('✅ [DEBUG] Directorio Documents encontrado: $publicPath');
        }

        // Método 2: Si falla, usar el directorio externo principal
        if (publicPath.isEmpty) {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            publicPath = '${externalDir.path}/Documents';
            print('✅ [DEBUG] Usando directorio externo: $publicPath');
          }
        }
      }

      // Método 3: Para iOS o fallback
      if (publicPath.isEmpty) {
        final appDocDir = await getApplicationDocumentsDirectory();
        publicPath = appDocDir.path;
        print('⚠️ [DEBUG] Usando directorio de la app: $publicPath');
      }

      // Crear el directorio si no existe
      final dir = Directory(publicPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        print('📁 [DEBUG] Directorio creado: $publicPath');
      }

      return publicPath;
    } catch (e) {
      print('❌ [DEBUG] Error obteniendo directorio: $e');
      final appDocDir = await getApplicationDocumentsDirectory();
      return appDocDir.path;
    }
  }

  // MÉTODO PARA GENERAR ESTADÍSTICAS - AÑADIDO
  static Future<Map<String, dynamic>> generarEstadisticas() async {
    try {
      print('🔍 [DEBUG] Generando estadísticas...');
      final cerdas = await SowService.obtenerCerdas();

      // Calcular estadísticas básicas
      int totalLechones = cerdas.fold(
        0,
        (sum, c) => sum + SowService.calcularTotalLechones(c),
      );

      // Calcular cerdas preñadas (asumiendo que el estado "Preñada" existe)
      int enGestacion = cerdas
          .where(
            (c) =>
                (c['estado']?.toString().toLowerCase().contains('preñada') ==
                    true) ||
                (c['estado']?.toString().toLowerCase().contains('gestación') ==
                    true),
          )
          .length;

      final stats = {
        'totalCerdas': cerdas.length,
        'totalLechones': totalLechones,
        'cerdasActivas': cerdas.length, // Por ahora igual al total
        'enGestacion': enGestacion,
      };

      print('🔍 [DEBUG] Estadísticas generadas: $stats');
      return stats;
    } catch (e) {
      print('❌ [DEBUG] Error generando estadísticas: $e');
      return {
        'totalCerdas': 0,
        'totalLechones': 0,
        'cerdasActivas': 0,
        'enGestacion': 0,
      };
    }
  }

  static Future<String?> exportCerdasToExcel() async {
    try {
      print('🔍 [DEBUG] Iniciando exportación Excel...');

      // 1. VERIFICAR PERMISOS
      if (!_permisosConcedidos) {
        print('🔍 [DEBUG] Solicitando permisos de almacenamiento...');
        final status = await Permission.storage.request();
        _permisosConcedidos = status.isGranted;

        if (!_permisosConcedidos) {
          print('❌ [DEBUG] Permisos denegados');
          return null;
        }
      }

      // 2. OBTENER DATOS
      print('🔍 [DEBUG] Obteniendo cerdas...');
      final cerdas = await SowService.obtenerCerdas();
      print('🔍 [DEBUG] Cerdas obtenidas: ${cerdas.length}');

      if (cerdas.isEmpty) {
        print('❌ [DEBUG] No hay cerdas para exportar');
        return null;
      }

      // 3. CREAR EXCEL
      print('🔍 [DEBUG] Creando Excel...');
      final excel = Excel.createExcel();
      final sheet = excel['Cerdas'];

      // Encabezados con estilo
      sheet.appendRow(['INFORME MY PORKI - CERDAS']);
      sheet.appendRow([
        'Generado:',
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      ]);
      sheet.appendRow([]); // Línea vacía
      sheet.appendRow([
        'Nombre',
        'Estado',
        'Partos',
        'Lechones',
        'Fecha Parto',
      ]);

      // Datos
      for (var i = 0; i < cerdas.length; i++) {
        var c = cerdas[i];
        final partos = c['partos'] as List? ?? [];
        sheet.appendRow([
          c['nombre'] ?? 'Sin nombre',
          c['estado'] ?? 'Sin estado',
          partos.length.toString(),
          SowService.calcularTotalLechones(c).toString(),
          c['fecha_parto_calculado'] ?? 'No definida',
        ]);
      }

      // 4. GUARDAR EN DOCUMENTOS PÚBLICOS
      print('🔍 [DEBUG] Obteniendo directorio público...');
      final publicDir = await _obtenerDirectorioPublico();

      final fileName =
          'MyPorki_Cerdas_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final file = File('$publicDir/$fileName');

      print('🔍 [DEBUG] Guardando Excel en: ${file.path}');

      final bytes = excel.encode();
      if (bytes == null) {
        print('❌ [DEBUG] Error al codificar Excel');
        return null;
      }

      await file.writeAsBytes(bytes);

      // VERIFICAR QUE SE CREÓ
      final fileExists = await file.exists();
      print('✅ [DEBUG] ¿Archivo Excel guardado? $fileExists');
      print('✅ [DEBUG] Ruta: ${file.path}');
      print('✅ [DEBUG] Tamaño: ${bytes.length} bytes');

      if (fileExists) {
        print('🎉 [DEBUG] EXCEL GUARDADO EXITOSAMENTE EN DOCUMENTOS');
      }

      return file.path;
    } catch (e) {
      print('❌ [DEBUG] ERROR en exportCerdasToExcel: $e');
      print('❌ [DEBUG] StackTrace: ${e.toString()}');
      return null;
    }
  }

  static Future<String?> exportCerdasToPDF() async {
    try {
      print('🔍 [DEBUG] Iniciando exportación PDF...');

      // 1. VERIFICAR PERMISOS
      if (!_permisosConcedidos) {
        print('🔍 [DEBUG] Solicitando permisos para PDF...');
        final status = await Permission.storage.request();
        _permisosConcedidos = status.isGranted;

        if (!_permisosConcedidos) {
          print('❌ [DEBUG] Permisos denegados para PDF');
          return null;
        }
      }

      // 2. OBTENER DATOS
      print('🔍 [DEBUG] Obteniendo cerdas para PDF...');
      final cerdas = await SowService.obtenerCerdas();
      print('🔍 [DEBUG] Cerdas para PDF: ${cerdas.length}');

      if (cerdas.isEmpty) {
        print('❌ [DEBUG] No hay cerdas para PDF');
        return null;
      }

      // 3. CREAR PDF MEJORADO
      print('🔍 [DEBUG] Creando PDF...');
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // TÍTULO
                pw.Text(
                  'INFORME MY PORKI',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 20),

                // RESUMEN
                pw.Text(
                  'RESUMEN',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Total de cerdas: ${cerdas.length}'),
                pw.Text(
                  'Total de lechones: ${cerdas.fold(0, (sum, c) => sum + SowService.calcularTotalLechones(c))}',
                ),
                pw.SizedBox(height: 20),

                // LISTA DETALLADA
                pw.Text(
                  'LISTA DE CERDAS',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),

                // TABLA DE CERDAS
                pw.Table(
                  border: pw.TableBorder.all(),
                  children: [
                    // ENCABEZADO DE TABLA
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          child: pw.Text(
                            'Nombre',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          padding: const pw.EdgeInsets.all(8),
                        ),
                        pw.Padding(
                          child: pw.Text(
                            'Estado',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          padding: const pw.EdgeInsets.all(8),
                        ),
                        pw.Padding(
                          child: pw.Text(
                            'Partos',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          padding: const pw.EdgeInsets.all(8),
                        ),
                        pw.Padding(
                          child: pw.Text(
                            'Lechones',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          padding: const pw.EdgeInsets.all(8),
                        ),
                      ],
                    ),
                    // DATOS DE CERDAS
                    ...cerdas
                        .map(
                          (cerda) => pw.TableRow(
                            children: [
                              pw.Padding(
                                child: pw.Text(cerda['nombre'] ?? 'Sin nombre'),
                                padding: const pw.EdgeInsets.all(8),
                              ),
                              pw.Padding(
                                child: pw.Text(cerda['estado'] ?? 'Sin estado'),
                                padding: const pw.EdgeInsets.all(8),
                              ),
                              pw.Padding(
                                child: pw.Text(
                                  (cerda['partos'] as List? ?? []).length
                                      .toString(),
                                ),
                                padding: const pw.EdgeInsets.all(8),
                              ),
                              pw.Padding(
                                child: pw.Text(
                                  SowService.calcularTotalLechones(
                                    cerda,
                                  ).toString(),
                                ),
                                padding: const pw.EdgeInsets.all(8),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // 4. GUARDAR EN DOCUMENTOS PÚBLICOS
      print('🔍 [DEBUG] Obteniendo directorio público para PDF...');
      final publicDir = await _obtenerDirectorioPublico();

      final fileName =
          'MyPorki_Cerdas_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('$publicDir/$fileName');

      print('🔍 [DEBUG] Guardando PDF en: ${file.path}');

      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      // VERIFICAR QUE SE CREÓ
      final fileExists = await file.exists();
      print('✅ [DEBUG] ¿Archivo PDF guardado? $fileExists');
      print('✅ [DEBUG] Ruta: ${file.path}');
      print('✅ [DEBUG] Tamaño: ${pdfBytes.length} bytes');

      if (fileExists) {
        print('🎉 [DEBUG] PDF GUARDADO EXITOSAMENTE EN DOCUMENTOS');
      }

      return file.path;
    } catch (e) {
      print('❌ [DEBUG] ERROR en exportCerdasToPDF: $e');
      return null;
    }
  }

  // MÉTODO PARA COMPARTIR EXCEL
  static Future<void> compartirExcel(String filePath) async {
    try {
      print('🔍 [DEBUG] Compartiendo Excel: $filePath');
      await OpenFile.open(filePath);
      print('✅ [DEBUG] Excel abierto para compartir');
    } catch (e) {
      print('❌ [DEBUG] Error compartiendo Excel: $e');
    }
  }

  // MÉTODO PARA COMPARTIR PDF
  static Future<void> compartirPDF(String filePath) async {
    try {
      print('🔍 [DEBUG] Compartiendo PDF: $filePath');
      await Printing.sharePdf(
        bytes: await File(filePath).readAsBytes(),
        filename: 'MyPorki_Informe.pdf',
      );
      print('✅ [DEBUG] PDF compartido exitosamente');
    } catch (e) {
      print('❌ [DEBUG] Error compartiendo PDF: $e');
    }
  }
}
