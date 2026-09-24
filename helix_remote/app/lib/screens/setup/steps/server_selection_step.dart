import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:helix_remote/app/helix_code.dart';
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

  @override
  State<ServerSelectionStep> createState() => _ServerSelectionStepState();
}

class _ServerSelectionStepState extends State<ServerSelectionStep> {
  late final TextEditingController _phoneController;
  late final TextEditingController _codeController;

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
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _handleCodeChanged(String value) {
    final decoded = decodeHelixInviteCode(value);
    if (decoded != null && decoded.inviteCode != value) {
      _codeController.text = decoded.inviteCode;
      _codeController.selection =
          TextSelection.collapsed(offset: decoded.inviteCode.length);
      widget.onCodeChanged?.call(decoded.inviteCode);
    } else {
      widget.onCodeChanged?.call(value);
    }
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
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFDBEAFE), width: 1.5),
              ),
              child: const Icon(
                Icons.shield,
                size: 34,
                color: Color(0xFF3B82F6),
              ),
            ),
          ),
          const SizedBox(height: HelixSpace.sm),
          Text(
            "Helix",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: HelixSpace.xxs),
          Text(
            "The privacy you deserve",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: HelixSpace.md),
          Text(
            "How do you want to proceed?",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: HelixSpace.md),

          // Primary Segmented Tabs: Helix Global Server | Others
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
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
          const SizedBox(height: HelixSpace.lg),

          // Error banner if any
          if (widget.errorMessage != null) ...[
            Container(
              padding: HelixInsets.all(HelixSpace.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 20, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HelixSpace.md),
          ],

          // Content based on Selected Server Type
          if (widget.selectedType == ServerType.global)
            _buildGlobalServerContent(context)
          else
            _buildOthersContent(context),

          const SizedBox(height: HelixSpace.sm),
          TextButton(
            onPressed: widget.onContinueOffline,
            child: const Text(
              "Continue offline for now",
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PANEL 1: HELIX GLOBAL SERVER CONTENT
  // ===========================================================================
  Widget _buildGlobalServerContent(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Connected to Helix Global Server Banner
        Container(
          padding: HelixInsets.symmetric(horizontal: 14, vertical: 8),
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
              const Flexible(
                child: Text(
                  "Connected to Helix Global Server",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF059669),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
              padding: HelixInsets.symmetric(horizontal: 10, vertical: 2),
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
                  errorMaxLines: 3,
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
                onFieldSubmitted: (_) {
                  if (widget.onRequestOtp != null) {
                    widget.onRequestOtp!();
                  } else {
                    widget.onProceed?.call();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: HelixSpace.lg),
        FilledButton(
          onPressed: widget.isLoading
              ? null
              : () {
                  if (widget.onRequestOtp != null) {
                    widget.onRequestOtp!();
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

  // ===========================================================================
  // PANEL 2: OTHERS (CUSTOM SERVERS) CONTENT
  // ===========================================================================
  Widget _buildOthersContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Prompt
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

  // Sub-panel: Join a Personal Server (Code Entry)
  Widget _buildJoinSubPanel(BuildContext context) {
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

        // Collapsible Info Popover Box
        if (widget.showInfoPopover) ...[
          const SizedBox(height: HelixSpace.sm),
          Container(
            padding: HelixInsets.all(HelixSpace.sm),
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
            hintText: 'INV-8829-X OR REC-9912-K',
            hintStyle: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF94A3B8),
              letterSpacing: 0.5,
              fontWeight: FontWeight.normal,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            errorMaxLines: 3,
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
              borderSide: const BorderSide(
                  color: Color(0xFF2563EB), width: 1.5),
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

  // Sub-panel: Host your own server (Guide)
  Widget _buildHostSubPanel(BuildContext context) {
    return Container(
      padding: HelixInsets.all(HelixSpace.md),
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
