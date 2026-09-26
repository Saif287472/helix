import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:helix_remote/data/countries.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

class PersonalVerifyStep extends StatefulWidget {
  const PersonalVerifyStep({
    super.key,
    required this.connectedServerName,
    required this.codeType,
    required this.countryCode,
    required this.phoneNumber,
    required this.otpCode,
    required this.rememberDevice,
    required this.displayName,
    required this.isLoading,
    required this.loadingStatus,
    this.errorMessage,
    required this.onCountryCodeChanged,
    required this.onPhoneChanged,
    required this.onOtpChanged,
    required this.onRememberDeviceChanged,
    required this.onNameChanged,
    required this.onRequestOtp,
    required this.onVerifyOtp,
    required this.onComplete,
  });

  final String connectedServerName;
  final CodeType? codeType;
  final String countryCode;
  final String phoneNumber;
  final String otpCode;
  final bool rememberDevice;
  final String displayName;
  final bool isLoading;
  final String loadingStatus;
  final String? errorMessage;
  final ValueChanged<String> onCountryCodeChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onOtpChanged;
  final ValueChanged<bool> onRememberDeviceChanged;
  final ValueChanged<String> onNameChanged;
  final Future<bool> Function({bool isPersonal}) onRequestOtp;
  final Future<bool> Function({bool isPersonal}) onVerifyOtp;
  final VoidCallback onComplete;

  @override
  State<PersonalVerifyStep> createState() => _PersonalVerifyStepState();
}

class _PersonalVerifyStepState extends State<PersonalVerifyStep> {
  int _subStep = 0; // 0: Phone, 1: OTP, 2: Name
  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _otpFocusNodes;

  /// Every country the server will accept a number from, rather than the six
  /// this step was redesigned with. The step's own dropdown is unchanged -
  /// only the list behind it grew.
  static final List<String> _dialCodes = kCountryDialCodes;

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(6, (i) {
      final char = i < widget.otpCode.length ? widget.otpCode[i] : '';
      return TextEditingController(text: char);
    });
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (value.length > 1) {
        final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
        final chars = digitsOnly.split('');
        for (var j = 0; j < 6; j++) {
          if (j < chars.length) {
            _otpControllers[j].text = chars[j];
          }
        }
        final nextIndex = (chars.length).clamp(0, 5);
        _otpFocusNodes[nextIndex].requestFocus();
      } else if (index < 5) {
        _otpFocusNodes[index + 1].requestFocus();
      }
    } else if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }

    final code = _otpControllers.map((c) => c.text).join();
    widget.onOtpChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If this is an Account Recovery flow
    if (widget.codeType == CodeType.recovery) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: HelixColorTokens.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: HelixColorTokens.success.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: HelixColorTokens.success,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Code Verified & Connected",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HelixColorTokens.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HelixSpace.xl),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              ),
              child: Icon(
                Icons.restore,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: HelixSpace.lg),
            Text(
              "Account Recovery",
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: HelixSpace.sm),
            Text(
              widget.loadingStatus,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HelixSpace.xl),
            FilledButton(
              onPressed: widget.onComplete,
              style: FilledButton.styleFrom(
                padding: HelixInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Proceed to Helix", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      );
    }

    // Otherwise, Personal Server Invitation verification
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connection banner
          Container(
            padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connected to ${widget.connectedServerName}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          if (_subStep == 0) ..._buildPhoneSubStep(theme),
          if (_subStep == 1) ..._buildOtpSubStep(theme),
          if (_subStep == 2) ..._buildNameSubStep(theme),
        ],
      ),
    );
  }

  List<Widget> _buildPhoneSubStep(ThemeData theme) {
    return [
      Text(
        "Please enter your phone number",
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: HelixSpace.xs),
      Text(
        "Personal server verification required for registration.",
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: HelixSpace.lg),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: HelixInsets.symmetric(horizontal: 12, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                // An unrecognised stored value would make DropdownButton
                // assert, so it falls back to the first entry.
                value: _dialCodes.contains(widget.countryCode)
                    ? widget.countryCode
                    : _dialCodes.first,
                isExpanded: true,
                items: kCountries.map((c) {
                  return DropdownMenuItem(
                    value: c.dialCode,
                    child: Text(
                      countryLabel(c),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) widget.onCountryCodeChanged(val);
                },
              ),
            ),
          ),
          const SizedBox(width: HelixSpace.sm),
          Expanded(
            child: TextFormField(
              initialValue: widget.phoneNumber,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '1700 000000',
                labelText: 'Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: widget.errorMessage,
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
              onChanged: widget.onPhoneChanged,
              onFieldSubmitted: (_) async {
                final ok = await widget.onRequestOtp(isPersonal: true);
                if (ok && mounted) setState(() => _subStep = 1);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: HelixSpace.xl),
      FilledButton.icon(
        onPressed: widget.isLoading
            ? null
            : () async {
                final ok = await widget.onRequestOtp(isPersonal: true);
                if (ok && mounted) setState(() => _subStep = 1);
              },
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
            : const Icon(Icons.arrow_forward),
        label: Text(
          widget.isLoading ? 'Requesting OTP…' : 'Request OTP',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    ];
  }

  List<Widget> _buildOtpSubStep(ThemeData theme) {
    return [
      Container(
        padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
        margin: HelixInsets.only(bottom: HelixSpace.md),
        decoration: BoxDecoration(
          color: HelixColorTokens.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 16, color: HelixColorTokens.success),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                "Code Verified",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: HelixColorTokens.success,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      Text(
        "Enter verification code",
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: HelixSpace.xs),
      Text(
        'Sent to ${widget.countryCode} ${widget.phoneNumber}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: HelixSpace.xl),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(6, (index) {
          return SizedBox(
            width: 48,
            height: 56,
            child: TextField(
              controller: _otpControllers[index],
              focusNode: _otpFocusNodes[index],
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
        title: const Text("Remember me on this device"),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
      ),
      const SizedBox(height: HelixSpace.xl),
      FilledButton.icon(
        onPressed: widget.isLoading
            ? null
            : () async {
                final ok = await widget.onVerifyOtp(isPersonal: true);
                if (ok && mounted) setState(() => _subStep = 2);
              },
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
    ];
  }

  List<Widget> _buildNameSubStep(ThemeData theme) {
    final isValid = widget.displayName.trim().length >= 3;

    return [
      Container(
        padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
        margin: HelixInsets.only(bottom: HelixSpace.md),
        decoration: BoxDecoration(
          color: HelixColorTokens.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 16, color: HelixColorTokens.success),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                "Phone Number Verified",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: HelixColorTokens.success,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      Text(
        "Please enter your name",
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: HelixSpace.xs),
      Text(
        "Choose how you'd like to appear to your contacts.",
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: HelixSpace.lg),
      TextFormField(
        initialValue: widget.displayName,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Display Name',
          hintText: 'e.g. Alex Vance',
          prefixIcon: const Icon(Icons.person_outline),
          helperText: 'Must be at least 3 characters',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onChanged: widget.onNameChanged,
      ),
      const SizedBox(height: HelixSpace.xl),
      FilledButton(
        onPressed: (isValid && !widget.isLoading) ? widget.onComplete : null,
        style: FilledButton.styleFrom(
          padding: HelixInsets.all(HelixSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          widget.isLoading ? "Creating Profile…" : "Proceed to Helix",
          style: const TextStyle(fontSize: 16),
        ),
      ),
      const SizedBox(height: HelixSpace.sm),
      OutlinedButton(
        onPressed: widget.isLoading ? null : widget.onComplete,
        style: OutlinedButton.styleFrom(
          padding: HelixInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Skip",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              "Your phone number will be used as your default name",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
