import 'package:flutter/material.dart';
import '../theme/nivasa_colors.dart';

/// Primary button with a loading state — "button keeps its width; label swaps or is
/// replaced by the spinner", per the design doc's Loading section. Wraps
/// ElevatedButtonTheme (see NivasaTheme) rather than re-declaring size/radius/color.
class NivasaPrimaryButton extends StatelessWidget {
  const NivasaPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false, this.loadingLabel});

  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(NivasaColors.white)),
                ),
                const SizedBox(width: 10),
                Text(loadingLabel ?? 'Loading…'),
              ],
            )
          : Text(label),
    );
  }
}
