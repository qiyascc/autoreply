import 'package:flutter/cupertino.dart';

import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

/// One missed call, end to end: who called, which rule matched, what was sent, and —
/// when something went wrong — exactly what the failure was.
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.callId});

  final int callId;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  LogDetail? _detail;
  Object? _error;
  int? _retrying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await Native.logEntry(widget.callId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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
    final detail = _detail;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('Call detail')),
      child: SafeArea(
        child: _error != null
            ? EmptyState(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: 'Could not load this call',
                message: '$_error',
              )
            : detail == null
                ? const Center(child: CupertinoActivityIndicator())
                : ListView(
                    children: [
                      _headerCard(context, detail),
                      _outcomeSection(context, detail),
                      ..._messageSections(context, detail),
                      const SizedBox(height: 28),
                    ],
                  ),
      ),
    );
  }

  Widget _headerCard(BuildContext context, LogDetail detail) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(color: colors.fill, shape: BoxShape.circle),
            child: Icon(CupertinoIcons.person_fill, size: 32, color: colors.secondaryLabel),
          ),
          const SizedBox(height: 12),
          Text(detail.display, style: AppText.title.copyWith(color: colors.label)),
          if (detail.contactName != null) ...[
            const SizedBox(height: 2),
            Text(detail.prettyNumber,
                style: AppText.subhead.copyWith(color: colors.secondaryLabel)),
          ],
          const SizedBox(height: 4),
          Text(
            When.stamp(detail.occurredAt),
            style: AppText.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ),
    );
  }

  Widget _outcomeSection(BuildContext context, LogDetail detail) {
    final colors = AppColors.of(context);
    final rows = <Widget>[];

    if (detail.attemptIndex != null) {
      rows.add(InsetTile(
        title: 'Call number',
        value: '#${detail.attemptIndex}',
        leading: GlyphBadge(icon: CupertinoIcons.number, color: colors.tint),
      ));
    }
    if (detail.ruleName != null) {
      rows.add(InsetTile(
        title: 'Rule matched',
        value: detail.ruleName,
        leading: GlyphBadge(icon: CupertinoIcons.slider_horizontal_3, color: colors.tint),
      ));
    }

    final (icon, color, label) = switch (detail.state) {
      'dispatched' => (CupertinoIcons.checkmark_alt, colors.success, 'Replied'),
      'cancelled' => (CupertinoIcons.clear, colors.secondaryLabel, 'Cancelled'),
      'skipped' => (CupertinoIcons.minus, colors.secondaryLabel, 'Skipped'),
      _ => (CupertinoIcons.clock, colors.warning, 'Waiting to reply'),
    };

    rows.add(InsetTile(
      title: label,
      subtitle: detail.cancelReason,
      leading: GlyphBadge(icon: icon, color: color),
    ));

    if (detail.dispatchedAt != null) {
      final gap = (detail.dispatchedAt! - detail.occurredAt) ~/ 1000;
      rows.add(InsetTile(
        title: 'Reply sent after',
        value: When.duration(gap),
        leading: GlyphBadge(icon: CupertinoIcons.timer, color: colors.secondaryLabel),
      ));
    }

    return InsetSection(header: 'Outcome', children: rows);
  }

  List<Widget> _messageSections(BuildContext context, LogDetail detail) {
    final colors = AppColors.of(context);

    if (detail.messages.isEmpty) {
      return [
        InsetSection(
          header: 'Messages',
          children: [
            InsetTile(
              title: 'Nothing was sent',
              subtitle: detail.cancelReason ?? 'No message was generated for this call',
              titleColor: colors.secondaryLabel,
            ),
          ],
        ),
      ];
    }

    return detail.messages
        .map((message) => _messageSection(context, message, colors))
        .toList();
  }

  Widget _messageSection(BuildContext context, OutboxMessage message, AppColors colors) {
    final isWhatsApp = message.channel == 'whatsapp';
    final (statusColor, statusLabel) = switch (message.status) {
      'delivered' => (colors.success, 'Delivered'),
      'sent' => (colors.success, 'Sent'),
      'failed' => (colors.danger, 'Failed'),
      _ => (colors.warning, 'Pending'),
    };

    return InsetSection(
      header: isWhatsApp ? 'WhatsApp' : 'Text message',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.body, style: AppText.body.copyWith(color: colors.label)),
              const SizedBox(height: 12),
              Row(
                children: [
                  StatusDot(color: statusColor, size: 8),
                  const SizedBox(width: 7),
                  Text(statusLabel,
                      style: AppText.footnote.copyWith(color: statusColor)),
                  const Spacer(),
                  Text(
                    When.time(message.sentAt ?? message.scheduledAt),
                    style: AppText.footnote.copyWith(color: colors.secondaryLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (message.error != null)
          InsetTile(
            dense: true,
            title: message.error!,
            titleColor: colors.danger,
            leading: Icon(CupertinoIcons.exclamationmark_circle,
                size: 17, color: colors.danger),
          ),
        if (message.deliveredAt != null)
          InsetTile(
            dense: true,
            title: 'Delivery confirmed',
            value: When.time(message.deliveredAt!),
            titleColor: colors.secondaryLabel,
          ),
        if (message.status == 'failed')
          InsetTile(
            title: _retrying == message.id ? 'Sending…' : 'Try again',
            titleColor: colors.tint,
            onTap: _retrying == null ? () => _retry(message.id) : null,
            trailing: _retrying == message.id
                ? const CupertinoActivityIndicator(radius: 8)
                : null,
          ),
      ],
    );
  }

  Future<void> _retry(int outboxId) async {
    setState(() => _retrying = outboxId);
    try {
      await Native.retry(outboxId);
      await _load();
    } catch (e) {
      if (mounted) await showError(context, e, title: 'Could not send');
      await _load();
    } finally {
      if (mounted) setState(() => _retrying = null);
    }
  }
}
