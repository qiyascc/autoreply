import 'package:flutter/cupertino.dart';

import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

/// Builds one rule: the condition that selects it, and the messages it sends.
class RuleEditorPage extends StatefulWidget {
  const RuleEditorPage({super.key, this.rule});

  final Rule? rule;

  @override
  State<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<RuleEditorPage> {
  late Rule _rule;
  late final TextEditingController _nameController;
  final List<TextEditingController> _messageControllers = [];
  final Map<int, MessageShape> _shapes = {};
  bool _saving = false;

  bool get _isNew => widget.rule?.id == null;

  @override
  void initState() {
    super.initState();
    _rule = widget.rule ??
        Rule(name: 'New rule', attemptMin: 1, attemptMax: 1, messages: const ['']);
    _nameController = TextEditingController(text: _rule.name);

    final messages = _rule.messages.isEmpty ? [''] : _rule.messages;
    for (final message in messages) {
      _addController(message);
    }
  }

  void _addController(String text) {
    final controller = TextEditingController(text: text);
    final index = _messageControllers.length;
    controller.addListener(() => _describe(index, controller.text));
    _messageControllers.add(controller);
    _describe(index, text);
  }

  Future<void> _describe(int index, String text) async {
    if (text.isEmpty) {
      if (mounted) setState(() => _shapes.remove(index));
      return;
    }
    try {
      final shape = await Native.describeMessage(text);
      if (mounted) setState(() => _shapes[index] = shape);
    } catch (_) {
      // The counter is a nicety; losing it must never block editing.
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _messageControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isNew ? 'New rule' : 'Edit rule'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator(radius: 9)
              : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      child: SafeArea(
        child: ListView(
          children: [
            _nameSection(colors),
            _conditionSection(colors),
            _timeSection(colors),
            _callerSection(colors),
            _channelSection(colors),
            _messagesSection(colors),
            if (!_isNew) _deleteSection(colors),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _nameSection(AppColors colors) => InsetSection(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: CupertinoTextField.borderless(
              controller: _nameController,
              placeholder: 'Rule name',
              padding: const EdgeInsets.symmetric(vertical: 12),
              style: AppText.body.copyWith(color: colors.label),
            ),
          ),
          InsetTile(
            title: 'Enabled',
            trailing: CupertinoSwitch(
              value: _rule.enabled,
              onChanged: (v) => setState(() => _rule = _rule.copyWith(enabled: v)),
            ),
          ),
        ],
      );

  // ---- which call ----------------------------------------------------------------

  Widget _conditionSection(AppColors colors) {
    final mode = _conditionMode;
    return InsetSection(
      header: 'Applies to',
      footer: switch (mode) {
        _ConditionMode.any => 'Every missed call, regardless of how many times they tried.',
        _ConditionMode.exactly =>
          'Only the ${Rule(name: '', attemptMin: _rule.attemptMin).attemptLabel.toLowerCase()} '
              'from the same person.',
        _ConditionMode.onwards =>
          'The ${_ordinal(_rule.attemptMin ?? 1)} call and every one after it.',
        _ConditionMode.range =>
          'Calls ${_rule.attemptMin ?? 1} through ${_rule.attemptMax ?? 1}.',
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: CupertinoSlidingSegmentedControl<_ConditionMode>(
            groupValue: mode,
            onValueChanged: _setConditionMode,
            children: const {
              _ConditionMode.any: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Any', style: TextStyle(fontSize: 13)),
              ),
              _ConditionMode.exactly: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Nth call', style: TextStyle(fontSize: 13)),
              ),
              _ConditionMode.onwards: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Nth+', style: TextStyle(fontSize: 13)),
              ),
              _ConditionMode.range: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Range', style: TextStyle(fontSize: 13)),
              ),
            },
          ),
        ),
        if (mode != _ConditionMode.any)
          InsetTile(
            title: mode == _ConditionMode.range ? 'From call' : 'Call number',
            value: '#${_rule.attemptMin ?? 1}',
            showChevron: true,
            onTap: () => _pickNumber(
              title: mode == _ConditionMode.range ? 'From call' : 'Call number',
              current: _rule.attemptMin ?? 1,
              onPicked: (value) => setState(() {
                _rule = _rule.copyWith(
                  attemptMin: value,
                  attemptMax: mode == _ConditionMode.exactly
                      ? value
                      : mode == _ConditionMode.range
                          ? (_rule.attemptMax ?? value).clamp(value, 99)
                          : null,
                );
              }),
            ),
          ),
        if (mode == _ConditionMode.range)
          InsetTile(
            title: 'To call',
            value: '#${_rule.attemptMax ?? _rule.attemptMin ?? 1}',
            showChevron: true,
            onTap: () => _pickNumber(
              title: 'To call',
              current: _rule.attemptMax ?? _rule.attemptMin ?? 1,
              min: _rule.attemptMin ?? 1,
              onPicked: (value) =>
                  setState(() => _rule = _rule.copyWith(attemptMax: value)),
            ),
          ),
      ],
    );
  }

  _ConditionMode get _conditionMode {
    final min = _rule.attemptMin;
    final max = _rule.attemptMax;
    if (min == null && max == null) return _ConditionMode.any;
    if (min != null && max == null) return _ConditionMode.onwards;
    if (min != null && min == max) return _ConditionMode.exactly;
    return _ConditionMode.range;
  }

  void _setConditionMode(_ConditionMode? mode) {
    if (mode == null) return;
    final current = _rule.attemptMin ?? 1;
    setState(() {
      _rule = switch (mode) {
        _ConditionMode.any => _rule.copyWith(attemptMin: null, attemptMax: null),
        _ConditionMode.exactly => _rule.copyWith(attemptMin: current, attemptMax: current),
        _ConditionMode.onwards => _rule.copyWith(attemptMin: current, attemptMax: null),
        _ConditionMode.range =>
          _rule.copyWith(attemptMin: current, attemptMax: current + 1),
      };
    });
  }

  // ---- time window ---------------------------------------------------------------

  Widget _timeSection(AppColors colors) {
    final active = _rule.timeStart != null && _rule.timeEnd != null;
    return InsetSection(
      header: 'Time of day',
      footer: active
          ? 'Only applies between ${When.minuteOfDay(_rule.timeStart!)} and '
              '${When.minuteOfDay(_rule.timeEnd!)}.'
          : 'Applies at any hour.',
      children: [
        InsetTile(
          title: 'Limit to certain hours',
          trailing: CupertinoSwitch(
            value: active,
            onChanged: (v) => setState(() {
              _rule = v
                  ? _rule.copyWith(timeStart: 540, timeEnd: 1080)
                  : _rule.copyWith(timeStart: null, timeEnd: null);
            }),
          ),
        ),
        if (active) ...[
          InsetTile(
            title: 'From',
            value: When.minuteOfDay(_rule.timeStart!),
            showChevron: true,
            onTap: () => _pickTime(
              current: _rule.timeStart!,
              onPicked: (v) => setState(() => _rule = _rule.copyWith(timeStart: v)),
            ),
          ),
          InsetTile(
            title: 'To',
            value: When.minuteOfDay(_rule.timeEnd!),
            showChevron: true,
            onTap: () => _pickTime(
              current: _rule.timeEnd!,
              onPicked: (v) => setState(() => _rule = _rule.copyWith(timeEnd: v)),
            ),
          ),
        ],
      ],
    );
  }

  // ---- caller ---------------------------------------------------------------------

  Widget _callerSection(AppColors colors) => InsetSection(
        header: 'Caller',
        footer: switch (_rule.contactFilter) {
          'known' => 'Only people saved in your contacts.',
          'unknown' => 'Only numbers that are not in your contacts.',
          _ => 'Everyone who calls.',
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _rule.contactFilter,
              onValueChanged: (v) =>
                  setState(() => _rule = _rule.copyWith(contactFilter: v ?? 'any')),
              children: const {
                'any': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Anyone', style: TextStyle(fontSize: 13)),
                ),
                'known': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('In contacts', style: TextStyle(fontSize: 13)),
                ),
                'unknown': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Unknown', style: TextStyle(fontSize: 13)),
                ),
              },
            ),
          ),
        ],
      );

  // ---- channel ---------------------------------------------------------------------

  Widget _channelSection(AppColors colors) => InsetSection(
        header: 'Send via',
        footer: switch (_rule.channel) {
          'whatsapp' => 'WhatsApp only. If it cannot be delivered you get a notification.',
          'both' => 'Sends the same message twice — once as a text, once on WhatsApp.',
          _ => 'A normal text message. Works with the phone locked and no internet.',
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _rule.channel,
              onValueChanged: (v) =>
                  setState(() => _rule = _rule.copyWith(channel: v ?? 'sms')),
              children: const {
                'sms': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Message', style: TextStyle(fontSize: 13)),
                ),
                'whatsapp': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('WhatsApp', style: TextStyle(fontSize: 13)),
                ),
                'both': Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Both', style: TextStyle(fontSize: 13)),
                ),
              },
            ),
          ),
        ],
      );

  // ---- messages ---------------------------------------------------------------------

  Widget _messagesSection(AppColors colors) => InsetSection(
        header: _messageControllers.length > 1 ? 'Messages (sent in order)' : 'Message',
        footer: 'Sent about three seconds apart when there is more than one.',
        children: [
          for (var i = 0; i < _messageControllers.length; i++) _messageRow(colors, i),
          InsetTile(
            title: 'Add another message',
            titleColor: colors.tint,
            leading: GlyphBadge(icon: CupertinoIcons.add, color: colors.tint, size: 24),
            onTap: () => setState(() => _addController('')),
          ),
        ],
      );

  Widget _messageRow(AppColors colors, int index) {
    final shape = _shapes[index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CupertinoTextField.borderless(
                  controller: _messageControllers[index],
                  placeholder: 'What should they receive?',
                  maxLines: null,
                  minLines: 2,
                  padding: EdgeInsets.zero,
                  style: AppText.body.copyWith(color: colors.label),
                ),
              ),
              if (_messageControllers.length > 1)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  onPressed: () => setState(() {
                    _messageControllers.removeAt(index).dispose();
                    _shapes.clear();
                    for (var i = 0; i < _messageControllers.length; i++) {
                      _describe(i, _messageControllers[i].text);
                    }
                  }),
                  child: Icon(CupertinoIcons.minus_circle_fill,
                      size: 19, color: colors.danger),
                ),
            ],
          ),
          if (shape != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${shape.chars}/${shape.perPart} · ${shape.parts} '
                '${shape.parts == 1 ? 'part' : 'parts'}'
                '${shape.unicode ? ' · unicode' : ''}',
                style: AppText.caption.copyWith(
                  color: shape.parts > 1 ? colors.warning : colors.secondaryLabel,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deleteSection(AppColors colors) => InsetSection(
        children: [
          InsetTile(
            title: 'Delete rule',
            titleColor: colors.danger,
            onTap: _confirmDelete,
          ),
        ],
      );

  // ---- pickers ---------------------------------------------------------------------

  Future<void> _pickNumber({
    required String title,
    required int current,
    int min = 1,
    required void Function(int) onPicked,
  }) async {
    final values = List.generate(20, (i) => min + i);
    var selected = current.clamp(min, min + 19);

    await _showPicker(
      title: title,
      initialItem: values.indexOf(selected),
      itemCount: values.length,
      itemBuilder: (i) => Text('Call #${values[i]}'),
      onSelected: (i) => selected = values[i],
    );
    onPicked(selected);
  }

  Future<void> _pickTime({
    required int current,
    required void Function(int) onPicked,
  }) async {
    // Quarter-hour resolution: enough for "evenings" without a 1440-row wheel.
    final values = List.generate(96, (i) => i * 15);
    var selected = values.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );

    await _showPicker(
      title: 'Time',
      initialItem: values.indexOf(selected),
      itemCount: values.length,
      itemBuilder: (i) => Text(When.minuteOfDay(values[i])),
      onSelected: (i) => selected = values[i],
    );
    onPicked(selected);
  }

  Future<void> _showPicker({
    required String title,
    required int initialItem,
    required int itemCount,
    required Widget Function(int) itemBuilder,
    required void Function(int) onSelected,
  }) async {
    final colors = AppColors.of(context);
    onSelected(initialItem);

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
                  scrollController:
                      FixedExtentScrollController(initialItem: initialItem.clamp(0, itemCount - 1)),
                  itemExtent: 36,
                  onSelectedItemChanged: onSelected,
                  children: List.generate(itemCount, itemBuilder),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- persistence -------------------------------------------------------------------

  Future<void> _save() async {
    final messages = _messageControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (messages.isEmpty) {
      await showError(
        context,
        'A rule needs at least one message to send.',
        title: 'Nothing to send',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await Native.saveRule(
        _rule.copyWith(
          name: _nameController.text.trim().isEmpty
              ? _rule.attemptLabel
              : _nameController.text.trim(),
          messages: messages,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showError(context, e, title: 'Could not save');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete this rule?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Native.deleteRule(_rule.id!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }
}

enum _ConditionMode { any, exactly, onwards, range }
