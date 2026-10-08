import 'package:flutter/material.dart';

/// A generic expandable panel with a header bar and collapsible body.
///
/// Shows an arrow on the left that rotates 90° when expanded.
class CollapsiblePanel extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;
  final Color? headerColor;
  final Widget? trailing;
  final Color? iconColor;

  const CollapsiblePanel({
    super.key,
    required this.title,
    this.icon = Icons.folder_outlined,
    required this.child,
    this.initiallyExpanded = false,
    this.headerColor,
    this.trailing,
    this.iconColor,
  });

  @override
  State<CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<CollapsiblePanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header — always visible.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: widget.headerColor ?? theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.arrow_right, size: 16, color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(widget.icon, size: 16, color: widget.iconColor ?? Colors.white54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleSmall),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        // Body — only visible when expanded.
        if (_expanded) widget.child,
      ],
    );
  }
}
