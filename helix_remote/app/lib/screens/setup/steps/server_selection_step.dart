import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:helix_remote/screens/setup/state/onboarding_state.dart';

class ServerSelectionStep extends StatefulWidget {
  const ServerSelectionStep({
    super.key,
    required this.selectedType,
    this.othersOption = OthersOption.join,
    required this.onSelectType,
    this.onSelectOthersOption,
    this.countryCode = '+880',
    this.phoneNumber = '',
    this.onCountryCodeChanged,
    this.onPhoneChanged,
    this.onRequestOtp,
    this.otpCode = '',
    this.onOtpChanged,
    this.onVerifyOtp,
    this.displayName = '',
    this.onDisplayNameChanged,
    this.onCompleteSetup,
    this.rememberDevice = false,
    this.onRememberDeviceChanged,
    this.codeString = '',
    this.showInfoPopover = false,
    this.onCodeChanged,
    this.onToggleInfo,
    this.onVerifyCode,
    this.hostGuideStep = 0,
    this.onHostStepChanged,
    this.isLoading = false,
    this.errorMessage,
    this.onProceed,
    required this.onContinueOffline,
    this.globalSubStep = GlobalSubStep.phone,
    this.joinSubStep = JoinSubStep.code,
    this.connectedServerName,
  });

  final ServerType selectedType;
  final OthersOption othersOption;
  final ValueChanged<ServerType> onSelectType;
  final ValueChanged<OthersOption>? onSelectOthersOption;
  final String countryCode;
  final String phoneNumber;
  final ValueChanged<String>? onCountryCodeChanged;
  final ValueChanged<String>? onPhoneChanged;
  final VoidCallback? onRequestOtp;
  final String otpCode;
  final ValueChanged<String>? onOtpChanged;
  final VoidCallback? onVerifyOtp;
  final String displayName;
  final ValueChanged<String>? onDisplayNameChanged;
  final void Function({bool skip})? onCompleteSetup;
  final bool rememberDevice;
  final ValueChanged<bool>? onRememberDeviceChanged;
  final String codeString;
  final bool showInfoPopover;
  final ValueChanged<String>? onCodeChanged;
  final VoidCallback? onToggleInfo;
  final VoidCallback? onVerifyCode;
  final int hostGuideStep;
  final ValueChanged<int>? onHostStepChanged;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onProceed;
  final VoidCallback onContinueOffline;
  final GlobalSubStep globalSubStep;
  final JoinSubStep joinSubStep;
  final String? connectedServerName;

  @override
  State<ServerSelectionStep> createState() => _ServerSelectionStepState();
}

class _ServerSelectionStepState extends State<ServerSelectionStep> {
  late final TextEditingController _phoneController;
  late final TextEditingController _codeController;
  late final TextEditingController _otpController;
  late final TextEditingController _nameController;
  late final List<TextEditingController> _otpDigitControllers;
  late final List<FocusNode> _otpFocusNodes;

  static const List<Map<String, String>> _countries = [
    {'code': '+880', 'label': '+880 (BD)'},
    {'code': '+1', 'label': '+1 (US)'},
    {'code': '+44', 'label': '+44 (UK)'},
    {'code': '+91', 'label': '+91 (IN)'},
    {'code': '+49', 'label': '+49 (DE)'},
    {'code': '+81', 'label': '+81 (JP)'},
    {'code': '+33', 'label': '+33 (FR)'},
    {'code': '+61', 'label': '+61 (AU)'},
  ];

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.phoneNumber);
    _codeController = TextEditingController(text: widget.codeString);
    _otpController = TextEditingController(text: widget.otpCode);
    _nameController = TextEditingController(text: widget.displayName);
    _otpDigitControllers = List.generate(6, (i) {
      final char = i < widget.otpCode.length ? widget.otpCode[i] : '';
      return TextEditingController(text: char);
    });
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
  }

  @override
  void didUpdateWidget(ServerSelectionStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phoneNumber != oldWidget.phoneNumber &&
        widget.phoneNumber != _phoneController.text) {
      _phoneController.text = widget.phoneNumber;
    }
    if (widget.codeString != oldWidget.codeString &&
        widget.codeString != _codeController.text) {
      _codeController.text = widget.codeString;
    }
    if (widget.otpCode != oldWidget.otpCode) {
      if (widget.otpCode != _otpController.text) {
        _otpController.text = widget.otpCode;
      }
      for (var i = 0; i < 6; i++) {
        final char = i < widget.otpCode.length ? widget.otpCode[i] : '';
        if (_otpDigitControllers[i].text != char) {
          _otpDigitControllers[i].text = char;
        }
      }
    }
    if (widget.displayName != oldWidget.displayName &&
        widget.displayName != _nameController.text) {
      _nameController.text = widget.displayName;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    for (final c in _otpDigitControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onOtpDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (value.length > 1) {
        final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
        final chars = digitsOnly.split('');
        for (var j = 0; j < 6; j++) {
          if (j < chars.length) {
            _otpDigitControllers[j].text = chars[j];
          }
        }
        final nextIndex = (chars.length).clamp(0, 5);
        _otpFocusNodes[nextIndex].requestFocus();
      } else if (index < 5) {
        _otpFocusNodes[index + 1].requestFocus();
      }
    }
    final combined = _otpDigitControllers.map((c) => c.text).join();
    _otpController.text = combined;
    widget.onOtpChanged?.call(combined);
  }

  void _handleCodeChanged(String value) {
    widget.onCodeChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered Header with Shield Icon
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Color(0xFF2563EB),
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.sm),
          Text(
            "Connect to Helix",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          Text(
            "Choose a server to connect to",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: HelixSpace.md),

          // Main Tabs: Helix Global Server | Others
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SegmentTab(
                    label: 'Helix Global Server',
                    isSelected: widget.selectedType == ServerType.global,
                    onTap: () => widget.onSelectType(ServerType.global),
                  ),
                ),
                Expanded(
                  child: _SegmentTab(
                    label: 'Others',
                    isSelected: widget.selectedType == ServerType.others,
                    onTap: () => widget.onSelectType(ServerType.others),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HelixSpace.md),

          // Active Panel Content
          if (widget.selectedType == ServerType.global)
            _buildGlobalContent(context)
          else
            _buildOthersContent(context),

          // Error Message Banner (if any)
          if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: HelixSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.errorMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: HelixSpace.md),
          const Divider(color: Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: HelixSpace.sm),

          // Continue Offline Button
          Center(
            child: TextButton(
              onPressed: widget.onContinueOffline,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text(
                "Continue offline for now",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),

          // Legal Footer
          const SizedBox(height: HelixSpace.xs),
          const Text(
            "By continuing, you agree to Helix Terms of Service and Privacy Policy.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
              height: 1.3,
            ),
          ),
          const SizedBox(height: HelixSpace.md),
        ],
      ),
    );
  }

  // ===========================================================================
  // PANEL 1: GLOBAL SERVER INLINE CONTENT
  // ===========================================================================
  Widget _buildGlobalContent(BuildContext context) {
    switch (widget.globalSubStep) {
      case GlobalSubStep.phone:
        return _buildPhoneInputSection(context, isPersonal: false);
      case GlobalSubStep.otp:
        return _buildOtpInputSection(context, isPersonal: false);
      case GlobalSubStep.name:
        return _buildNameInputSection(context, isPersonal: false);
    }
  }

  // ===========================================================================
  // PANEL 2: OTHERS (CUSTOM SERVERS) CONTENT
  // ===========================================================================
  Widget _buildOthersContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Choose a custom server option:",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: HelixSpace.sm),

        // Sub-tabs: Join a personal server | Host your own server
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SegmentTab(
                  label: 'Join a personal server',
                  isSelected: widget.othersOption == OthersOption.join,
                  onTap: () => widget.onSelectOthersOption
                      ?.call(OthersOption.join),
                ),
              ),
              Expanded(
                child: _SegmentTab(
                  label: 'Host your own server',
                  isSelected: widget.othersOption == OthersOption.host,
                  onTap: () => widget.onSelectOthersOption
                      ?.call(OthersOption.host),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HelixSpace.md),

        // Sub-Panel Content
        if (widget.othersOption == OthersOption.join)
          _buildJoinSubPanel(context)
        else
          _buildHostSubPanel(context),
      ],
    );
  }

  Widget _buildJoinSubPanel(BuildContext context) {
    switch (widget.joinSubStep) {
      case JoinSubStep.code:
        return _buildJoinCodeContent(context);
      case JoinSubStep.phone:
        return _buildPhoneInputSection(context, isPersonal: true);
      case JoinSubStep.otp:
        return _buildOtpInputSection(context, isPersonal: true);
      case JoinSubStep.name:
        return _buildNameInputSection(context, isPersonal: true);
      case JoinSubStep.recoverySync:
        return _buildJoinRecoveryContent(context);
    }
  }

  // ===========================================================================
  // SUB-STEP BUILDERS
  // ===========================================================================

  Widget _buildConnectedServerBanner(String serverName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "Connected to $serverName",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF059669),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneVerifiedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              "Phone Number Verified",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF15803D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. Code Entry Section
  Widget _buildJoinCodeContent(BuildContext context) {
    final theme = Theme.of(context);
    final upper = widget.codeString.trim().toUpperCase();
    final isRecovery = upper.startsWith('HLX-REC-') ||
        upper.startsWith('REC-') ||
        upper.contains('RECOVERY');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                "Enter invitation or recovery code",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            InkWell(
              onTap: widget.onToggleInfo,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                ),
                child: const Center(
                  child: Text(
                    "!",
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        if (widget.showInfoPopover) ...[
          const SizedBox(height: HelixSpace.sm),
          Container(
            padding: const EdgeInsets.all(HelixSpace.sm),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Code Details",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    InkWell(
                      onTap: widget.onToggleInfo,
                      child: const Padding(
                        padding: EdgeInsets.all(2.0),
                        child: Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  "Provide the access code issued by your server admin or your seed recovery key.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 6),
                const Text(
                  "• Invitation Codes: Connects to private server & requires phone verification.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 2),
                const Text(
                  "• Recovery Codes: Restores existing account instantly.",
                  style: TextStyle(fontSize: 12, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: HelixSpace.md),
        const Text(
          "CODE INPUT",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        TextFormField(
          controller: _codeController,
          autofocus: false,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: 'HLX-INV-ey... OR REC-9912-K',
            hintStyle: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
              fontWeight: FontWeight.normal,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          onChanged: _handleCodeChanged,
          onFieldSubmitted: (_) {
            if (widget.onVerifyCode != null) {
              widget.onVerifyCode!();
            } else {
              widget.onProceed?.call();
            }
          },
        ),

        if (upper.isNotEmpty) ...[
          const SizedBox(height: HelixSpace.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isRecovery
                  ? const Color(0xFFF3E8FF)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRecovery ? Icons.history : Icons.verified_outlined,
                  size: 16,
                  color: isRecovery
                      ? const Color(0xFF7E22CE)
                      : const Color(0xFF2563EB),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isRecovery
                        ? "Detected: Account Recovery Code"
                        : "Detected: Server Invitation Code",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isRecovery
                          ? const Color(0xFF7E22CE)
                          : const Color(0xFF2563EB),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: HelixSpace.lg),
        FilledButton(
          onPressed: widget.isLoading
              ? null
              : () {
                  if (widget.onVerifyCode != null) {
                    widget.onVerifyCode!();
                  } else {
                    widget.onProceed?.call();
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
          ),
          child: widget.isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  "Verify & Connect",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }

  // 2. Phone Input Section
  Widget _buildPhoneInputSection(BuildContext context, {required bool isPersonal}) {
    final theme = Theme.of(context);
    final serverName = isPersonal
        ? (widget.connectedServerName ?? 'Personal Server')
        : 'Helix Global Server';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildConnectedServerBanner(serverName),
        const SizedBox(height: HelixSpace.md),
        Text(
          "Please enter your phone number",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        Text(
          "We'll send a one-time verification code via SMS.",
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: HelixSpace.md),
        const Text(
          "PHONE NUMBER",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _countries.any((c) => c['code'] == widget.countryCode)
                      ? widget.countryCode
                      : '+880',
                  items: _countries.map((c) {
                    return DropdownMenuItem<String>(
                      value: c['code'],
                      child: Text(
                        c['label']!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      widget.onCountryCodeChanged?.call(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: HelixSpace.xs),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(
                  hintText: '1700 000000',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF2563EB), width: 1.5),
                  ),
                ),
                onChanged: widget.onPhoneChanged,
                onFieldSubmitted: (_) => widget.onRequestOtp?.call(),
              ),
            ),
          ],
        ),
        const SizedBox(height: HelixSpace.md),
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: widget.rememberDevice,
                onChanged: (val) =>
                    widget.onRememberDeviceChanged?.call(val ?? false),
                activeColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.onRememberDeviceChanged
                  ?.call(!widget.rememberDevice),
              child: const Text(
                "Remember this device",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: HelixSpace.lg),
        FilledButton(
          onPressed: widget.isLoading ? null : widget.onRequestOtp,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
          ),
          child: widget.isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  "Request OTP",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }

  // 3. OTP Input Section
  Widget _buildOtpInputSection(BuildContext context, {required bool isPersonal}) {
    final theme = Theme.of(context);
    final serverName = isPersonal
        ? (widget.connectedServerName ?? 'Personal Server')
        : 'Helix Global Server';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildConnectedServerBanner(serverName),
        const SizedBox(height: HelixSpace.md),
        Text(
          "Enter verification code",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        Text(
          "We've sent a 6-digit verification code to ${widget.countryCode} ${widget.phoneNumber}.",
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: HelixSpace.md),
        const Text(
          "VERIFICATION CODE",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: _otpDigitControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: Color(0xFF2563EB), width: 1.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                onChanged: (val) => _onOtpDigitChanged(index, val),
              ),
            );
          }),
        ),
        const SizedBox(height: HelixSpace.xs),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.isLoading ? null : widget.onRequestOtp,
            child: const Text(
              "Didn't receive code? Resend",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        ),
        const SizedBox(height: HelixSpace.sm),
        FilledButton(
          onPressed: widget.isLoading ? null : widget.onVerifyOtp,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
          ),
          child: widget.isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  "Verify",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
      ],
    );
  }

  // 4. Name Input Section
  Widget _buildNameInputSection(BuildContext context, {required bool isPersonal}) {
    final theme = Theme.of(context);
    final serverName = isPersonal
        ? (widget.connectedServerName ?? 'Personal Server')
        : 'Helix Global Server';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildConnectedServerBanner(serverName),
        const SizedBox(height: HelixSpace.xs),
        _buildPhoneVerifiedBanner(),
        const SizedBox(height: HelixSpace.md),
        Text(
          "Complete your profile",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        Text(
          "Please enter your name to finish setting up your account.",
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: HelixSpace.md),
        const Text(
          "DISPLAY NAME",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'e.g. Alex Miller',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF2563EB), width: 1.5),
            ),
          ),
          onChanged: widget.onDisplayNameChanged,
          onFieldSubmitted: (_) =>
              widget.onCompleteSetup?.call(skip: false),
        ),
        const SizedBox(height: HelixSpace.lg),
        FilledButton(
          onPressed: widget.isLoading
              ? null
              : () => widget.onCompleteSetup?.call(skip: false),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
          ),
          child: widget.isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  "Proceed to Helix",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
        const SizedBox(height: HelixSpace.xs),
        TextButton(
          onPressed: widget.isLoading
              ? null
              : () => widget.onCompleteSetup?.call(skip: true),
          child: const Text(
            "Skip",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  // 5. Recovery Section
  Widget _buildJoinRecoveryContent(BuildContext context) {
    final theme = Theme.of(context);
    final serverName = widget.connectedServerName ?? 'Personal Server';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildConnectedServerBanner(serverName),
        const SizedBox(height: HelixSpace.md),
        Text(
          "Restoring your account",
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: HelixSpace.xxs),
        const Text(
          "We are restoring your keys and connecting to your server.",
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: HelixSpace.xl),
        const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2563EB),
          ),
        ),
        const SizedBox(height: HelixSpace.xl),
      ],
    );
  }

  // Sub-panel: Host your own server (Guide)
  Widget _buildHostSubPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HelixSpace.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Run your own Helix Remote server",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          const Text(
            "Helix Admin is a free companion app that sets up and manages a Helix Remote server on your own PC or a rented VPS. You stay in full control of your data.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          _buildGuideStepRow(
            stepNumber: "1",
            text: "Install Helix Admin on the machine that will run your server.",
          ),
          const SizedBox(height: 8),
          _buildGuideStepRow(
            stepNumber: "2",
            text: "Follow its Self-Hosting Guide to install and configure the backend.",
          ),
          const SizedBox(height: 8),
          _buildGuideStepRow(
            stepNumber: "3",
            text: "Once it's running, Helix Admin gives you a shareable invite link.",
          ),
          const SizedBox(height: 8),
          _buildGuideStepRow(
            stepNumber: "4",
            text: "Come back here and choose \"Join a personal server\" with that link.",
          ),
          const SizedBox(height: HelixSpace.lg),
          OutlinedButton(
            onPressed: () =>
                widget.onSelectOthersOption?.call(OthersOption.join),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFF2563EB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "I have a code to join",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideStepRow({required String stepNumber, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFDBEAFE),
          ),
          child: Center(
            child: Text(
              stepNumber,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF334155),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFFDBEAFE), width: 1.2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}
