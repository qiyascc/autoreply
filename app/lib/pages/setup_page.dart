import 'package:flutter/cupertino.dart';

import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

/// The mandatory first run, and the same checklist re-openable from Settings.
///
/// Permissions alone are not enough on this phone. MIUI keeps its own battery policy and
/// autostart switch, and with either of them wrong the app looks perfectly configured
/// while the OS quietly kills it between the ring and the reply. Those vendor steps are
/// therefore first-class items here, not a footnote.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.onFinished, this.reviewMode = false});

  final Future<void> Function() onFinished;
  final bool reviewMode;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with WidgetsBindingObserver {
  SetupStatus? _status;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Every one of these steps happens in a system screen; re-read on the way back.
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await Native.setupStatus();
      if (mounted) setState(() => _status = status);
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final status = _status;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: widget.reviewMode
          ? const CupertinoNavigationBar(middle: Text('Phone setup'))
          : null,
      child: SafeArea(
        child: status == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                children: [
                  if (!widget.reviewMode) _welcome(colors, status),
                  _permissionsSection(colors, status),
                  _backgroundSection(colors, status),
                  if (status.vendorSteps.isNotEmpty) _vendorSection(colors, status),
                  _finishSection(colors, status),
                  const SizedBox(height: 36),
                ],
              ),
      ),
    );
  }

  Widget _welcome(AppColors colors, SetupStatus status) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 8),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset('assets/brand/icon_256.png', width: 78, height: 78),
            ),
            const SizedBox(height: 18),
            Text('Autoreply',
                style: AppText.largeTitle.copyWith(color: colors.label)),
            const SizedBox(height: 6),
            Text(
              'Answers the calls you miss, so you don\'t have to.',
              textAlign: TextAlign.center,
              style: AppText.callout.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: 10),
            Text(
              'A few permissions first. Every one of them is used for exactly one thing, '
              'explained below.',
              textAlign: TextAlign.center,
              style: AppText.footnote.copyWith(color: colors.tertiaryLabel),
            ),
          ],
        ),
      );

  Widget _permissionsSection(AppColors colors, SetupStatus status) => InsetSection(
        header: 'Permissions',
        margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        footer: status.allPermissionsGranted
            ? null
            : 'Tap below to grant the ones still missing.',
        children: [
          ...status.permissions.map(
            (p) => InsetTile(
              title: p.label,
              subtitle: p.why,
              leading: GlyphBadge(
                icon: p.granted ? CupertinoIcons.checkmark_alt : CupertinoIcons.circle,
                color: p.granted ? colors.success : colors.secondaryLabel,
              ),
            ),
          ),
          if (!status.allPermissionsGranted)
            InsetTile(
              title: 'Grant permissions',
              titleColor: colors.tint,
              onTap: () async {
                await Native.requestPermissions();
                await _load();
              },
            ),
        ],
      );

  Widget _backgroundSection(AppColors colors, SetupStatus status) => InsetSection(
        header: 'Background access',
        footer: 'Android puts sleeping apps into Doze. Both of these are needed to fire a '
            'reply one minute after a call while the phone is idle.',
        children: [
          InsetTile(
            title: 'Unrestricted battery use',
            subtitle: status.batteryUnrestricted
                ? 'Granted'
                : 'Required — Android will otherwise delay or drop the reply',
            leading: GlyphBadge(
              icon: status.batteryUnrestricted
                  ? CupertinoIcons.checkmark_alt
                  : CupertinoIcons.bolt_fill,
              color: status.batteryUnrestricted ? colors.success : colors.warning,
            ),
            showChevron: !status.batteryUnrestricted,
            onTap: status.batteryUnrestricted
                ? null
                : () => Native.openSystemPage('battery'),
          ),
          InsetTile(
            title: 'Exact alarms',
            subtitle: status.exactAlarms
                ? 'Granted'
                : 'Required — without it the one-minute timer becomes approximate',
            leading: GlyphBadge(
              icon: status.exactAlarms
                  ? CupertinoIcons.checkmark_alt
                  : CupertinoIcons.alarm_fill,
              color: status.exactAlarms ? colors.success : colors.warning,
            ),
            showChevron: !status.exactAlarms,
            onTap: status.exactAlarms ? null : () => Native.openSystemPage('exact_alarms'),
          ),
        ],
      );

  Widget _vendorSection(AppColors colors, SetupStatus status) => InsetSection(
        header: '${status.manufacturer} specific',
        footer: 'These are not Android permissions and cannot be checked automatically. '
            'On ${status.model} they are the difference between the app working and '
            'silently doing nothing.',
        children: status.vendorSteps
            .map(
              (step) => InsetTile(
                title: step.title,
                subtitle: step.detail,
                leading: GlyphBadge(
                  icon: step.manualOnly
                      ? CupertinoIcons.hand_point_right_fill
                      : CupertinoIcons.arrow_up_right_square_fill,
                  color: colors.warning,
                ),
                showChevron: !step.manualOnly,
                onTap: step.manualOnly ? null : () => Native.openSystemPage(step.key),
              ),
            )
            .toList(),
      );

  Widget _finishSection(AppColors colors, SetupStatus status) {
    if (widget.reviewMode) {
      return InsetSection(
        footer: 'Running on ${status.manufacturer} ${status.model}, Android '
            '${status.androidVersion}.',
        children: [
          InsetTile(
            title: 'Open app info in Android settings',
            titleColor: colors.tint,
            onTap: () => Native.openSystemPage('app_settings'),
          ),
        ],
      );
    }

    final ready = status.ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        children: [
          PrimaryButton(
            label: ready ? 'Start watching for calls' : 'Grant what is missing first',
            busy: _finishing,
            onPressed: ready ? _finish : null,
          ),
          const SizedBox(height: 14),
          Text(
            'Qiyas CC',
            style: AppText.caption.copyWith(
              color: colors.tertiaryLabel,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      await Native.completeSetup();
      await widget.onFinished();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }
}
