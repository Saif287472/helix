import 'dart:async';

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/components/fields.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/toggles.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';

/// A page with an app bar over a column that scrolls above the keyboard.
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      resizeToAvoidBottomInset: true,
      body: OrbitPageBackground(
        child: Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrbitAppBar(
                title: title,
                onLead: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    OrbitSpace.gutter,
                    16,
                    OrbitSpace.gutter,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runs [send] with the page busy, and closes the page when it answers with
/// no sentence; otherwise gives the sentence back to show.
Future<String?> _submit(
  BuildContext context,
  Future<String?> Function() send,
) async {
  final error = await send();
  if (error == null && context.mounted) Navigator.of(context).pop();
  return error;
}

/// A poll to write: the question, two to twelve answers, and whether people
/// may choose more than one. Unused answers are left empty and ignored.
class OrbitNewPollPage extends StatefulWidget {
  const OrbitNewPollPage({super.key, required this.onSend});

  static const maxOptions = 12;
  static const minOptions = 2;

  /// Sends the poll: null when it was sent, else the sentence to show.
  final FutureOr<String?> Function(HelixPollDraft draft) onSend;

  @override
  State<OrbitNewPollPage> createState() => _OrbitNewPollPageState();
}

class _OrbitNewPollPageState extends State<OrbitNewPollPage> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  var _multiple = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _answers => [
    for (final c in _options)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ];

  bool get _valid {
    final answers = _answers;
    return _question.text.trim().isNotEmpty &&
        answers.length >= OrbitNewPollPage.minOptions &&
        {for (final a in answers) a.toLowerCase()}.length == answers.length;
  }

  Future<void> _send() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = HelixPollDraft(
      question: _question.text.trim(),
      options: _answers,
      multiple: _multiple,
    );
    final error = await _submit(context, () async => widget.onSend(draft));
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final answers = _answers;
    final repeated =
        {for (final a in answers) a.toLowerCase()}.length != answers.length;
    return _Frame(
      title: 'New poll',
      children: [
        OrbitTextField(
          label: 'Question',
          controller: _question,
          maxLength: 200,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const OrbitListLabel('Answers'),
        const SizedBox(height: 8),
        for (final (i, c) in _options.indexed)
          OrbitTextField(
            label: 'Answer ${i + 1}',
            controller: c,
            maxLength: 100,
            onChanged: (_) => setState(() {}),
          ),
        if (_options.length < OrbitNewPollPage.maxOptions)
          Align(
            alignment: Alignment.centerLeft,
            child: OrbitButton(
              label: 'Add an answer',
              icon: OrbitIcons.plus,
              kind: OrbitButtonKind.ghost,
              onPressed: () =>
                  setState(() => _options.add(TextEditingController())),
            ),
          ),
        const SizedBox(height: 8),
        _SwitchRow(
          label: 'Allow several answers',
          on: _multiple,
          onChanged: (v) => setState(() => _multiple = v),
        ),
        if (repeated)
          const OrbitInlineNotice(
            kind: OrbitNoticeKind.warning,
            text: 'Two answers are the same. Each answer must be different.',
          ),
        if (_error != null)
          OrbitInlineNotice(kind: OrbitNoticeKind.error, text: _error!),
        const SizedBox(height: 16),
        OrbitButton(
          label: 'Send poll',
          icon: OrbitIcons.paperPlaneTilt,
          block: true,
          busy: _busy,
          onPressed: _valid ? _send : null,
        ),
      ],
    );
  }
}

/// An event to write: a title, the day and time, and where. The time starts
/// at 18:00 tomorrow and is picked with the phone's own pickers.
class OrbitNewEventPage extends StatefulWidget {
  const OrbitNewEventPage({super.key, required this.now, required this.onSend});

  /// The moment it is now, which the start must come after.
  final DateTime now;

  /// Sends the event: null when it was sent, else the sentence to show.
  final FutureOr<String?> Function(HelixEventDraft draft) onSend;

  @override
  State<OrbitNewEventPage> createState() => _OrbitNewEventPageState();
}

class _OrbitNewEventPageState extends State<OrbitNewEventPage> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  late DateTime _start = DateTime(
    widget.now.year,
    widget.now.month,
    widget.now.day + 1,
    18,
  );
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    super.dispose();
  }

  bool get _future => _start.isAfter(widget.now);
  bool get _valid => _title.text.trim().isNotEmpty && _future;

  Future<void> _pickDate() async {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final day = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(today) ? today : _start,
      firstDate: today,
      lastDate: today.add(const Duration(days: 3650)),
    );
    if (day == null || !mounted) return;
    setState(
      () => _start = DateTime(
        day.year,
        day.month,
        day.day,
        _start.hour,
        _start.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(
      () => _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _send() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = HelixEventDraft(
      title: _title.text.trim(),
      startsAt: _start,
      place: _place.text.trim(),
    );
    final error = await _submit(context, () async => widget.onSend(draft));
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Frame(
      title: 'New event',
      children: [
        OrbitTextField(
          label: 'Title',
          controller: _title,
          maxLength: 100,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        _PickRow(label: 'Day', value: _dayLabel(_start), onTap: _pickDate),
        const SizedBox(height: 10),
        _PickRow(label: 'Time', value: _clock(_start), onTap: _pickTime),
        const SizedBox(height: 14),
        OrbitTextField(
          label: 'Where (optional)',
          controller: _place,
          maxLength: 100,
          onChanged: (_) => setState(() {}),
        ),
        if (!_future)
          const OrbitInlineNotice(
            kind: OrbitNoticeKind.warning,
            text: 'Pick a time that has not passed yet.',
          ),
        if (_error != null)
          OrbitInlineNotice(kind: OrbitNoticeKind.error, text: _error!),
        const SizedBox(height: 16),
        OrbitButton(
          label: 'Send event',
          icon: OrbitIcons.paperPlaneTilt,
          block: true,
          busy: _busy,
          onPressed: _valid ? _send : null,
        ),
      ],
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

String _clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// A labelled value that opens a picker when touched.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: OrbitSpace.target),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(t.rMd),
          ),
          child: Row(
            children: [
              OrbitText(
                label,
                style: t.font.style(size: OrbitType.small, color: t.ink3),
              ),
              const Spacer(),
              OrbitText(
                value,
                style: t.font.style(
                  size: OrbitType.body,
                  weight: 560,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line with a switch at its end; the whole line toggles it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.on,
    required this.onChanged,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      toggled: on,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(!on),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!on),
        child: Container(
          constraints: const BoxConstraints(minHeight: OrbitSpace.target),
          child: Row(
            children: [
              Expanded(
                child: OrbitText(
                  label,
                  style: t.font.style(size: OrbitType.body, color: t.ink),
                ),
              ),
              OrbitSwitch(on: on),
            ],
          ),
        ),
      ),
    );
  }
}
