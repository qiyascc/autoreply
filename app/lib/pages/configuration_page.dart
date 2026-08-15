import 'package:flutter/cupertino.dart';

import '../native.dart';
import '../theme.dart';
import '../widgets.dart';
import 'rule_editor_page.dart';

/// The rule list. Rules are evaluated top to bottom and the first match wins, so the
/// order on this screen is the order the engine uses — hence the explicit reordering.
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  List<Rule>? _rules;
  Object? _error;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await Native.rules();
      if (!mounted) return;
      setState(() {
        _rules = rules;
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
    final rules = _rules;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Rules'),
            trailing: rules == null || rules.length < 2
                ? null
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _editing = !_editing),
                    child: Text(_editing ? 'Done' : 'Reorder'),
                  ),
          ),
          CupertinoSliverRefreshControl(onRefresh: _load),
          SliverToBoxAdapter(child: _body(context, colors, rules)),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppColors colors, List<Rule>? rules) {
    if (_error != null) {
      return EmptyState(
        icon: CupertinoIcons.exclamationmark_triangle,
        title: 'Could not load rules',
        message: '$_error',
      );
    }
    if (rules == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rules.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.slider_horizontal_3,
            title: 'No rules yet',
            message: 'Add one to decide what gets sent, and when.',
          )
        else
          InsetSection(
            footer: 'Rules are checked from the top down and the first match wins. '
                'Put your most specific conditions above the general ones.',
            children: [
              for (var i = 0; i < rules.length; i++) _ruleTile(context, colors, rules, i),
            ],
          ),
        InsetSection(
          children: [
            InsetTile(
              title: 'Add rule',
              titleColor: colors.tint,
              leading: GlyphBadge(icon: CupertinoIcons.add, color: colors.tint),
              onTap: () => _openEditor(context, null),
            ),
          ],
        ),
      ],
    );
  }

  Widget _ruleTile(BuildContext context, AppColors colors, List<Rule> rules, int index) {
    final rule = rules[index];
    final channelIcon = switch (rule.channel) {
      'whatsapp' => CupertinoIcons.chat_bubble_fill,
      'both' => CupertinoIcons.square_stack_3d_up_fill,
      _ => CupertinoIcons.text_bubble_fill,
    };

    final preview = rule.messages.isEmpty
        ? 'No message set'
        : '“${rule.messages.first}”${rule.messages.length > 1 ? ' +${rule.messages.length - 1} more' : ''}';

    if (_editing) {
      return InsetTile(
        title: rule.attemptLabel,
        subtitle: rule.name,
        leading: GlyphBadge(
          icon: channelIcon,
          color: rule.enabled ? colors.tint : colors.secondaryLabel,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: index == 0 ? null : () => _move(rules, index, index - 1),
              child: Icon(CupertinoIcons.chevron_up,
                  size: 18,
                  color: index == 0 ? colors.tertiaryLabel : colors.tint),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              onPressed: index == rules.length - 1
                  ? null
                  : () => _move(rules, index, index + 1),
              child: Icon(CupertinoIcons.chevron_down,
                  size: 18,
                  color: index == rules.length - 1
                      ? colors.tertiaryLabel
                      : colors.tint),
            ),
          ],
        ),
      );
    }

    return InsetTile(
      title: rule.attemptLabel,
      subtitle: preview,
      leading: GlyphBadge(
        icon: channelIcon,
        color: rule.enabled ? colors.tint : colors.secondaryLabel,
      ),
      value: rule.enabled ? null : 'Off',
      showChevron: true,
      onTap: () => _openEditor(context, rule),
    );
  }

  Future<void> _move(List<Rule> rules, int from, int to) async {
    final reordered = [...rules];
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    setState(() => _rules = reordered);

    try {
      final saved = await Native.reorderRules(
        reordered.map((r) => r.id!).toList(),
      );
      if (mounted) setState(() => _rules = saved);
    } catch (e) {
      if (mounted) await showError(context, e);
      await _load();
    }
  }

  Future<void> _openEditor(BuildContext context, Rule? rule) async {
    final changed = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(builder: (_) => RuleEditorPage(rule: rule)),
    );
    if (changed == true) await _load();
  }
}
