package com.aidocassistant.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.aidocassistant.app.pdfimport.PdfImportPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(PdfImportPlugin())
        flutterEngine.plugins.add(LowRamPlugin())
    }
}
