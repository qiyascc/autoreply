import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

/// Links WhatsApp to the bridge with an 8-character pairing code.
///
/// A QR would be absurd here: the phone showing the code is the phone that has to scan
/// it. The code path is the primary one; the one-time browser link exists for the case
/// where you would rather pair from a laptop.
class WhatsAppLinkPage extends StatefulWidget {
  const WhatsAppLinkPage({super.key});

  @override
  State<WhatsAppLinkPage> createState() => _WhatsAppLinkPageState();
}

class _WhatsAppLinkPageState extends State<WhatsAppLinkPage> {
  final TextEditingController _inviteController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  PairingSession? _session;
  String? _pairingCode;
  String _sessionState = 'none';
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshSession();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _inviteController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _refreshSession() async {
    try {
      final json = await Native.bridgeSessionStatus();
      if (!mounted) return;
      setState(() => _sessionState = json['status'] as String? ?? 'none');
      if (_sessionState == 'connected') {
        _poll?.cancel();
        await AppScope.of(context).refresh();
      }
    } catch (_) {
      // Offline is a normal state here; the UI already says "not linked".
    }
  }

  /// Polls while pairing is in flight. The browser page gets live SSE; the phone is
  /// in the foreground for a few seconds at most, so polling is simpler and enough.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshSession());
  }

  @override
  Widget build(BuildContext context) {
    final status = AppScope.of(context).status;
    final colors = AppColors.of(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('WhatsApp')),
      child: SafeArea(
        child: status == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                children: status.whatsappMode == 'device'
                    ? _deviceMode(status, colors)
                    : _bridgeMode(status, colors),
              ),
      ),
    );
  }

  // ---- on-device mode ---------------------------------------------------------------

  List<Widget> _deviceMode(AppStatus status, AppColors colors) => [
        InsetSection(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          header: 'On-device delivery',
          footer: 'This mode opens WhatsApp on screen and taps Send. It needs the phone '
              'unlocked at that moment, so it will not work while the device is in your '
              'pocket. Switch to the server bridge in Settings for silent delivery.',
          children: [
            InsetTile(
              title: 'WhatsApp installed',
              leading: GlyphBadge(
                icon: CupertinoIcons.chat_bubble_fill,
                color: status.whatsappInstalled ? colors.success : colors.danger,
              ),
              value: status.whatsappInstalled ? 'Yes' : 'No',
            ),
            InsetTile(
              title: 'Accessibility service',
              subtitle: status.accessibilityEnabled
                  ? 'Autoreply can tap Send for you'
                  : 'Tap to enable in Android settings',
              leading: GlyphBadge(
                icon: CupertinoIcons.hand_draw_fill,
                color: status.accessibilityEnabled ? colors.success : colors.warning,
              ),
              showChevron: !status.accessibilityEnabled,
              onTap: status.accessibilityEnabled
                  ? null
                  : () => Native.openSystemPage('accessibility'),
            ),
          ],
        ),
      ];

  // ---- bridge mode -------------------------------------------------------------------

  List<Widget> _bridgeMode(AppStatus status, AppColors colors) {
    final registered = status.settings['bridge_token']?.isNotEmpty ?? false;

    if (!registered) return [_inviteStep(colors)];
    if (_sessionState == 'connected') return _connectedStep(status, colors);
    if (_session != null) return [_codeStep(colors)];
    return [_phoneStep(status, colors)];
  }

  Widget _inviteStep(AppColors colors) => Column(
        children: [
          _hero(
            colors,
            icon: CupertinoIcons.ticket_fill,
            title: 'Register this phone',
            message: 'Enter the invite code from the bridge. It works once.',
          ),
          InsetSection(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoTextField.borderless(
                  controller: _inviteController,
                  placeholder: 'XXXX-XXXX-XXXX',
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  style: AppText.body.copyWith(
                    color: colors.label,
                    letterSpacing: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: PrimaryButton(
              label: 'Register',
              busy: _busy,
              onPressed: () => _run(() async {
                final updated = await Native.bridgeRegister(
                  _inviteController.text.trim(),
                  'Autoreply phone',
                );
                if (mounted) AppScope.of(context).adopt(updated);
              }),
            ),
          ),
        ],
      );

  Widget _phoneStep(AppStatus status, AppColors colors) => Column(
        children: [
          _hero(
            colors,
            icon: CupertinoIcons.phone_fill,
            title: 'Which WhatsApp number?',
            message: 'The number replies will be sent from — normally this phone\'s own '
                'WhatsApp account.',
          ),
          InsetSection(
            footer: 'Include the country code, for example +90 532 111 22 33.',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CupertinoTextField.borderless(
                  controller: _phoneController,
                  placeholder: '+${status.countryCode} …',
                  keyboardType: TextInputType.phone,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  style: AppText.body.copyWith(color: colors.label),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: PrimaryButton(
              label: 'Get pairing code',
              busy: _busy,
              onPressed: () => _run(() async {
                final session = await Native.bridgeCreateSession(_phoneController.text.trim());
                if (!mounted) return;
                setState(() => _session = session);
                _startPolling();
                await _requestCode();
              }),
            ),
          ),
        ],
      );

  Widget _codeStep(AppColors colors) {
    final code = _pairingCode;

    return Column(
      children: [
        _hero(
          colors,
          icon: CupertinoIcons.number_square_fill,
          title: 'Enter this in WhatsApp',
          message: null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: code == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: CupertinoActivityIndicator(),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final char in code.split(''))
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 34,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.fill,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          char,
                          style: AppText.title.copyWith(
                            color: colors.label,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        InsetSection(
          header: 'How',
          children: const [
            _Step(number: 1, text: 'Open WhatsApp on this phone'),
            _Step(number: 2, text: 'Go to Settings › Linked devices'),
            _Step(number: 3, text: 'Tap Link a device, then Link with phone number instead'),
            _Step(number: 4, text: 'Type the code above'),
          ],
        ),
        InsetSection(
          footer: 'Waiting for WhatsApp to confirm. This page updates by itself.',
          children: [
            InsetTile(
              title: switch (_sessionState) {
                'pairing' => 'Waiting for the code to be entered',
                'disconnected' => 'Reconnecting…',
                'logged_out' => 'Session ended — start again',
                _ => 'Connecting…',
              },
              leading: StatusDot(
                color: _sessionState == 'logged_out' ? colors.danger : colors.warning,
                pulsing: _sessionState != 'logged_out',
                size: 11,
              ),
            ),
            if (_session != null)
              InsetTile(
                title: 'Copy browser link instead',
                subtitle: 'Pair from a computer with a QR code',
                titleColor: colors.tint,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: _session!.linkUrl));
                  if (mounted) {
                    await showCupertinoDialog<void>(
                      context: context,
                      builder: (c) => CupertinoAlertDialog(
                        title: const Text('Link copied'),
                        content: const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Open it in a browser within 10 minutes. It works once.',
                          ),
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
                },
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: CupertinoButton(
            onPressed: () => setState(() {
              _session = null;
              _pairingCode = null;
              _poll?.cancel();
            }),
            child: const Text('Start over'),
          ),
        ),
      ],
    );
  }

  List<Widget> _connectedStep(AppStatus status, AppColors colors) => [
        _hero(
          colors,
          icon: CupertinoIcons.checkmark_seal_fill,
          title: 'WhatsApp is linked',
          message: 'Replies will be sent silently by the bridge, even with the phone locked.',
          iconColor: colors.success,
        ),
        InsetSection(
          children: [
            InsetTile(
              title: 'Status',
              value: 'Connected',
              leading: StatusDot(color: colors.success, size: 11),
            ),
            InsetTile(
              title: 'Bridge',
              value: Uri.parse(status.bridgeUrl).host,
              leading: GlyphBadge(icon: CupertinoIcons.cloud_fill, color: colors.tint),
            ),
          ],
        ),
        InsetSection(
          footer: 'Unlinking logs the bridge out of WhatsApp. You can pair again any time.',
          children: [
            InsetTile(
              title: 'Unlink WhatsApp',
              titleColor: colors.danger,
              onTap: () => _run(() async {
                final updated = await Native.bridgeLogout();
                if (!mounted) return;
                AppScope.of(context).adopt(updated);
                setState(() {
                  _session = null;
                  _pairingCode = null;
                  _sessionState = 'none';
                });
              }),
            ),
          ],
        ),
      ];

  Future<void> _requestCode() async {
    // The socket may still be handshaking; retry briefly rather than showing an error.
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        final code = await Native.bridgePairingCode();
        if (code != null) {
          if (mounted) setState(() => _pairingCode = code);
          return;
        }
      } catch (e) {
        if (attempt == 7 && mounted) {
          await showError(context, e, title: 'Could not get a code');
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
    }
  }

  Widget _hero(
    AppColors colors, {
    required IconData icon,
    required String title,
    required String? message,
    Color? iconColor,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 4),
        child: Column(
          children: [
            Icon(icon, size: 46, color: iconColor ?? colors.tint),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: AppText.title.copyWith(color: colors.label)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ],
          ],
        ),
      );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colors.fill, shape: BoxShape.circle),
            child: Text('$number',
                style: AppText.caption.copyWith(
                  color: colors.secondaryLabel,
                  fontWeight: FontWeight.w600,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AppText.subhead.copyWith(color: colors.label)),
          ),
        ],
      ),
    );
  }
}
