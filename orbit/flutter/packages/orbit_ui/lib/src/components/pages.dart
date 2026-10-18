import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/bars.dart';
import 'package:orbit_ui/src/theme/pattern_painter.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `Kit.youPage(title, body, opts)` (`js/kit.js`): a You-style page. The
/// flat header on the page colour (`.appbar.flat.you-bar`) with ←, × or
/// nothing before the title, then the body scrolling, 36px of space at the
/// end.
class OrbitYouPage extends StatelessWidget {
  const OrbitYouPage({
    super.key,
    required this.title,
    required this.children,
    this.lead = OrbitAppBarLead.back,
    this.onBack,
    this.actions = const [],
    this.bottom = 36,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final OrbitAppBarLead lead;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final double bottom;

  /// Something fixed under the scrolling body (a composer, a button bar).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return _Page(
      bar: OrbitAppBar(
        title: title,
        lead: lead,
        onLead: onBack ?? () => Navigator.maybePop(context),
        actions: actions,
        background: t.bg,
        rule: false,
      ),
      bottom: bottom,
      footer: footer,
      children: children,
    );
  }
}

/// `Kit.page({ title, body })` (`js/kit.js`): an older-style page. The
/// `--surface` app bar with its rule, then the body scrolling, 40px of space
/// at the end.
class OrbitPage extends StatelessWidget {
  const OrbitPage({
    super.key,
    required this.title,
    required this.children,
    this.lead = OrbitAppBarLead.back,
    this.onBack,
    this.actions = const [],
    this.background,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final OrbitAppBarLead lead;
  final VoidCallback? onBack;
  final List<Widget> actions;

  /// The scroll area's own colour (`style="background:var(--surface)"`).
  final Color? background;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => _Page(
    bar: OrbitAppBar(
      title: title,
      lead: lead,
      onLead: onBack ?? () => Navigator.maybePop(context),
      actions: actions,
    ),
    bottom: 40,
    background: background,
    footer: footer,
    children: children,
  );
}

class _Page extends StatelessWidget {
  const _Page({
    required this.bar,
    required this.children,
    required this.bottom,
    this.background,
    this.footer,
  });

  final Widget bar;
  final List<Widget> children;
  final double bottom;
  final Color? background;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final f = footer;
    Widget body = SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    final bg = background;
    if (bg != null) body = ColoredBox(color: bg, child: body);
    return OrbitPageBackground(
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            Expanded(child: body),
            ?f,
          ],
        ),
      ),
    );
  }
}
