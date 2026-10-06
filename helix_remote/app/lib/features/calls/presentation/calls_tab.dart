import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/calls/application/call_log.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Starts a call to [peer] from inside the people search.
typedef CallsPeopleSearchCall =
    Future<void> Function(String peer, {required bool video});

/// Builds the Calls tab's people search: the results for [query], with
/// [onCall] to start a call with the person tapped.
///
/// **The seam for the people feature.** The people feature owns the search
/// widget (find someone by name, number or `~Helix name`); features may not
/// import each other, so the router hands it in:
///
/// ```dart
/// CallsTabScreen(peopleSearch: (context, query, onCall) =>
///     PeopleSearchResults(query: query, onPerson: (p) => onCall(p, video: false)))
/// ```
///
/// Without one the tab searches its own call log by name, so the search
/// button always does something useful.
typedef CallsPeopleSearchBuilder =
    Widget Function(
      BuildContext context,
      String query,
      CallsPeopleSearchCall onCall,
    );

/// Calls: recent calls, newest first, and search.
///
/// Calls with the same person in the same direction on one day fold into one
/// row. Tap opens the call detail; the call button calls back (voice or video,
/// as the call was); long-press and swipe delete the entry from the history.
class CallsTabScreen extends ConsumerStatefulWidget {
  const CallsTabScreen({super.key, this.peopleSearch});

  /// The people search plugged in by the router; null uses the log filter.
  final CallsPeopleSearchBuilder? peopleSearch;

  @override
  ConsumerState<CallsTabScreen> createState() => _CallsTabScreenState();
}

class _CallsTabScreenState extends ConsumerState<CallsTabScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _call(String peer, {required bool video}) async {
    final outcome = await ref
        .read(callLogActionsProvider)
        .callBack(peer, video: video);
    if (!mounted || outcome.started) return;
    showHelixSnackBar(
      context,
      outcome.message ?? 'The call could not be placed.',
    );
  }

  Future<void> _delete(CallLogEntry entry) async {
    await ref.read(callLogActionsProvider).delete(entry.callIds);
  }

  Future<bool> _confirmDelete(CallLogEntry entry) => showHelixDestructiveDialog(
    context,
    title: 'Delete from call history?',
    message: entry.callIds.length > 1
        ? 'These ${entry.callIds.length} calls with ${entry.item.title} '
              'will be removed from your call history.'
        : 'This call with ${entry.item.title} will be removed from your call '
              'history.',
    action: 'Delete',
  );

  Future<void> _showActions(CallLogEntry entry) async {
    final choice = await showHelixBottomSheet<_RowAction>(
      context,
      title: entry.item.title,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.call),
            title: const Text('Voice call'),
            onTap: () => Navigator.of(sheet).pop(_RowAction.voice),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Video call'),
            onTap: () => Navigator.of(sheet).pop(_RowAction.video),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(sheet).colorScheme.error,
            ),
            title: Text(
              'Delete from call history',
              style: TextStyle(color: Theme.of(sheet).colorScheme.error),
            ),
            onTap: () => Navigator.of(sheet).pop(_RowAction.delete),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _RowAction.voice:
        await _call(entry.peer, video: false);
      case _RowAction.video:
        await _call(entry.peer, video: true);
      case _RowAction.delete:
        if (await _confirmDelete(entry)) await _delete(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peopleSearch = widget.peopleSearch;
    final searchingPeople =
        peopleSearch != null && _searching && _query.trim().isNotEmpty;
    return Scaffold(
      appBar: HelixSearchAppBar(
        title: 'Calls',
        searching: _searching,
        controller: _controller,
        searchHint: peopleSearch == null ? 'Search calls' : 'Search people',
        onSearchChanged: (value) => setState(() {
          _searching = value;
          if (!value) _query = '';
        }),
        onQueryChanged: (value) => setState(() => _query = value),
      ),
      body: searchingPeople
          ? peopleSearch(context, _query, _call)
          : _CallList(
              query: _searching && peopleSearch == null ? _query : '',
              onOpen: (entry) => context.push(CallRoutes.detail(entry.id)),
              onCall: (entry) => _call(entry.peer, video: entry.video),
              onLongPress: _showActions,
              onSwipeDelete: (entry) async {
                if (!await _confirmDelete(entry)) return false;
                await _delete(entry);
                return true;
              },
            ),
    );
  }
}

enum _RowAction { voice, video, delete }

class _CallList extends ConsumerWidget {
  const _CallList({
    required this.query,
    required this.onOpen,
    required this.onCall,
    required this.onLongPress,
    required this.onSwipeDelete,
  });

  final String query;
  final void Function(CallLogEntry entry) onOpen;
  final void Function(CallLogEntry entry) onCall;
  final void Function(CallLogEntry entry) onLongPress;
  final Future<bool> Function(CallLogEntry entry) onSwipeDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(callLogSearchProvider(query));
    return switch (log) {
      AsyncError() => HelixErrorState(
        message: 'Your calls could not be loaded.',
        onRetry: () => ref.invalidate(callLogProvider),
      ),
      AsyncData(:final value) when value.isEmpty =>
        query.trim().isNotEmpty
            ? HelixNoResults(query: query.trim())
            : const HelixEmptyState(
                icon: Icons.call_outlined,
                title: 'No calls yet',
                message: 'Calls you make and receive will show up here.',
              ),
      AsyncData(:final value) => ListView.builder(
        itemCount: value.length,
        itemExtent: HelixChatListTile.extentFor(
          MediaQuery.textScalerOf(context),
        ),
        itemBuilder: (context, index) {
          final entry = value[index];
          return Dismissible(
            key: ValueKey('call-${entry.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => onSwipeDelete(entry),
            background: const _DeleteBackground(),
            child: HelixCallLogTile(
              item: entry.item,
              onTap: () => onOpen(entry),
              onCallBack: () => onCall(entry),
              onLongPress: () => onLongPress(entry),
            ),
          );
        },
      ),
      _ => const HelixChatListSkeleton(),
    };
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(end: HelixSpace.lg),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}
