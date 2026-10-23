import 'dart:io';

import 'package:printing/printing.dart';

/// Sends a PDF to the system print dialog (Android's print framework,
/// AirPrint on iOS). The file is passed as is, so text stays sharp and
/// selectable on the printout.
class PdfPrintService {
  const PdfPrintService();

  /// Opens the print dialog for the PDF at [path]. Returns false when the
  /// user cancelled it or the platform cannot print.
  Future<bool> printFile(String path, {String? jobName}) {
    final name = jobName ?? path.split(Platform.pathSeparator).last;
    return Printing.layoutPdf(name: name, onLayout: (_) => File(path).readAsBytes());
  }
}
