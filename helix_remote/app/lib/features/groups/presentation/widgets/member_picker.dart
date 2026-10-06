import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/create_group.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Chooses people for a group: the ones this device knows, filtered as you
/// type, and - for a number or `~Helix name` it does not know yet - a lookup on
/// the server. Chosen people sit above the list as removable chips.
///
/// No contact requests exist: anybody who allows being added can be added, so
/// there is nothing to wait for. (People whose privacy settings say otherwise
/// come back from the server as "not added", with a sentence to say so.)
class MemberPicker extends ConsumerStatefulWidget {
  const MemberPicker({
    super.key,
    required this.selected,
    required this.onToggle,
    this.exclude = const {},
  });

  /// Accounts chosen so far, in the order they were chosen.
  final List<String> selected;

  /// Chooses or un-chooses an account.
  final void Function(String account) onToggle;

  /// Accounts that cannot be chosen (already in the group).
  final Set<String> exclude;

  @override
  ConsumerState<MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends ConsumerState<MemberPicker> {
  final TextEditingController _query = TextEditingController();
  String _text = '';
  bool _looking = false;

  /// People found by lookup, until the people list catches up with them.
  final Map<String, GroupCandidate> _found = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(GroupCandidate c, String needle) {
    if (needle.isEmpty) return true;
    final names = c.names;
    return names.display.toLowerCase().contains(needle) ||
        (names.number ?? '').contains(needle) ||
        (names.helixName ?? '').toLowerCase().contains(needle) ||
        (names.nickname ?? '').toLowerCase().contains(needle) ||
        (names.phoneBookName ?? '').toLowerCase().contains(needle);
  }

  /// A query that could be a phone number or a `~Helix name`, so a lookup on
  /// the server is worth offering.
  bool get _lookable {
    final text = _text.trim();
    if (text.startsWith('~')) return text.length > 1;
    return RegExp(r'^\+?[\d\s\-().]{7,}$').hasMatch(text);
  }

  Future<void> _lookup() async {
    setState(() => _looking = true);
    final result = await ref.read(candidateLookupProvider).find(_text);
    if (!mounted) return;
    setState(() => _looking = false);
    final found = result.found;
    if (found == null) {
      showHelixSnackBar(context, result.error ?? 'Nobody matches that.');
      return;
    }
    if (widget.exclude.contains(found.account)) {
      showHelixSnackBar(context, 'That person is already in this group.');
      return;
    }
    setState(() {
      _found[found.account] = found;
      _query.clear();
      _text = '';
    });
    if (!widget.selected.contains(found.account)) {
      widget.onToggle(found.account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(groupCandidatesProvider);
    final theme = Theme.of(context);
    final needle = _text.trim().toLowerCase();
    final all = <String, GroupCandidate>{
      ..._found,
      for (final c in candidates.value ?? const <GroupCandidate>[])
        c.account: c,
    };
    final visible =
        [
          for (final c in all.values)
            if (!widget.exclude.contains(c.account) && _matches(c, needle)) c,
        ]..sort(
          (a, b) => a.names.display.toLowerCase().compareTo(
            b.names.display.toLowerCase(),
          ),
        );

    return Column(
      children: [
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HelixSpace.md,
              HelixSpace.xs,
              HelixSpace.md,
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: HelixSpace.xs,
                children: [
                  for (final account in widget.selected)
                    InputChip(
                      key: ValueKey('chip-$account'),
                      label: Text(all[account]?.names.display ?? 'Helix user'),
                      deleteButtonTooltipMessage: 'Remove from selection',
                      onDeleted: () => widget.onToggle(account),
                    ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(HelixSpace.md),
          child: HelixSearchField(
            controller: _query,
            hint: 'Search name, number or ~name',
            onChanged: (value) => setState(() => _text = value),
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (candidates.hasError && all.isEmpty) {
                return const HelixErrorState(
                  message: 'Your people could not be loaded.',
                );
              }
              if (candidates.isLoading && all.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  if (visible.isEmpty && needle.isNotEmpty && !_lookable)
                    HelixNoResults(query: _text.trim()),
                  if (visible.isEmpty && needle.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(HelixSpace.lg),
                      child: Text(
                        'Nobody here yet. Type a phone number or a ~name to '
                        'find someone on Helix.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final c in visible)
                    _PickerRow(
                      candidate: c,
                      selected: widget.selected.contains(c.account),
                      onTap: () => widget.onToggle(c.account),
                    ),
                  if (_lookable && !visible.any((c) => _matches(c, needle)))
                    ListTile(
                      key: const ValueKey('lookup'),
                      leading: _looking
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_search),
                      title: Text('Find "${_text.trim()}" on Helix'),
                      onTap: _looking ? null : _lookup,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final GroupCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: HelixPersonTile(
        key: ValueKey('person-${candidate.account}'),
        person: HelixPersonItem(id: candidate.account, names: candidate.names),
        onTap: onTap,
        trailing: Icon(
          selected ? Icons.check_circle : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
