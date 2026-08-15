import 'package:flutter/cupertino.dart';

import '../main.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';
import 'numbers_page.dart';
import 'setup_page.dart';
import 'whatsapp_link_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<SimCard> _sims = const [];

  @override
  void initState() {
    super.initState();
    // A missing SIM list only hides the dual-SIM picker; it is not worth an error dialog.
    Native.sims().then(
      (sims) {
        if (mounted) setState(() => _sims = sims);
      },
      onError: (_) {},
    );
  }

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
          const CupertinoSliverNavigationBar(largeTitle: Text('Settings')),
          CupertinoSliverRefreshControl(onRefresh: app.refresh),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _appearance(app, status, colors),
                _timing(app, status, colors),
                _counter(app, status, colors),
                _quietHours(app, status, colors),
                _dailySummary(app, status, colors),
                _delivery(app, status, colors),
                if (_sims.length > 1) _simSection(app, status, colors),
                _filters(status, colors),
                _phoneSetup(status, colors),
                _testSection(colors),
                _about(status, colors),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- appearance ------------------------------------------------------------------

  Widget _appearance(AppController app, AppStatus status, AppColors colors) => InsetSection(
        header: 'Appearance',
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: status.theme,
              onValueChanged: (v) => v == null ? null : app.set('theme', v),
              children: const {
                'system': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('System', style: TextStyle(fontSize: 13)),
                ),
                'light': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Light', style: TextStyle(fontSize: 13)),
                ),
                'dark': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Dark', style: TextStyle(fontSize: 13)),
                ),
              },
            ),
          ),
        ],
      );

  // ---- timing -----------------------------------------------------------------------

  Widget _timing(AppController app, AppStatus status, AppColors colors) => InsetSection(
        header: 'Timing',
        footer: 'The wait gives you a chance to call back first. If you do, the reply is '
            'cancelled automatically.',
        children: [
          InsetTile(
            title: 'Wait before replying',
            value: When.duration(status.delaySeconds),
            leading: GlyphBadge(icon: CupertinoIcons.timer, color: colors.tint),
            showChevron: true,
            onTap: () => _pickFromList(
              title: 'Wait before replying',
              options: const [30, 60, 120, 300, 600],
              labels: const ['30 seconds', '1 minute', '2 minutes', '5 minutes', '10 minutes'],
              current: status.delaySeconds,
              onPicked: (v) => app.set('default_delay_seconds', '$v'),
            ),
          ),
          InsetTile(
            title: 'Ignore repeats within',
            value: status.dedupeMinutes == 0
                ? 'Off'
                : '${status.dedupeMinutes} min',
            subtitle: 'Stops a second reply if they call again straight away',
            leading: GlyphBadge(icon: CupertinoIcons.arrow_2_squarepath, color: colors.tint),
            showChevron: true,
            onTap: () => _pickFromList(
              title: 'Ignore repeats within',
              options: const [0, 5, 10, 30, 60],
              labels: const ['Off', '5 minutes', '10 minutes', '30 minutes', '1 hour'],
              current: status.dedupeMinutes,
              onPicked: (v) => app.set('dedupe_minutes', '$v'),
            ),
          ),
        ],
      );

  // ---- counter ----------------------------------------------------------------------

  Widget _counter(AppController app, AppStatus status, AppColors colors) {
    const options = ['answered', '6h', '12h', '24h', '7d', 'never'];
    const labels = [
      'When we talk',
      'After 6 hours',
      'After 12 hours',
      'After 24 hours',
      'After 7 days',
      'Never',
    ];
    final label = labels[options.indexOf(status.counterResetMode).clamp(0, labels.length - 1)];

    return InsetSection(
      header: 'Call counter',
      footer: switch (status.counterResetMode) {
        'answered' =>
          'The count resets once you actually speak. Someone you spoke to this morning '
              'starts again at call #1 tonight.',
        'never' => 'Counts every missed call from that number, forever.',
        _ => 'The count resets after the chosen amount of time with no contact.',
      },
      children: [
        InsetTile(
          title: 'Reset the count',
          value: label,
          leading: GlyphBadge(icon: CupertinoIcons.number, color: colors.tint),
          showChevron: true,
          onTap: () => _pickFromList<String>(
            title: 'Reset the count',
            options: options,
            labels: labels,
            current: status.counterResetMode,
            onPicked: (v) => app.set('counter_reset_mode', v),
          ),
        ),
      ],
    );
  }

  // ---- quiet hours -------------------------------------------------------------------

  Widget _quietHours(AppController app, AppStatus status, AppColors colors) => InsetSection(
        header: 'Quiet hours',
        footer: status.quietEnabled
            ? 'Nothing is sent between ${When.minuteOfDay(status.quietStart)} and '
                '${When.minuteOfDay(status.quietEnd)}.'
            : 'Replies go out at any hour.',
        children: [
          InsetTile(
            title: 'Stay silent overnight',
            leading: GlyphBadge(icon: CupertinoIcons.moon_fill, color: colors.tint),
            trailing: CupertinoSwitch(
              value: status.quietEnabled,
              onChanged: (v) => app.set('quiet_enabled', v ? '1' : '0'),
            ),
          ),
          if (status.quietEnabled) ...[
            InsetTile(
              title: 'From',
              value: When.minuteOfDay(status.quietStart),
              showChevron: true,
              onTap: () => _pickTime(
                current: status.quietStart,
                onPicked: (v) => app.set('quiet_start', '$v'),
              ),
            ),
            InsetTile(
              title: 'To',
              value: When.minuteOfDay(status.quietEnd),
              showChevron: true,
              onTap: () => _pickTime(
                current: status.quietEnd,
                onPicked: (v) => app.set('quiet_end', '$v'),
              ),
            ),
          ],
        ],
      );

  // ---- daily summary -----------------------------------------------------------------

  Widget _dailySummary(AppController app, AppStatus status, AppColors colors) => InsetSection(
        header: 'Daily summary',
        footer: status.dailySummaryEnabled
            ? 'One notification at ${When.minuteOfDay(status.dailySummaryMinute)} with the '
                'day\'s activity. Tapping it opens the log for that day. Quiet days are skipped.'
            : 'No end-of-day notification.',
        children: [
          InsetTile(
            title: 'Send a daily summary',
            leading: GlyphBadge(icon: CupertinoIcons.bell_fill, color: colors.tint),
            trailing: CupertinoSwitch(
              value: status.dailySummaryEnabled,
              onChanged: (v) => app.set('daily_summary_enabled', v ? '1' : '0'),
            ),
          ),
          if (status.dailySummaryEnabled)
            InsetTile(
              title: 'Time',
              value: When.minuteOfDay(status.dailySummaryMinute),
              showChevron: true,
              onTap: () => _pickTime(
                current: status.dailySummaryMinute,
                onPicked: (v) => app.set('daily_summary_minute', '$v'),
              ),
            ),
        ],
      );

  // ---- delivery ----------------------------------------------------------------------

  Widget _delivery(AppController app, AppStatus status, AppColors colors) {
    final bridge = status.whatsappMode == 'bridge';
    return InsetSection(
      header: 'WhatsApp delivery',
      footer: bridge
          ? 'Messages are sent by the server, silently, even with the phone locked. '
              'Nothing appears on screen.'
          : 'Opens WhatsApp on this phone and taps send for you. Needs the screen unlocked, '
              'and you will see it happen.',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: CupertinoSlidingSegmentedControl<String>(
            groupValue: status.whatsappMode,
            onValueChanged: (v) => v == null ? null : app.set('whatsapp_mode', v),
            children: const {
              'bridge': Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Server bridge', style: TextStyle(fontSize: 13)),
              ),
              'device': Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('On this phone', style: TextStyle(fontSize: 13)),
              ),
            },
          ),
        ),
        InsetTile(
          title: bridge ? 'WhatsApp link' : 'Accessibility service',
          subtitle: bridge
              ? (status.bridgeLinked ? 'Linked' : 'Not linked yet')
              : (status.accessibilityEnabled ? 'Enabled' : 'Not enabled'),
          leading: GlyphBadge(
            icon: CupertinoIcons.link,
            color: (bridge ? status.bridgeLinked : status.accessibilityEnabled)
                ? colors.success
                : colors.secondaryLabel,
          ),
          showChevron: true,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const WhatsAppLinkPage()),
          ),
        ),
      ],
    );
  }

  // ---- SIM ----------------------------------------------------------------------------

  Widget _simSection(AppController app, AppStatus status, AppColors colors) {
    final current = _sims.firstWhere(
      (s) => s.id == status.simSubscriptionId,
      orElse: () => const SimCard(id: -1, label: 'Default'),
    );

    return InsetSection(
      header: 'SIM',
      footer: 'Which line text replies are sent from.',
      children: [
        InsetTile(
          title: 'Send texts from',
          value: current.label,
          leading: GlyphBadge(icon: CupertinoIcons.antenna_radiowaves_left_right, color: colors.tint),
          showChevron: true,
          onTap: () => _pickFromList<int>(
            title: 'Send texts from',
            options: [-1, ..._sims.map((s) => s.id)],
            labels: ['Default', ..._sims.map((s) => s.label)],
            current: status.simSubscriptionId,
            onPicked: (v) => app.set('sim_subscription_id', '$v'),
          ),
        ),
      ],
    );
  }

  // ---- filters -------------------------------------------------------------------------

  Widget _filters(AppStatus status, AppColors colors) {
    final label = switch (status.listMode) {
      'blocklist' => 'Block list',
      'allowlist' => 'Allow list only',
      _ => 'Off',
    };

    return InsetSection(
      header: 'Who gets replies',
      children: [
        InsetTile(
          title: 'Number list',
          value: label,
          leading: GlyphBadge(icon: CupertinoIcons.person_crop_circle_badge_xmark, color: colors.tint),
          showChevron: true,
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const NumbersPage()),
          ),
        ),
      ],
    );
  }

  // ---- phone setup ----------------------------------------------------------------------

  Widget _phoneSetup(AppStatus status, AppColors colors) => InsetSection(
        header: 'Phone',
        footer: status.health.looksHealthy
            ? 'Seen ${status.health.ringsSeen} rings and fired '
                '${status.health.alarmsFired} reply alarms in the last 24 hours.'
            : 'Android blocked the background service '
                '${status.health.startRefusals} time(s) recently — worth re-checking.',
        children: [
          InsetTile(
            title: 'Permissions & background access',
            subtitle: status.health.looksHealthy ? 'Everything looks healthy' : 'Needs attention',
            leading: GlyphBadge(
              icon: CupertinoIcons.checkmark_shield_fill,
              color: status.health.looksHealthy ? colors.success : colors.warning,
            ),
            showChevron: true,
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (_) => SetupPage(reviewMode: true, onFinished: () async {}),
              ),
            ),
          ),
        ],
      );

  // ---- test -------------------------------------------------------------------------------

  Widget _testSection(AppColors colors) => InsetSection(
        header: 'Try it',
        footer: 'Sends a real message right now, so you can confirm delivery works before '
            'you rely on it.',
        children: [
          InsetTile(
            title: 'Send a test message',
            leading: GlyphBadge(icon: CupertinoIcons.paperplane_fill, color: colors.tint),
            showChevron: true,
            onTap: _showTestSheet,
          ),
        ],
      );

  Future<void> _showTestSheet() async {
    final numberController = TextEditingController();
    final textController =
        TextEditingController(text: 'Test from Autoreply. Everything is working.');
    var channel = 'sms';
    var sending = false;

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final colors = AppColors.of(sheetContext);
          return Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 14),
                  Text('Send a test',
                      style: AppText.headline.copyWith(color: colors.label)),
                  InsetSection(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: CupertinoSlidingSegmentedControl<String>(
                          groupValue: channel,
                          onValueChanged: (v) =>
                              setSheetState(() => channel = v ?? 'sms'),
                          children: const {
                            'sms': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Message', style: TextStyle(fontSize: 13)),
                            ),
                            'whatsapp': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('WhatsApp', style: TextStyle(fontSize: 13)),
                            ),
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CupertinoTextField.borderless(
                          controller: numberController,
                          placeholder: 'Phone number',
                          keyboardType: TextInputType.phone,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CupertinoTextField.borderless(
                          controller: textController,
                          placeholder: 'Message',
                          maxLines: 3,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: PrimaryButton(
                      label: 'Send now',
                      busy: sending,
                      onPressed: () async {
                        setSheetState(() => sending = true);
                        try {
                          await Native.testSend(
                            channel: channel,
                            to: numberController.text,
                            text: textController.text,
                          );
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                          if (mounted) {
                            await showCupertinoDialog<void>(
                              context: context,
                              builder: (c) => CupertinoAlertDialog(
                                title: const Text('Sent'),
                                content: const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text('Check the other phone.'),
                                ),
                                actions: [
                                  CupertinoDialogAction(
                                    isDefaultAction: true,
                                    onPressed: () => Navigator.of(c).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        } catch (e) {
                          setSheetState(() => sending = false);
                          if (sheetContext.mounted) {
                            await showError(sheetContext, e, title: 'Could not send');
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    numberController.dispose();
    textController.dispose();
  }

  // ---- about ---------------------------------------------------------------------------------

  Widget _about(AppStatus status, AppColors colors) => Column(
        children: [
          InsetSection(
            header: 'About',
            children: [
              InsetTile(
                title: 'Autoreply',
                value: 'Version ${status.appVersion}',
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset('assets/brand/icon_256.png', width: 29, height: 29),
                ),
              ),
              InsetTile(
                title: 'Bridge',
                value: Uri.parse(status.bridgeUrl).host,
                leading: GlyphBadge(
                  icon: CupertinoIcons.cloud_fill,
                  color: status.bridgeLinked ? colors.success : colors.secondaryLabel,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: Column(
              children: [
                Text(
                  'Qiyas CC',
                  style: AppText.subhead.copyWith(
                    color: colors.secondaryLabel,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Designed and built by Qiyas CC.\nctm.ubermensch.cc',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: colors.tertiaryLabel, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      );

  // ---- shared pickers -----------------------------------------------------------------------

  Future<void> _pickFromList<T>({
    required String title,
    required List<T> options,
    required List<String> labels,
    required T current,
    required Future<void> Function(T) onPicked,
  }) async {
    var index = options.indexOf(current);
    if (index < 0) index = 0;
    var selected = index;

    final colors = AppColors.of(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 280,
        color: colors.card,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: AppText.headline.copyWith(color: colors.label)),
                    CupertinoButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(initialItem: index),
                  itemExtent: 36,
                  onSelectedItemChanged: (i) => selected = i,
                  children: labels.map((l) => Center(child: Text(l))).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await onPicked(options[selected]);
  }

  Future<void> _pickTime({
    required int current,
    required Future<void> Function(int) onPicked,
  }) async {
    final values = List.generate(96, (i) => i * 15);
    await _pickFromList<int>(
      title: 'Time',
      options: values,
      labels: values.map(When.minuteOfDay).toList(),
      current: values.reduce((a, b) => (a - current).abs() <= (b - current).abs() ? a : b),
      onPicked: onPicked,
    );
  }
}
