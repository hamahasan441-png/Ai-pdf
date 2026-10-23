
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/ink_smooth_service.dart';

void main() {
  const svc = InkSmoothService();

  test('a pen stroke keeps its endpoints and gains rounded points', () {
    final pts = [const Offset(0, 0), const Offset(0.5, 1), const Offset(1, 0)];
    final out = svc.smooth(pts);
    expect(out.first, pts.first);
    expect(out.last, pts.last);
    expect(out.length, greaterThan(pts.length));
  });

  test('a two-point stroke is left unchanged', () {
    final pts = [const Offset(0, 0), const Offset(1, 1)];
    expect(svc.smooth(pts), pts);
  });
}
