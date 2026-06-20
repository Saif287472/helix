import 'package:flutter/material.dart';
import 'package:helix/ui/app_theme.dart';

/// A scaffold that constrains its body to [HelixTokens.contentMaxWidth] and
/// centres it horizontally, preventing overly-wide layouts on desktop.
class HelixPageScaffold extends StatelessWidget {
  const HelixPageScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.maxWidth = HelixTokens.contentMaxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: HelixTokens.space16),
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding, child: body),
        ),
      ),
    );
  }
}
