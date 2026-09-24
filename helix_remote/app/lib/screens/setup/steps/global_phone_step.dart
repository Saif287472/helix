import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class GlobalPhoneStep extends StatelessWidget {
  const GlobalPhoneStep({
    super.key,
    required this.countryCode,
    required this.phoneNumber,
    required this.isLoading,
    this.errorMessage,
    required this.onCountryCodeChanged,
    required this.onPhoneChanged,
    required this.onSubmit,
  });

  final String countryCode;
  final String phoneNumber;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<String> onCountryCodeChanged;
  final ValueChanged<String> onPhoneChanged;
  final VoidCallback onSubmit;

  static const List<String> _countries = [
    '+880',
    '+1',
    '+44',
    '+91',
    '+49',
    '+81',
    '+33',
    '+61',
    '+86',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner
          Container(
            padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: HelixColorTokens.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: HelixColorTokens.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: HelixColorTokens.success,
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    "Connected to Helix Global Server",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HelixColorTokens.success,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          Text(
            "Please enter your phone number",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: HelixSpace.xs),
          Text(
            "We'll send a one-time verification code via SMS.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: HelixSpace.lg),
          // Phone Input Row
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
                    value: _countries.contains(countryCode) ? countryCode : _countries.first,
                    items: _countries.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) onCountryCodeChanged(val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: HelixSpace.sm),
              Expanded(
                child: TextFormField(
                  initialValue: phoneNumber,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '1700 000000',
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorText: errorMessage,
                    errorMaxLines: 3,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  onChanged: onPhoneChanged,
                  onFieldSubmitted: (_) => onSubmit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.xl),
          FilledButton.icon(
            onPressed: isLoading ? null : onSubmit,
            style: FilledButton.styleFrom(
              padding: HelixInsets.all(HelixSpace.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: Text(
              isLoading ? 'Requesting OTP…' : 'Request OTP',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
