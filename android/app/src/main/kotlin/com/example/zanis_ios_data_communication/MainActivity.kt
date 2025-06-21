package com.example.zanis_ios_data_communication

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the vendor USB plugin
        flutterEngine.plugins.add(VendorUsbPlugin())
    }
}
