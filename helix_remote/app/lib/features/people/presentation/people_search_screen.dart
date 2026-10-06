import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/shared/widgets/people_search_panel.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The standalone people search: a search box over [PeopleSearchPanel].
///
/// The Chats and Calls tabs mount the same panel under their own search
/// field; this screen is for everything else that needs "pick a person" - a
/// `helix://contact` link, a "new chat" button, a "new call" button.
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key, this.mode = PeopleSearchMode.chats});

  final PeopleSearchMode mode;

  @override
  ConsumerState<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: HelixSearchField(
          controller: _controller,
          hint: 'Name, number or ~Helix name',
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (text) => PeopleSearchPanel.submit(ref, text),
        ),
      ),
      body: PeopleSearchPanel(query: _controller.text, mode: widget.mode),
    );
  }
}
