import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

/// Sortable timeslot table per Windows UI design.
class TimeslotTable extends ConsumerStatefulWidget {
  const TimeslotTable({super.key, this.onSlotTap});

  /// Optional tap handler (e.g. autogen dialog seeks + plays the slot).
  final void Function(Timeslot slot)? onSlotTap;

  static const colors = [
    Color(0xFF42A5F5), Color(0xFFEF5350), Color(0xFF66BB6A),
    Color(0xFFFFA726), Color(0xFFAB47BC), Color(0xFF26C6DA),
    Color(0xFFEC407A), Color(0xFF8D6E63),
  ];

  @override
  ConsumerState<TimeslotTable> createState() => _TimeslotTableState();
}

class _TimeslotTableState extends ConsumerState<TimeslotTable> {
  String? _editingSlotId;
  final _editController = TextEditingController();
  final _editFocusNode = FocusNode();

  _SortKey? _sortKey;
  bool _sortAsc = true;

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onHeaderTap(_SortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
    });
  }

  /// Sorted display list: preserves each row's original index so the "#"
  /// column stays a stable identity and resumes insertion order when sorted
  /// by number.
  List<(Timeslot, int)> _sortedSlots(List<Timeslot> slots) {
    final rows = <(Timeslot, int)>[
      for (var i = 0; i < slots.length; i++) (slots[i], i),
    ];
    final key = _sortKey;
    if (key != null) {
      final asc = _sortAsc;
      rows.sort((a, b) {
        final c = _compare(key, a, b);
        return asc ? c : -c;
      });
    }
    return rows;
  }

  int _compare(_SortKey key, (Timeslot, int) a, (Timeslot, int) b) {
    final (sa, ia) = a;
    final (sb, ib) = b;
    switch (key) {
      case _SortKey.number:
        return ia.compareTo(ib);
      case _SortKey.description:
        String labelOf(Timeslot s) => s.description.isNotEmpty
            ? s.description
            : (s.label.isNotEmpty ? s.label : '');
        return labelOf(sa).toLowerCase().compareTo(labelOf(sb).toLowerCase());
      case _SortKey.filename:
        return sa.filename.toLowerCase().compareTo(sb.filename.toLowerCase());
      case _SortKey.time:
        return sa.inPointMs.compareTo(sb.inPointMs);
      case _SortKey.elapse:
        return sa.elapse.compareTo(sb.elapse);
      case _SortKey.rating:
        return sa.rating.compareTo(sb.rating);
      case _SortKey.remote:
        return (sa.remote ? 1 : 0).compareTo(sb.remote ? 1 : 0);
      case _SortKey.color:
        return sa.colorIndex.compareTo(sb.colorIndex);
    }
  }

  void _startEditing(Timeslot slot) {
    _editingSlotId = slot.id;
    _editController.text =
        slot.description.isNotEmpty ? slot.description : slot.label;
    // Delay focus to next frame so the TextField is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
    });
    setState(() {});
  }

  void _commitEditing(Timeslot slot) {
    if (_editingSlotId != slot.id) return;
    final text = _editController.text.trim();
    ref.read(recordProvider.notifier).updateTimeslot(
        slot.copyWith(description: text, label: text));
    _editingSlotId = null;
    setState(() {});
  }

  void _showContextMenu(
      BuildContext context, Offset position, Timeslot slot, AppStrings l10n) {
    final vm = ref.read(recordProvider.notifier);

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ContextMenuItem(
        position: position,
        onClose: () => entry.remove(),
        items: [
          _MenuItemData(
            icon: Icons.edit_outlined,
            label: l10n.editDescription,
            onTap: () {
              entry.remove();
              _startEditing(slot);
            },
          ),
          _MenuItemData(
            icon: Icons.delete_outline,
            label: l10n.delete,
            isDestructive: true,
            onTap: () {
              entry.remove();
              vm.deleteTimeslot(slot.id);
            },
          ),
        ],
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(recordProvider);
    final vm = ref.read(recordProvider.notifier);
    final theme = Theme.of(context);
    final slots = state.timeslots;
    final rows = _sortedSlots(slots);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Text('${l10n.timeslots} (${slots.length})',
                  style: theme.textTheme.titleSmall),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: theme.colorScheme.surfaceContainer,
          child: Row(
            children: [
              _SortableHeader(
                label: l10n.colNumber,
                width: 30,
                sortKey: _SortKey.number,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.number),
              ),
              _SortableHeader(
                label: l10n.colDescription,
                flex: 2,
                sortKey: _SortKey.description,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.description),
              ),
              _SortableHeader(
                label: l10n.colFilename,
                flex: 1,
                sortKey: _SortKey.filename,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.filename),
              ),
              _SortableHeader(
                label: l10n.colTime,
                flex: 1,
                align: TextAlign.right,
                sortKey: _SortKey.time,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.time),
              ),
              _SortableHeader(
                label: l10n.colElapse,
                width: 50,
                align: TextAlign.right,
                sortKey: _SortKey.elapse,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.elapse),
              ),
              _SortableHeader(
                label: l10n.colRemoteShort,
                width: 70,
                align: TextAlign.center,
                sortKey: _SortKey.remote,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.remote),
              ),
              _SortableHeader(
                label: l10n.colRating,
                width: 60,
                align: TextAlign.center,
                sortKey: _SortKey.rating,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.rating),
              ),
              _SortableHeader(
                label: l10n.colColor,
                width: 40,
                align: TextAlign.center,
                sortKey: _SortKey.color,
                current: _sortKey,
                asc: _sortAsc,
                onTap: () => _onHeaderTap(_SortKey.color),
              ),
              const SizedBox(width: 80),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: slots.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.noTimeslotsYet,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white38)),
                      const SizedBox(height: 4),
                      Text(l10n.useMarkButton,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white24)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) {
                    final (s, _) = rows[i];
                    final rowNo = i + 1;
                    final isSel = s.id == state.selectedTimeslotId;
                    final color = TimeslotTable.colors[s.colorIndex % TimeslotTable.colors.length];
                    final isEditing = _editingSlotId == s.id;

                    return GestureDetector(
                      onSecondaryTapDown: (d) => _showContextMenu(
                          context, d.globalPosition, s, l10n),
                      child: InkWell(
                        onTap: () {
                          vm.selectTimeslot(s.id);
                          widget.onSlotTap?.call(s);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          color: isSel
                              ? theme.colorScheme.primaryContainer.withAlpha(100)
                              : null,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text('$rowNo',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white54)),
                              ),
                              Expanded(
                                flex: 2,
                                child: isEditing
                                    ? TextField(
                                        controller: _editController,
                                        focusNode: _editFocusNode,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(
                                                  horizontal: 4, vertical: 2),
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (_) => _commitEditing(s),
                                        onEditingComplete: () =>
                                            _commitEditing(s),
                                        onTapOutside: (_) => _commitEditing(s),
                                      )
                                    : Tooltip(
                                        message: s.description.isNotEmpty
                                            ? s.description
                                            : (s.label.isNotEmpty
                                                ? s.label
                                                : '${l10n.slotPrefix}$rowNo'),
                                        child: GestureDetector(
                                          onDoubleTap: () =>
                                              _startEditing(s),
                                          child: Text(
                                            s.description.isNotEmpty
                                                ? s.description
                                                : (s.label.isNotEmpty
                                                    ? s.label
                                                    : '${l10n.slotPrefix}$rowNo'),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.w500),
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Tooltip(
                                  message:
                                      s.filename.isNotEmpty ? s.filename : '-',
                                  child: Text(
                                    s.filename.isNotEmpty ? s.filename : '-',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Tooltip(
                                  message: _fmtMs(s.inPointMs),
                                  child: Text(_fmtMs(s.inPointMs),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace'),
                                      textAlign: TextAlign.right),
                                ),
                              ),
                              SizedBox(
                                width: 50,
                                child: Text(
                                  s.elapse > 0
                                      ? '${s.elapse ~/ 1000}.${(s.elapse % 1000 ~/ 100)}s'
                                      : '-',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace'),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Tooltip(
                                message: s.remote ? l10n.remoteTooltip : l10n.localTooltip,
                                child: SizedBox(
                                  width: 70,
                                  child: Center(
                                    child: Icon(
                                      s.remote
                                          ? Icons.public
                                          : Icons.public_off,
                                      size: 14,
                                      color: s.remote
                                          ? Colors.lightBlueAccent
                                          : Colors.white24,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: GestureDetector(
                                  onTap: () => vm.updateTimeslot(
                                      s.copyWith(
                                          rating: (s.rating + 1) % 6)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(
                                        5,
                                        (j) => Icon(
                                              j < s.rating
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 10,
                                              color: j < s.rating
                                                  ? Colors.amber
                                                  : Colors.white24,
                                            )),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => vm.updateTimeslot(
                                      s.copyWith(
                                          colorIndex:
                                              (s.colorIndex + 1) % 8)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(7),
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 14),
                                      tooltip: l10n.editAction,
                                      onPressed: () =>
                                          _startEditing(s),
                                      visualDensity:
                                          VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints(
                                              minWidth: 24,
                                              minHeight: 24),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 14,
                                          color: Colors.red),
                                      tooltip: l10n.deleteAction,
                                      onPressed: () => vm
                                          .deleteTimeslot(s.id),
                                      visualDensity:
                                          VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints(
                                              minWidth: 24,
                                              minHeight: 24),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _fmtMs(int ms) {
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');
    return '$m:$s';
  }
}

class _MenuItemData {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _MenuItemData({
    required this.icon,
    required this.label,
    this.isDestructive = false,
    required this.onTap,
  });
}

/// Column identity for sorting.
enum _SortKey { number, description, filename, time, elapse, remote, rating, color }

/// Sortable column header: tappable to sort (▲/▼ indicator), and shows a
/// hover tooltip when the label is truncated (issues.md).
class _SortableHeader extends StatelessWidget {
  final String label;
  final int? flex;
  final double? width;
  final TextAlign align;
  final _SortKey sortKey;
  final _SortKey? current;
  final bool asc;
  final VoidCallback onTap;

  const _SortableHeader({
    required this.label,
    this.flex,
    this.width,
    this.align = TextAlign.start,
    required this.sortKey,
    required this.current,
    required this.asc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 10, color: Colors.white54);
    final isSort = sortKey == current;
    final alignX = switch (align) {
      TextAlign.right => Alignment.centerRight,
      TextAlign.center => Alignment.center,
      _ => Alignment.centerLeft,
    };
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) {
            final painter = TextPainter(
              text: TextSpan(text: label, style: style),
              maxLines: 1,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: c.maxWidth - (isSort ? 12 : 0));
            final truncated = painter.didExceedMaxLines;
            Widget body = Text(
              label,
              style: style,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
            if (truncated) body = Tooltip(message: label, child: body);
            if (isSort) {
              return Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(child: Align(alignment: alignX, child: body)),
                  Text(asc ? '\u25B2' : '\u25BC',
                      style: const TextStyle(
                          fontSize: 8, color: Colors.white70)),
                ],
              );
            }
            return Align(alignment: alignX, child: body);
          },
        ),
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: child);
    return SizedBox(width: width, child: child);
  }
}

class _ContextMenuItem extends StatefulWidget {
  final Offset position;
  final VoidCallback onClose;
  final List<_MenuItemData> items;

  const _ContextMenuItem({
    required this.position,
    required this.onClose,
    required this.items,
  });

  @override
  State<_ContextMenuItem> createState() => _ContextMenuItemState();
}

class _ContextMenuItemState extends State<_ContextMenuItem> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const menuWidth = 200.0;

    // Clamp position so menu stays on screen.
    final screen = MediaQuery.of(context).size;
    var left = widget.position.dx;
    var top = widget.position.dy;
    if (left + menuWidth > screen.width) left = screen.width - menuWidth - 8;
    if (top + widget.items.length * 40 > screen.height) {
      top = screen.height - widget.items.length * 40 - 8;
    }

    return Stack(
      children: [
        // Dismiss on tap outside.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Menu card.
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: menuWidth,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outline.withAlpha(60),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.items.length; i++) ...[
                    if (i > 0)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: colorScheme.outline.withAlpha(40),
                      ),
                    _HoverableMenuItem(
                      item: widget.items[i],
                      isHovered: _hoveredIndex == i,
                      onHover: (v) => setState(() => _hoveredIndex = v ? i : null),
                      colorScheme: colorScheme,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HoverableMenuItem extends StatefulWidget {
  final _MenuItemData item;
  final bool isHovered;
  final ValueChanged<bool> onHover;
  final ColorScheme colorScheme;

  const _HoverableMenuItem({
    required this.item,
    required this.isHovered,
    required this.onHover,
    required this.colorScheme,
  });

  @override
  State<_HoverableMenuItem> createState() => _HoverableMenuItemState();
}

class _HoverableMenuItemState extends State<_HoverableMenuItem> {
  @override
  Widget build(BuildContext context) {
    final color = widget.item.isDestructive
        ? const Color(0xFFEF5350)
        : widget.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => widget.onHover(true),
      onExit: (_) => widget.onHover(false),
      child: GestureDetector(
        onTap: widget.item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: widget.isHovered
              ? widget.colorScheme.primary.withAlpha(30)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(widget.item.icon, size: 16, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
