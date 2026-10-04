import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Backup > Recovery backup.
///
/// A recovery backup is sealed under a secret that only the person holds, so
/// chats can come back on a new phone with no other device to copy from. The
/// secret is shown once, here, and never stored, sent or logged by the app:
/// there is no copy button for it either, because a clipboard is not a safe
/// place for it. Helix cannot recover it, and the page says so.
class RecoveryBackupPage extends ConsumerStatefulWidget {
  const RecoveryBackupPage({super.key});

  @override
  ConsumerState<RecoveryBackupPage> createState() => _RecoveryBackupPageState();
}

enum _Mode { create, restore }

class _RecoveryBackupPageState extends ConsumerState<RecoveryBackupPage> {
  _Mode _mode = _Mode.create;
  bool _typingOwn = false;
  final TextEditingController _own = TextEditingController();
  final TextEditingController _restoreSecret = TextEditingController();

  @override
  void dispose() {
    _own.dispose();
    _restoreSecret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recoveryBackupProvider);
    final controller = ref.read(recoveryBackupProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Recovery backup')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.create, label: Text('Create')),
                ButtonSegment(value: _Mode.restore, label: Text('Restore')),
              ],
              selected: {_mode},
              onSelectionChanged: state.busy
                  ? null
                  : (value) => setState(() => _mode = value.first),
            ),
          ),
          if (state.error != null)
            InlineNotice(kind: InlineNoticeKind.error, message: state.error!),
          if (_mode == _Mode.create) ..._create(context, state, controller),
          if (_mode == _Mode.restore) ..._restore(context, state, controller),
          if (state.created != null && _mode == _Mode.create)
            const PageIntro(
              text:
                  'The secret is not stored anywhere on this phone or on the '
                  'server. If you lose it, this backup cannot be opened.',
            ),
          const SizedBox(height: HelixSpace.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
            child: Text(
              'Helix cannot reset or recover a recovery secret.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _create(
    BuildContext context,
    RecoveryBackupState state,
    RecoveryBackupController controller,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = state.stage == RecoveryStage.created;
    return [
      const PageIntro(
        text:
            'Write this secret down and keep it somewhere safe, away from '
            'this phone. You will need it to open the backup on a new phone. '
            'It is shown only here, and only now.',
      ),
      if (!_typingOwn)
        Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: Semantics(
            label: 'Your recovery secret',
            value: state.secret.split('').join(' '),
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: HelixRadius.card,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(HelixSpace.md),
                  child: Center(
                    child: Text(
                      state.secret,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
          child: TextField(
            controller: _own,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Your own secret',
              helperText: 'At least 16 characters, or 6 words',
            ),
            onChanged: controller.useOwn,
          ),
        ),
      if (!done)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
          child: Wrap(
            spacing: HelixSpace.xs,
            children: [
              if (!_typingOwn)
                TextButton(
                  onPressed: state.busy ? null : controller.regenerate,
                  child: const Text('Generate another'),
                ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () {
                        setState(() => _typingOwn = !_typingOwn);
                        if (_typingOwn) {
                          _own.clear();
                          controller.useOwn('');
                        } else {
                          controller.regenerate();
                        }
                      },
                child: Text(
                  _typingOwn ? 'Use a generated secret' : 'Type my own instead',
                ),
              ),
            ],
          ),
        ),
      if (!done)
        CheckboxListTile(
          value: state.written,
          onChanged: state.busy
              ? null
              : (value) => controller.setWritten(value ?? false),
          title: const Text('I have written it down'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      if (done)
        InlineNotice(
          kind: InlineNoticeKind.success,
          message: state.created!.skipped
              ? 'There was no history to back up yet.'
              : 'Recovery backup created.',
        )
      else
        BusyFilledButton(
          label: 'Create recovery backup',
          icon: Icons.key_outlined,
          busy: state.stage == RecoveryStage.creating,
          onPressed: state.written && state.secret.trim().isNotEmpty
              ? controller.create
              : null,
        ),
    ];
  }

  List<Widget> _restore(
    BuildContext context,
    RecoveryBackupState state,
    RecoveryBackupController controller,
  ) {
    final restored = state.restored;
    return [
      const PageIntro(
        text:
            'Type the recovery secret exactly as you wrote it, including any '
            'dashes. The messages in the backup are added to this phone; '
            'nothing already here is replaced.',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
        child: TextField(
          controller: _restoreSecret,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !state.busy,
          decoration: const InputDecoration(labelText: 'Recovery secret'),
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (restored != null)
        InlineNotice(
          kind: InlineNoticeKind.success,
          message: restored.added == 0
              ? 'The backup is already on this phone.'
              : 'Restored ${restored.added} messages.',
        ),
      BusyFilledButton(
        label: 'Restore from recovery backup',
        icon: Icons.download_for_offline_outlined,
        busy: state.stage == RecoveryStage.restoring,
        onPressed: _restoreSecret.text.trim().isEmpty
            ? null
            : () => controller.restore(_restoreSecret.text),
      ),
    ];
  }
}
