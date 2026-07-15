import 'package:flutter/material.dart';

class SignaturePad extends StatefulWidget {
  final Function(List<Offset>) onDone;
  const SignaturePad({super.key, required this.onDone});
  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Sign Here'),
        actions: [
          TextButton(onPressed: () => setState(() { _strokes.clear(); _current = []; }), child: const Text('Clear')),
          FilledButton(onPressed: () {
            final all = _strokes.expand((s) => s).toList();
            if (all.isNotEmpty) widget.onDone(all);
            Navigator.pop(context);
          }, child: const Text('Done')),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300, width: 2), borderRadius: BorderRadius.circular(12)),
        child: GestureDetector(
          onPanStart: (d) => setState(() => _current = [d.localPosition]),
          onPanUpdate: (d) => setState(() => _current = [..._current, d.localPosition]),
          onPanEnd: (_) => setState(() { _strokes.add(List.from(_current)); _current = []; }),
          child: CustomPaint(painter: _SigPainter(_strokes, _current), size: Size.infinite),
        ),
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> current;
  _SigPainter(this.strokes, this.current);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black..strokeWidth = 3
      ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final s in [...strokes, current]) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s[0].dx, s[0].dy);
      for (int i = 1; i < s.length; i++) path.lineTo(s[i].dx, s[i].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
