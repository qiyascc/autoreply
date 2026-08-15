import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// An iOS inset-grouped section: rounded card, optional header and footer, hairline
/// separators that stop short of the leading edge the way the system does.
class InsetSection extends StatelessWidget {
  const InsetSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.margin = const EdgeInsets.fromLTRB(16, 22, 16, 0),
  });

  final List<Widget> children;
  final String? header;
  final String? footer;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (children.isEmpty && header == null && footer == null) {
      return const SizedBox.shrink();
    }

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Container(height: 0.5, color: colors.separator),
        ));
      }
    }

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
              child: Text(
                header!.toUpperCase(),
                style: AppText.sectionHeader.copyWith(color: colors.secondaryLabel),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
              child: Text(
                footer!,
                style: AppText.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single row inside an [InsetSection].
class InsetTile extends StatefulWidget {
  const InsetTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.showChevron = false,
    this.titleColor,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? titleColor;
  final bool dense;

  @override
  State<InsetTile> createState() => _InsetTileState();
}

class _InsetTileState extends State<InsetTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final interactive = widget.onTap != null;

    final content = Container(
      color: _pressed ? colors.cardPressed : colors.card,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: widget.dense ? 9 : 12),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: AppText.body.copyWith(color: widget.titleColor ?? colors.label),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    style: AppText.footnote.copyWith(color: colors.secondaryLabel),
                  ),
                ],
              ],
            ),
          ),
          if (widget.value != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                widget.value!,
                style: AppText.body.copyWith(color: colors.secondaryLabel),
              ),
            ),
          if (widget.trailing != null)
            Padding(padding: const EdgeInsets.only(left: 8), child: widget.trailing!),
          if (widget.showChevron)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(CupertinoIcons.chevron_right,
                  size: 15, color: colors.tertiaryLabel),
            ),
        ],
      ),
    );

    if (!interactive) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: content,
    );
  }
}

/// Small circular status light used on Home and in the pairing flow.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.pulsing = false, this.size = 10});

  final Color color;
  final bool pulsing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulsing) return dot;
    return _Pulse(child: dot);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.3).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: widget.child,
      );
}

/// One of the three counters on Home.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });

  final int value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Text(
            '$value',
            style: AppText.largeTitle.copyWith(
              color: color ?? colors.label,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.footnote.copyWith(color: colors.secondaryLabel)),
        ],
      ),
    );
  }
}

/// A rounded glyph badge, the way iOS Settings marks each row.
class GlyphBadge extends StatelessWidget {
  const GlyphBadge({super.key, required this.icon, required this.color, this.size = 29});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: size * 0.6, color: const Color(0xFFFFFFFF)),
      );
}

/// Full-width filled button, matching the system's prominent action style.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 14),
        borderRadius: BorderRadius.circular(12),
        color: destructive ? colors.danger : colors.tint,
        onPressed: busy ? null : onPressed,
        child: busy
            ? const CupertinoActivityIndicator(color: Color(0xFFFFFFFF))
            : Text(
                label,
                style: AppText.body.copyWith(
                  color: const Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Empty-state placeholder: a glyph, a line, and a reason.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 64, 40, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: colors.tertiaryLabel),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.headline.copyWith(color: colors.secondaryLabel),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppText.footnote.copyWith(color: colors.tertiaryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows a failure in the house style. Native errors arrive as PlatformException, whose
/// `message` is already a sentence written for the user by the Kotlin layer.
Future<void> showError(BuildContext context, Object error, {String title = 'Something went wrong'}) {
  final message = switch (error) {
    PlatformException e => e.message ?? e.code,
    _ => error.toString(),
  };
  return showCupertinoDialog(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
