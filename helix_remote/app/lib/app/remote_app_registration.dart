part of '../main.dart';

extension _RemoteAppRegistration on _HelixRemoteAppState {
  Widget _buildAccountDetailsStep() {
    final theme = Theme.of(context);
    // Deep-linked/auto-issued invites (Helix Global, or a personal-server
    // link already validated on the choice screen) are pre-filled - check
    // it as soon as this step is actually on screen (which only happens
    // once _startupState reaches unauthenticated, so the composition
    // root's restClient is guaranteed ready) rather than waiting for the
    // user to focus and blur a field they never touched. Deferred a frame
    // so it never calls setState synchronously from within build().
    if (!_prefilledInviteChecked && _inviteController.text.isNotEmpty) {
      _prefilledInviteChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _validateInviteCode();
      });
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Deep-linked invite signups (widget.initialInviteCode) skip
        // ServerChoiceScreen entirely and land here directly, so this
        // onboarding highlight is repeated here rather than relying solely
        // on the choice screen showing it first.
        const OnboardingSecurityBadge(),
        const SizedBox(height: 16),
        TextField(
          controller: _inviteController,
          focusNode: _inviteFocusNode,
          enabled: !_sendingCode,
          decoration: InputDecoration(
            labelText: 'Server invitation code',
            border: const OutlineInputBorder(),
            errorText: _inviteError,
            suffixIcon: _buildInviteStatusIcon(),
          ),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _validateInviteCode(),
        ),
        const SizedBox(height: 16),
        PhoneNumberInput(
          country: _selectedCountry,
          onCountryChanged: (country) => _update(() {
            _selectedCountry = country;
            _syncPhoneController();
          }),
          numberController: _nationalNumberController,
          enabled: !_sendingCode,
          errorText: _phoneError,
          // _phoneError can be a server-provided message (e.g. the SMS
          // gateway's own rejection reason via _formatRegistrationError),
          // which is longer than a plain "Invalid number" label - without
          // this it truncates to one line with an ellipsis, hiding exactly
          // the detail needed to diagnose a delivery failure.
          errorMaxLines: 5,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendVerificationCode(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed:
                (_sendingCode || _inviteCheckState != _InviteCheckState.valid)
                ? null
                : _sendVerificationCode,
            icon: _sendingCode
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sms_outlined),
            label: Text(_sendingCode ? 'Requesting code…' : 'Request OTP'),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        InkWell(
          onTap: widget.onChangeServerUrl,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: HelixInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.root.devConfig.restBaseUri.authority,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Change',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Trailing icon for the invite-code field reflecting [_inviteCheckState]:
  /// nothing while untouched/empty, a spinner while checking, a green check
  /// once valid, or a tappable red icon (shows the specific reason in a
  /// snackbar) once known invalid.
  Widget? _buildInviteStatusIcon() {
    switch (_inviteCheckState) {
      case null:
        return null;
      case _InviteCheckState.checking:
        return Padding(
          padding: HelixInsets.all(12),
          child: const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _InviteCheckState.valid:
        return const Icon(Icons.check_circle, color: Colors.green);
      case _InviteCheckState.invalid:
        // Builder gives the onPressed callback a context from *inside* the
        // MaterialApp this State builds - `this.context` (the State's own
        // context) sits above that MaterialApp, so ScaffoldMessenger.of
        // would never find the ScaffoldMessenger the MaterialApp provides,
        // silently no-opping the tap instead of showing the reason.
        return Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            tooltip: _inviteCheckReason ?? 'Invalid invitation',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_inviteCheckReason ?? 'Invalid invitation.'),
                ),
              );
            },
          ),
        );
    }
  }

  /// Recomputes the E.164 [_phoneController] value from [_selectedCountry]
  /// and whatever's currently in [_nationalNumberController] - the two
  /// fields the phone-number UI actually shows. A leading `0` is stripped
  /// since that's the common local-dialing prefix in national formats
  /// (e.g. "01712345678") that must not appear after the country code.
  void _syncPhoneController() {
    final digits = _nationalNumberController.text.replaceAll(
      RegExp(r'[^\d]'),
      '',
    );
    final national = digits.startsWith('0') ? digits.substring(1) : digits;
    _phoneController.text = '${_selectedCountry.dialCode}$national';
  }

  /// Pulls the bare code out of a pasted `.../join?invite=CODE` link - this
  /// field is labeled the same as the one on the personal-server entry
  /// screen, which *does* expect a full link, so admins share (and users
  /// paste) full links here too even though only the bare code is normally
  /// expected. Returns [raw] unchanged if it doesn't look like a link.
  String _extractInviteCode(String raw) {
    if (!raw.contains('invite=')) return raw;
    final withScheme = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final code = Uri.tryParse(withScheme)?.queryParameters['invite'];
    return (code != null && code.isNotEmpty) ? code : raw;
  }

  /// Auto-validates the invite code against the server on focus loss (see
  /// the `_inviteFocusNode` listener in `initState`) - validates the
  /// invitation before sending the OTP, to avoid unnecessary verification
  /// attempts against an invite that was never going to work.
  Future<void> _validateInviteCode() async {
    final code = _extractInviteCode(_inviteController.text.trim());
    if (code != _inviteController.text) {
      _inviteController.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    }
    if (code.isEmpty) {
      if (mounted) {
        _update(() {
          _inviteCheckState = null;
          _inviteCheckReason = null;
        });
      }
      return;
    }
    _update(() {
      _inviteCheckState = _InviteCheckState.checking;
      _inviteCheckReason = null;
    });
    try {
      final result = await widget.root.lookupInvite(code);
      if (!mounted) return;
      if (result['valid'] == true) {
        _update(() {
          _inviteCheckState = _InviteCheckState.valid;
          _inviteCheckReason = null;
        });
      } else {
        _update(() {
          _inviteCheckState = _InviteCheckState.invalid;
          _inviteCheckReason = _inviteReasonText(result['reason'] as String?);
        });
      }
    } catch (e) {
      if (!mounted) return;
      _update(() {
        _inviteCheckState = _InviteCheckState.invalid;
        _inviteCheckReason = e is RemoteRestException
            ? RemoteUserErrorCopy.registrationFailure(
                e,
                widget.root.devConfig.restBaseUri,
              )
            : 'Server is unavailable. Check your connection and try again.';
      });
    }
  }

  String _inviteReasonText(String? reason) {
    switch (reason) {
      case 'not_found':
        return 'Invitation not found.';
      case 'already_used':
        return 'Invitation already used.';
      case 'cancelled':
        return 'Invitation was cancelled.';
      case 'expired':
        return 'Invitation expired.';
      default:
        return 'This invitation is not valid.';
    }
  }

  Widget _buildOtpStep() {
    final phoneNumber = _phoneController.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _otpIsPlaceholder
              ? 'We sent a code to $phoneNumber. Since real SMS delivery '
                    'isn\'t available yet, check your notifications for it.'
              : 'We texted a verification code to $phoneNumber. It may '
                    'take a moment to arrive.',
          textAlign: TextAlign.center,
        ),
        if (_otpIsPlaceholder) ...[
          const SizedBox(height: 12),
          const OtpPlaceholderNotice(),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _otpController,
          enabled: !_registering,
          decoration: InputDecoration(
            labelText: 'Verification code',
            border: const OutlineInputBorder(),
            errorText: _otpError,
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _continueToDisplayNameStep(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _continueToDisplayNameStep,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Verify'),
          ),
        ),
      ],
    );
  }

  /// Format-checks the OTP field and moves to the display-name step. The
  /// code is only actually verified server-side once registration
  /// completes (see `_completeRegistration`) - that's the same call that
  /// consumes it, and there's no separate verify-only endpoint. A wrong or
  /// expired code surfaces as an error there and sends the user back to
  /// this step to fix it.
  void _continueToDisplayNameStep() {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty) {
      _update(() => _otpError = 'Verification code cannot be empty.');
      return;
    }
    _unfocusForStepChange();
    _update(() {
      _otpError = null;
      _createAccountStep = _CreateAccountStep.enterDisplayName;
    });
  }

  /// Closes the keyboard before swapping `_createAccountStep`'s TextField
  /// out from under it. Without this, Android's on-screen keyboard can get
  /// stuck showing the outgoing field's layout (e.g. the OTP step's numeric
  /// pad) instead of picking up the next field's - typing still lands in
  /// the right place, but the wrong keys are on screen until the keyboard
  /// is dismissed and reopened some other way.
  void _unfocusForStepChange() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Widget _buildDisplayNameStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'What should people see as your name?',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _displayNameController,
          enabled: !_registering,
          decoration: InputDecoration(
            labelText: 'Display name (optional)',
            hintText: 'e.g. Hasan',
            border: const OutlineInputBorder(),
            helperText: RemoteAccountValidation.displayNameRules,
            errorText: _displayNameError ?? _registrationError,
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _completeRegistration(skip: false),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _registering
                ? null
                : () => _completeRegistration(skip: false),
            icon: _registering
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_outlined),
            label: Text(_registering ? 'Creating account…' : 'Save'),
          ),
        ),
        const SizedBox(height: 8),
        // Builder gives onPressed a context from *inside* the MaterialApp
        // this State builds - `this.context` (the State's own context)
        // sits above that MaterialApp, so showDialog would never find a
        // Navigator, silently no-opping the tap instead of showing the
        // confirmation (see the invite-icon fix for the same bug).
        Builder(
          builder: (context) => TextButton(
            onPressed: _registering
                ? null
                : () => _confirmSkipDisplayName(context),
            child: const Text('Skip'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSkipDisplayName(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip display name?'),
        content: const Text(
          'No display name was provided. Your phone number will be used '
          'as your display name until you change it in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _completeRegistration(skip: true);
    }
  }

  Future<void> _sendVerificationCode() async {
    if (_sendingCode) return;
    if (_inviteCheckState != _InviteCheckState.valid) {
      // Reachable via the phone field's keyboard "done" action even though
      // the Request OTP button is disabled for the same reason - re-check
      // rather than silently doing nothing.
      _validateInviteCode();
      return;
    }
    final phoneNumber = _phoneController.text;
    final phoneError = RemoteAccountValidation.phoneNumberError(phoneNumber);
    if (phoneError != null) {
      _update(() {
        _phoneError = phoneError;
        _errorMessage = phoneError;
      });
      return;
    }

    _update(() {
      _sendingCode = true;
      _phoneError = null;
      _errorMessage = null;
    });

    try {
      final isPlaceholder = await widget.root.requestOtp(phoneNumber);
      if (mounted) {
        _unfocusForStepChange();
        _update(() {
          _otpIsPlaceholder = isPlaceholder;
          _createAccountStep = _CreateAccountStep.enterOtp;
        });
      }
    } catch (e, st) {
      AppLogger.instance.warn('auth', 'OTP request failed: $e', st);
      if (mounted) {
        _update(() {
          _phoneError = _formatRegistrationError(e);
          _errorMessage = _phoneError;
        });
      }
    } finally {
      if (mounted) {
        _update(() {
          _sendingCode = false;
        });
      }
    }
  }

  /// Completes registration with whatever's in `_displayNameController`, or
  /// (when [skip] is true) the phone number itself.
  Future<void> _completeRegistration({required bool skip}) async {
    if (_registering) return;
    final otpCode = _otpController.text.trim();
    final phoneNumber = _phoneController.text;
    final displayName = skip
        ? phoneNumber
        : RemoteAccountValidation.normalizeDisplayName(
            _displayNameController.text,
          );
    if (!skip) {
      final displayNameError = RemoteAccountValidation.displayNameError(
        displayName,
      );
      if (displayNameError != null) {
        _update(() => _displayNameError = displayNameError);
        return;
      }
    }

    _update(() {
      _registering = true;
      _displayNameError = null;
      _registrationError = null;
      _errorMessage = null;
    });

    try {
      await widget.root.registerAndLogin(
        phoneNumber: phoneNumber,
        displayName: displayName,
        otpCode: otpCode,
        inviteCode: _inviteController.text.trim(),
      );
    } catch (e, st) {
      AppLogger.instance.warn('auth', 'Registration failed: $e', st);
      if (mounted) {
        _unfocusForStepChange();
        _update(() {
          _registrationError = _formatRegistrationError(e);
          _errorMessage = _registrationError;
          // A stale/wrong/expired OTP code is the most likely cause of a
          // failure this late - send the user back to fix it instead of
          // leaving them stuck re-submitting the same bad code from the
          // display-name step.
          _createAccountStep = _CreateAccountStep.enterOtp;
          _otpError = _registrationError;
        });
      }
    } finally {
      if (mounted) {
        _update(() {
          _registering = false;
        });
      }
    }
  }

  String _formatRegistrationError(Object error) {
    final backend = widget.root.devConfig.restBaseUri;
    if (error is RemoteRestException) {
      return RemoteUserErrorCopy.registrationFailure(error, backend);
    }
    return RemoteUserErrorCopy.unknownRegistration();
  }
}
