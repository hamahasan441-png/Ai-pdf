import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Full-screen signature capture pad.
class SignaturePadSheet extends StatefulWidget {
  const SignaturePadSheet({super.key});

  @override
  State<SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<SignaturePadSheet> {
  final List<Offset> _points = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.signHere),
        actions: [
          TextButton(
            onPressed: () => setState(() => _points.clear()),
            child: Text(AppLocalizations.of(context)!.clear),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _points.where((p) => p.isFinite).toList(),
            ),
            child: Text(AppLocalizations.of(context)!.done),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
        onPanEnd: (_) => _points.add(Offset.infinite),
        child: CustomPaint(
          painter: SignaturePadPainter(_points),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class SignaturePadPainter extends CustomPainter {
  final List<Offset> points;

  SignaturePadPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.infinite && points[i + 1] != Offset.infinite) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePadPainter oldDelegate) => true;
}
