import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/config/app_settings.dart';

void main() {
  test('a real server URL counts, the emulator default and junk do not', () {
    expect(AppSettings.isRealServerUrl('https://api.example.com/api/v1'), isTrue);
    expect(AppSettings.isRealServerUrl('http://192.168.1.20:8000/api/v1'), isTrue, reason: 'a server on the LAN');
    expect(AppSettings.isRealServerUrl('http://10.0.2.2:8000/api/v1'), isFalse, reason: 'emulator-only default');
    expect(AppSettings.isRealServerUrl('http://localhost:8000'), isFalse);
    expect(AppSettings.isRealServerUrl(''), isFalse);
    expect(AppSettings.isRealServerUrl('not a url'), isFalse);
    expect(AppSettings.isRealServerUrl('ftp://files.example.com'), isFalse);
  });
}
