import 'package:flutter/material.dart';

class EditorLoadingOverlay extends StatelessWidget {
  final bool loading;
  final bool detecting;
  final String? detectingLabel;

  const EditorLoadingOverlay({
    super.key,
    required this.loading,
    required this.detecting,
    this.detectingLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && !detecting) return const SizedBox.shrink();
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x66000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (detecting && detectingLabel != null) ...[
                const SizedBox(height: 12),
                Text(detectingLabel!, style: const TextStyle(color: Colors.white)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
