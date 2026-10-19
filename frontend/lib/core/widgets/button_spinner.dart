import 'package:flutter/material.dart';

/// A small spinner for a button's icon slot while its work runs. It takes
/// the button's icon colour, so it stays visible when the button is
/// disabled during the work (a fixed white one vanished on the light grey).
class ButtonSpinner extends StatelessWidget {
  final double size;

  const ButtonSpinner({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: IconTheme.of(context).color),
    );
  }
}
