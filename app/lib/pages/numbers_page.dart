import 'package:flutter/cupertino.dart';

import '../main.dart';
import '../native.dart';
import '../theme.dart';
import '../widgets.dart';

/// The block/allow list. One list, two meanings, chosen by the mode above it — which is
/// simpler to reason about than maintaining two separate lists that can contradict.
class NumbersPage extends StatefulWidget {
  const NumbersPage({super.key});

  @override
  State<NumbersPage> createState() => _NumbersPageState();
}

class _NumbersPageState extends State<NumbersPage> {
  List<ListedNumber>? _numbers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final numbers = await Native.numberList();
      if (mounted) setState(() => _numbers = numbers);
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final status = app.status;
    final colors = AppColors.of(context);
    final numbers = _numbers;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: const CupertinoNavigationBar(middle: Text('Number list')),
      child: SafeArea(
        child: status == null
            ? const Center(child: CupertinoActivityIndicator())
            : ListView(
                children: [
                  InsetSection(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    header: 'Mode',
                    footer: switch (status.listMode) {
                      'blocklist' => 'Everyone gets replies except the numbers below.',
                      'allowlist' => 'Only the numbers below get replies. Everyone else is ignored.',
                      _ => 'The list is ignored. Everyone gets replies.',
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: CupertinoSlidingSegmentedControl<String>(
                          groupValue: status.listMode,
                          onValueChanged: (v) => v == null ? null : app.set('list_mode', v),
                          children: const {
                            'off': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Off', style: TextStyle(fontSize: 13)),
                            ),
                            'blocklist': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Block these', style: TextStyle(fontSize: 13)),
                            ),
                            'allowlist': Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text('Only these', style: TextStyle(fontSize: 13)),
                            ),
                          },
                        ),
                      ),
                    ],
                  ),
                  if (numbers == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(child: CupertinoActivityIndicator()),
                    )
                  else ...[
                    if (numbers.isEmpty)
                      const EmptyState(
                        icon: CupertinoIcons.person_2,
                        title: 'The list is empty',
                        message: 'Add a number to start filtering.',
                      )
                    else
                      InsetSection(
                        header: 'Numbers',
                        children: numbers
                            .map((n) => InsetTile(
                                  title: n.pretty,
                                  subtitle: n.note,
                                  leading: GlyphBadge(
                                    icon: CupertinoIcons.person_fill,
                                    color: colors.secondaryLabel,
                                  ),
                                  trailing: CupertinoButton(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    minimumSize: Size.zero,
                                    onPressed: () => _remove(n.id),
                                    child: Icon(CupertinoIcons.minus_circle_fill,
                                        size: 19, color: colors.danger),
                                  ),
                                ))
                            .toList(),
                      ),
                    InsetSection(
                      children: [
                        InsetTile(
                          title: 'Add a number',
                          titleColor: colors.tint,
                          leading: GlyphBadge(icon: CupertinoIcons.add, color: colors.tint),
                          onTap: _addNumber,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
      ),
    );
  }

  Future<void> _remove(int id) async {
    try {
      final numbers = await Native.removeNumber(id);
      if (mounted) setState(() => _numbers = numbers);
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  Future<void> _addNumber() async {
    final numberController = TextEditingController();
    final noteController = TextEditingController();

    final added = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Add a number'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: numberController,
                placeholder: 'Phone number',
                keyboardType: TextInputType.phone,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: noteController,
                placeholder: 'Note (optional)',
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (added == true) {
      try {
        final numbers = await Native.addNumber(
          numberController.text,
          note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
        );
        if (mounted) setState(() => _numbers = numbers);
      } catch (e) {
        if (mounted) await showError(context, e);
      }
    }

    numberController.dispose();
    noteController.dispose();
  }
}
