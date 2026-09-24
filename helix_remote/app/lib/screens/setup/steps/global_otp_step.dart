import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class GlobalOtpStep extends StatefulWidget {
  const GlobalOtpStep({
    super.key,
    required this.phoneNumber,
    required this.otpCode,
    required this.rememberDevice,
    required this.isLoading,
    this.errorMessage,
    this.otpIsPlaceholder = false,
    required this.onOtpChanged,
    required this.onRememberDeviceChanged,
    required this.onSubmit,
    this.onResendOtp,
  });

  final String phoneNumber;
  final String otpCode;
  final bool rememberDevice;
  final bool isLoading;
  final String? errorMessage;
  final bool otpIsPlaceholder;
  final ValueChanged<String> onOtpChanged;
  final ValueChanged<bool> onRememberDeviceChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onResendOtp;

  @override
  State<GlobalOtpStep> createState() => _GlobalOtpStepState();
}

class _GlobalOtpStepState extends State<GlobalOtpStep> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (i) {
      final char = i < widget.otpCode.length ? widget.otpCode[i] : '';
      return TextEditingController(text: char);
    });
    _focusNodes = List.generate(6, (_) => FocusNode());
  }

  @override
  void didUpdateWidget(covariant GlobalOtpStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.otpCode != oldWidget.otpCode) {
      for (var i = 0; i < 6; i++) {
        final char = i < widget.otpCode.length ? widget.otpCode[i] : '';
        if (_controllers[i].text != char) {
          _controllers[i].text = char;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (value.length > 1) {
        // Multi-character paste (e.g. from notification or clipboard)
        final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
        final chars = digitsOnly.split('');
        for (var j = 0; j < 6; j++) {
          if (j < chars.length) {
            _controllers[j].text = chars[j];
          }
        }
        final nextIndex = (chars.length).clamp(0, 5);
        _focusNodes[nextIndex].requestFocus();
      } else {
        if (index < 5) {
          _focusNodes[index + 1].requestFocus();
        }
      }
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    final code = _controllers.map((c) => c.text).join();
    widget.onOtpChanged(code);
    if (code.length == 6) {
      widget.onSubmit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Enter verification code",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: HelixSpace.xs),
          RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              children: [
                const TextSpan(text: 'Sent to '),
                TextSpan(
                  text: widget.phoneNumber,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          if (widget.otpIsPlaceholder) ...[
            Container(
              padding: HelixInsets.all(HelixSpace.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      size: 20, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "SMS service is currently unavailable. A one-time verification code has been sent to your device notifications.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HelixSpace.md),
          ],
          // 6-digit OTP Box Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 48,
                height: 56,
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  onChanged: (val) => _onDigitChanged(index, val),
                ),
              );
            }),
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: HelixSpace.sm),
            Text(
              widget.errorMessage!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: HelixSpace.md),
          CheckboxListTile(
            value: widget.rememberDevice,
            onChanged: (val) => widget.onRememberDeviceChanged(val ?? true),
            title: const Text("Remember me on this device", style: TextStyle(fontSize: 13)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: HelixSpace.md),
          FilledButton.icon(
            onPressed: widget.isLoading ? null : widget.onSubmit,
            style: FilledButton.styleFrom(
              padding: HelixInsets.all(HelixSpace.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: widget.isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              widget.isLoading ? "Verifying…" : "Verify",
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Didn't receive code?",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              TextButton(
                onPressed: widget.onResendOtp ?? () {},
                child: const Text("Resend OTP"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
