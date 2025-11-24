import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:my_porki/backend/services/sow_service.dart';

class ExportService {

  ///  EXPORTAR CERDAS A EXCEL — 100% FUNCIONAL
  static Future<String?> exportCerdasToExcel() async {
    try {
      print('🟡 [1/7] Iniciando exportación...');

      // 1. PERMISOS (Android 10–14)
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        throw Exception("Permiso de manejo de almacenamiento denegado");
      }

      print('✅ Permisos OK');

      // 2. OBTENER DATOS
      final cerdas = await SowService.obtenerCerdas();
      if (cerdas.isEmpty) throw Exception("No hay cerdas para exportar");

      print('📦 Total cerdas: ${cerdas.length}');

      // 3. CREAR EXCEL
      final excel = Excel.createExcel();

      // NOMBRE SEGURO
      final sheet = excel['Cerdas'];

      // 4. ENCABEZADOS
      sheet.appendRow([
        'ID',
        'Nombre',
        'Estado',
        'Fecha Preñez',
        'Fecha Parto',
        'Total Partos',
        'Total Lechones',
        'Vacunas Pendientes',
        'Creada',
        'Actualizada'
      ]);

      // Aux para fechas
      String formatFecha(String? f) {
        if (f == null || f.isEmpty) return '';
        try {
          final d = DateTime.parse(f);
          return "${d.day}/${d.month}/${d.year}";
        } catch (_) {
          return f;
        }
      }

      // 5. LLENAR DATOS
      for (var c in cerdas) {
        final partos = c['partos'] as List? ?? [];
        final vacunas = c['vacunas'] as List? ?? [];
        int vacunasPend = 0;
        final ahora = DateTime.now();

        for (var v in vacunas) {
          final dosis = v['dosis_programadas'] as List? ?? [];
          for (var d in dosis) {
            final fecha = DateTime.tryParse(d['fecha'] ?? '');
            if (fecha != null && fecha.isAfter(ahora)) vacunasPend++;
          }
        }

        sheet.appendRow([
          c['id'] ?? '',
          c['nombre'] ?? '',
          c['estado'] ?? '',
          formatFecha(c['fecha_prenez']),
          formatFecha(c['fecha_parto_calculado']),
          partos.length.toString(),
          SowService.totalLechones(c).toString(),
          vacunasPend.toString(),
          formatFecha(c['fecha_creacion']),
          formatFecha(c['fecha_actualizacion']),
        ]);
      }

      // 6. DIRECTORIO REAL COMPATIBLE
      final downloads = Directory('/storage/emulated/0/Download');

      if (!await downloads.exists()) {
        throw Exception("La carpeta Downloads no existe");
      }

      final fecha =
          DateTime.now().toString().replaceAll(':', '-').split('.')[0];

      final output = File(
          '${downloads.path}/Informe_MyPorki_$fecha.xlsx');

      // 7. GUARDAR ARCHIVO
      final bytes = excel.encode();
      if (bytes == null) throw Exception("excel.encode() retornó null");

      await output.writeAsBytes(bytes);
      print('✅ Archivo guardado en: ${output.path}');

      return output.path;

    } catch (e) {
      print('❌ Error exportando Excel: $e');
      return null;
    }
  }

  ///  GENERAR ESTADÍSTICAS
  static Future<Map<String, dynamic>> generarEstadisticas() async {
    try {
      final cerdas = await SowService.obtenerCerdas();

      int total = cerdas.length;
      int prenadas = cerdas
          .where((c) => (c['estado'] ?? '').toString().toLowerCase().contains('pre'))
          .length;

      int totalLechones = 0;
      int totalPartos = 0;
      int vacunasPendientes = 0;
      final ahora = DateTime.now();

      for (var c in cerdas) {
        totalLechones += SowService.totalLechones(c);
        totalPartos += (c['partos'] as List? ?? []).length;

        final vacunas = c['vacunas'] as List? ?? [];
        for (var v in vacunas) {
          final dosis = v['dosis_programadas'] as List? ?? [];
          for (var d in dosis) {
            final f = DateTime.tryParse(d['fecha'] ?? '');
            if (f != null && f.isAfter(ahora)) vacunasPendientes++;
          }
        }
      }

      return {
        'totalCerdas': total,
        'prenadas': prenadas,
        'totalLechones': totalLechones,
        'totalPartos': totalPartos,
        'vacunasPendientes': vacunasPendientes,
      };
    } catch (e) {
      print('❌ Error estadísticas: $e');
      return {};
    }
  }
}
