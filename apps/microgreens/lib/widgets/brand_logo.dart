import 'package:flutter/material.dart';

/// Wordmark from the original calligraphic asset.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.maxWidth = 300});

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Микрозелень от Агронайзер',
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Image.asset(
            'assets/logo_microgreens.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
