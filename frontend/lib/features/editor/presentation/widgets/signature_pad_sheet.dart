import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Full-screen signature capture pad: a sheet of paper with a signing line.
/// Pops the drawn points (strokes split by [Offset.infinite]), or nothing
/// when closed.
class SignaturePadSheet extends StatefulWidget {
  const SignaturePadSheet({super.key});

  @override
  State<SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<SignaturePadSheet> {
  final List<Offset> _points = [];

  bool get _empty => !_points.any((p) => p.isFinite);

  void _undoStroke() {
    setState(() {
      // Drop the trailing break, then the last stroke up to the one before.
      if (_points.isNotEmpty && !_points.last.isFinite) _points.removeLast();
      while (_points.isNotEmpty && _points.last.isFinite) {
        _points.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.signHere),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.undo,
            onPressed: _empty ? null : _undoStroke,
          ),
          TextButton(
            onPressed: _empty ? null : () => setState(_points.clear),
            child: Text(l10n.clear),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              onPressed: _empty ? null : () => Navigator.pop(context, List.of(_points)),
              child: Text(l10n.done),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DecoratedBox(
            // Paper stays white in dark mode too: ink is black.
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned(
                    left: 32,
                    right: 32,
                    bottom: 72,
                    child: Row(children: [
                      const Text('✕', style: TextStyle(color: Color(0xFF9AA3B8), fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(child: Container(height: 1.2, color: const Color(0xFFB6BECF))),
                    ]),
                  ),
                  if (_empty)
                    Center(
                      child: Text(
                        l10n.signHere,
                        style: const TextStyle(color: Color(0xFFB6BECF), fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('signaturePad'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => setState(() => _points.add(d.localPosition)),
                      onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
                      onPanEnd: (_) => setState(() => _points.add(Offset.infinite)),
                      child: CustomPaint(painter: SignaturePadPainter(_points)),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      ..strokeJoin = StrokeJoin.round
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
