import 'package:flutter/cupertino.dart';

import '../native.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_page.dart';
import 'home_page.dart' show describeEntry;

/// Everything that has happened, newest first, grouped by day.
class LogPage extends StatefulWidget {
  const LogPage({super.key, this.initialDayFilter});

  final int? initialDayFilter;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String _filter = 'all';
  int? _dayFilter;
  List<LogEntry>? _entries;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _dayFilter = widget.initialDayFilter;
    _load();
  }

  @override
  void didUpdateWidget(LogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDayFilter != widget.initialDayFilter) {
      _dayFilter = widget.initialDayFilter;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final entries = await Native.log(
        limit: 300,
        dayStart: _dayFilter,
        status: _filter == 'all' ? null : _filter,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Log'),
            trailing: _entries != null && _entries!.isNotEmpty
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _confirmClear,
                    child: const Text('Clear'),
                  )
                : null,
          ),
          CupertinoSliverRefreshControl(onRefresh: _load),
          SliverToBoxAdapter(child: _controls(colors)),
          ..._body(colors),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _controls(AppColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            CupertinoSlidingSegmentedControl<String>(
              groupValue: _filter,
              onValueChanged: (value) {
                if (value == null) return;
                setState(() => _filter = value);
                _load();
              },
              children: const {
                'all': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                  child: Text('All'),
                ),
                'sent': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                  child: Text('Sent'),
                ),
                'failed': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                  child: Text('Failed'),
                ),
              },
            ),
            if (_dayFilter != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Showing ${When.dayLabel(_dayFilter!)}',
                      style: AppText.footnote.copyWith(color: colors.secondaryLabel),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      onPressed: () {
                        setState(() => _dayFilter = null);
                        _load();
                      },
                      child: Text('Show all',
                          style: AppText.footnote.copyWith(color: colors.tint)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  List<Widget> _body(AppColors colors) {
    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'Could not load the log',
            message: '$_error',
          ),
        ),
      ];
    }

    final entries = _entries;
    if (entries == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      ];
    }

    if (entries.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: CupertinoIcons.tray,
            title: _filter == 'all' ? 'No activity yet' : 'Nothing matches this filter',
            message: _filter == 'all'
                ? 'Missed calls and the replies they triggered will appear here.'
                : null,
          ),
        ),
      ];
    }

    // Group by calendar day so the list reads like a timeline rather than a dump.
    final groups = <int, List<LogEntry>>{};
    for (final entry in entries) {
      final d = DateTime.fromMillisecondsSinceEpoch(entry.occurredAt);
      final key = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return groups.entries
        .map((group) => SliverToBoxAdapter(
              child: InsetSection(
                header: When.dayLabel(group.key),
                children: group.value.map((e) => _tile(e, colors)).toList(),
              ),
            ))
        .toList();
  }

  Widget _tile(LogEntry entry, AppColors colors) {
    final (icon, color, summary) = describeEntry(entry, colors);
    return InsetTile(
      title: entry.display,
      subtitle: summary,
      leading: GlyphBadge(icon: icon, color: color),
      value: When.time(entry.occurredAt),
      showChevron: true,
      onTap: () async {
        await Navigator.of(context).push(
          CupertinoPageRoute<void>(builder: (_) => DetailPage(callId: entry.id)),
        );
        _load();
      },
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Clear history?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'This deletes every recorded call and reply. Your rules and settings are kept.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await Native.clearHistory();
      await _load();
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }
}
