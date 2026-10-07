import 'package:flutter/material.dart';
import '../theme/pavio_text_styles.dart';

/// Obscured by default with a show/hide toggle — was previously a plain permanent
/// `obscureText: true` duplicated identically in both Login and Signup, with no way to
/// verify what was typed before submitting.
class PavioPasswordField extends StatefulWidget {
  const PavioPasswordField({super.key, required this.controller, this.hintText, this.errorText, this.autofillHints, this.onSubmitted});

  final TextEditingController controller;
  final String? hintText;
  final String? errorText;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PavioPasswordField> createState() => _PavioPasswordFieldState();
}

class _PavioPasswordFieldState extends State<PavioPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      style: PavioText.body,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hintText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
