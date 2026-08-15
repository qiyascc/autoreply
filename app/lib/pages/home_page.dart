import 'package:flutter/cupertino.dart';

import '../main.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_page.dart';
import 'whatsapp_link_page.dart';

/// The overview: is it on, what happened today, and is anything wrong.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onOpenTab});

  final void Function(int index) onOpenTab;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _togglingMaster = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final status = app.status;
    final colors = AppColors.of(context);

    if (status == null) {
      return const CupertinoPageScaffold(child: Center(child: CupertinoActivityIndicator()));
    }

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(largeTitle: Text('Autoreply')),
          CupertinoSliverRefreshControl(onRefresh: app.refresh),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _masterCard(context, status),
                _todayCard(context, status),
                if (!status.health.looksHealthy) _healthWarning(context, status),
                _whatsappCard(context, status),
                _recentSection(context, status),
                _signature(context),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _masterCard(BuildContext context, AppStatus status) {
    final colors = AppColors.of(context);
    final on = status.masterEnabled;

    return InsetSection(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      footer: on
          ? 'Replies go out ${When.duration(status.delaySeconds)} after a call you did not answer.'
          : 'Nothing will be sent while this is off. Calls are not recorded either.',
      children: [
        InsetTile(
          title: on ? 'Watching for missed calls' : 'Paused',
          subtitle: on ? null : 'Turn on to start replying again',
          leading: StatusDot(
            color: on ? colors.success : colors.secondaryLabel,
            pulsing: on,
            size: 11,
          ),
          trailing: _togglingMaster
              ? const CupertinoActivityIndicator(radius: 9)
              : CupertinoSwitch(
                  value: on,
                  onChanged: (value) => _toggleMaster(context, value),
                ),
        ),
      ],
    );
  }

  Future<void> _toggleMaster(BuildContext context, bool value) async {
    setState(() => _togglingMaster = true);
    try {
      await AppScope.of(context).set('master_enabled', value ? '1' : '0');
    } catch (e) {
      if (context.mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => _togglingMaster = false);
    }
  }

  Widget _todayCard(BuildContext context, AppStatus status) {
    final colors = AppColors.of(context);
    final today = status.today;

    return InsetSection(
      header: 'Today',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              StatTile(
                value: today.missed,
                label: 'missed',
                onTap: () => widget.onOpenTab(1),
              ),
              _divider(colors),
              StatTile(
                value: today.sent,
                label: 'replied',
                color: today.sent > 0 ? colors.success : null,
                onTap: () => widget.onOpenTab(1),
              ),
              _divider(colors),
              StatTile(
                value: today.failed,
                label: 'failed',
                color: today.failed > 0 ? colors.danger : null,
                onTap: () => widget.onOpenTab(1),
              ),
            ],
          ),
        ),
        if (today.cancelled > 0 || today.skipped > 0)
          InsetTile(
            dense: true,
            title: _quietOutcomes(today),
            titleColor: colors.secondaryLabel,
            leading: Icon(CupertinoIcons.info_circle, size: 17, color: colors.secondaryLabel),
          ),
      ],
    );
  }

  String _quietOutcomes(DayCounts today) {
    final parts = <String>[];
    if (today.cancelled > 0) {
      parts.add('${today.cancelled} cancelled because you handled the call');
    }
    if (today.skipped > 0) parts.add('${today.skipped} had no matching rule');
    return parts.join(' · ');
  }

  Widget _divider(AppColors colors) =>
      Container(width: 0.5, height: 34, color: colors.separator);

  Widget _healthWarning(BuildContext context, AppStatus status) {
    final colors = AppColors.of(context);
    return InsetSection(
      header: 'Attention',
      footer: 'Android refused to start the background service '
          '${status.health.startRefusals} time(s) in the last 24 hours. On Xiaomi phones '
          'this usually means Autostart or the battery policy was reset.',
      children: [
        InsetTile(
          title: 'Background service is being blocked',
          subtitle: 'Tap to review the phone settings',
          leading: GlyphBadge(icon: CupertinoIcons.exclamationmark, color: colors.warning),
          showChevron: true,
          onTap: () => widget.onOpenTab(3),
        ),
      ],
    );
  }

  Widget _whatsappCard(BuildContext context, AppStatus status) {
    final colors = AppColors.of(context);
    final bridgeMode = status.whatsappMode == 'bridge';
    final linked = bridgeMode ? status.bridgeLinked : status.accessibilityEnabled;

    return InsetSection(
      header: 'WhatsApp',
      children: [
        InsetTile(
          title: bridgeMode ? 'Server bridge' : 'On-device WhatsApp',
          subtitle: linked
              ? (bridgeMode ? 'Linked and ready' : 'Accessibility service is on')
              : (bridgeMode ? 'Not linked yet' : 'Accessibility service is off'),
          leading: GlyphBadge(
            icon: bridgeMode ? CupertinoIcons.antenna_radiowaves_left_right : CupertinoIcons.device_phone_portrait,
            color: linked ? colors.success : colors.secondaryLabel,
          ),
          showChevron: true,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const WhatsAppLinkPage()),
          ),
        ),
      ],
    );
  }

  Widget _recentSection(BuildContext context, AppStatus status) {
    final colors = AppColors.of(context);

    if (status.recent.isEmpty) {
      return InsetSection(
        header: 'Recent',
        children: [
          InsetTile(
            title: 'Nothing yet',
            subtitle: 'Missed calls will show up here',
            titleColor: colors.secondaryLabel,
            leading: Icon(CupertinoIcons.phone_down, size: 20, color: colors.tertiaryLabel),
          ),
        ],
      );
    }

    return InsetSection(
      header: 'Recent',
      children: [
        ...status.recent.map((entry) => _recentTile(context, entry)),
        InsetTile(
          title: 'See all activity',
          titleColor: colors.tint,
          onTap: () => widget.onOpenTab(1),
        ),
      ],
    );
  }

  Widget _recentTile(BuildContext context, LogEntry entry) {
    final colors = AppColors.of(context);
    final (icon, color, summary) = describeEntry(entry, colors);

    return InsetTile(
      title: entry.display,
      subtitle: summary,
      leading: GlyphBadge(icon: icon, color: color),
      value: When.time(entry.occurredAt),
      showChevron: true,
      onTap: () => Navigator.of(context).push(
        CupertinoPageRoute<void>(builder: (_) => DetailPage(callId: entry.id)),
      ),
    );
  }

  Widget _signature(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        children: [
          Text(
            'Qiyas CC',
            style: AppText.footnote.copyWith(
              color: colors.secondaryLabel,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Built for one phone, by its owner.',
            style: AppText.caption.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

/// Shared between Home and the Log so a call reads the same in both places.
(IconData, Color, String) describeEntry(LogEntry entry, AppColors colors) {
  final attempt = entry.attemptIndex;
  final attemptText = attempt == null ? '' : ' · call #$attempt';

  return switch (entry.state) {
    'dispatched' when entry.failedCount > 0 => (
        CupertinoIcons.exclamationmark,
        colors.danger,
        'Failed$attemptText',
      ),
    'dispatched' => (
        entry.channels?.contains('whatsapp') ?? false
            ? CupertinoIcons.chat_bubble_fill
            : CupertinoIcons.text_bubble_fill,
        colors.success,
        '${entry.ruleName ?? 'Replied'}$attemptText',
      ),
    'cancelled' => (
        CupertinoIcons.clear,
        colors.secondaryLabel,
        entry.cancelReason ?? 'Cancelled',
      ),
    'skipped' => (
        CupertinoIcons.minus,
        colors.secondaryLabel,
        entry.cancelReason ?? 'No rule matched',
      ),
    _ => (CupertinoIcons.clock, colors.warning, 'Reply pending$attemptText'),
  };
}
