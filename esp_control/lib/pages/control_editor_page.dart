import 'package:flutter/material.dart';

import '../models/profile.dart';

const _palette = [
  0xFF2196F3, 0xFF4CAF50, 0xFFF44336, 0xFFFF9800, 0xFFFFEB3B, //
  0xFF9C27B0, 0xFF00BCD4, 0xFF795548, 0xFF607D8B, 0xFFE91E63,
];

/// Creates or edits a [ControlItem]. Pops with the edited copy, or null.
class ControlEditorPage extends StatefulWidget {
  const ControlEditorPage({super.key, this.initial});

  final ControlItem? initial;

  @override
  State<ControlEditorPage> createState() => _ControlEditorPageState();
}

class _ControlEditorPageState extends State<ControlEditorPage> {
  late final ControlItem _item;
  late final TextEditingController _label, _press, _release, _min, _max, _div;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    // Work on a copy that keeps the same id, so Cancel leaves the original untouched.
    _item = init != null ? ControlItem.fromJson(init.toJson()) : ControlItem(label: 'Button');
    _label = TextEditingController(text: _item.label);
    _press = TextEditingController(text: _item.pressMsg);
    _release = TextEditingController(text: _item.releaseMsg);
    _min = TextEditingController(text: _fmt(_item.min));
    _max = TextEditingController(text: _fmt(_item.max));
    _div = TextEditingController(text: '${_item.divisions}');
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  @override
  void dispose() {
    for (final c in [_label, _press, _release, _min, _max, _div]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    _item
      ..label = _label.text.trim().isEmpty ? 'Button' : _label.text.trim()
      ..pressMsg = _press.text
      ..releaseMsg = _release.text
      ..min = double.tryParse(_min.text) ?? 0
      ..max = double.tryParse(_max.text) ?? 255
      ..divisions = int.tryParse(_div.text) ?? 0;
    if (_item.max <= _item.min) _item.max = _item.min + 1;
    Navigator.pop(context, _item);
  }

  @override
  Widget build(BuildContext context) {
    final (pressLabel, pressHelp, releaseLabel, releaseHelp) = switch (_item.type) {
      ControlType.button => ('Message on press', null, 'Message on release', 'Leave empty to send nothing'),
      ControlType.toggle => ('Message when turned ON', null, 'Message when turned OFF', null),
      ControlType.slider => ('Message template', 'Use {v} for the value, e.g. {"cmd":"speed","v":{v}}', '', null),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New control' : 'Edit control'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ControlType>(
            segments: const [
              ButtonSegment(value: ControlType.button, icon: Icon(Icons.touch_app), label: Text('Button')),
              ButtonSegment(value: ControlType.toggle, icon: Icon(Icons.toggle_on), label: Text('Toggle')),
              ButtonSegment(value: ControlType.slider, icon: Icon(Icons.linear_scale), label: Text('Slider')),
            ],
            selected: {_item.type},
            onSelectionChanged: (s) => setState(() => _item.type = s.first),
          ),
          const SizedBox(height: 16),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Label')),
          const SizedBox(height: 12),
          TextField(
            controller: _press,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(labelText: pressLabel, helperText: pressHelp),
          ),
          if (_item.type != ControlType.slider) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _release,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(labelText: releaseLabel, helperText: releaseHelp),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: const InputDecoration(labelText: 'Min'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: const InputDecoration(labelText: 'Max'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _div,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Steps (0 = free)'),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show on Controller page'),
            value: _item.showOnController,
            onChanged: (v) => setState(() => _item.showOnController = v),
          ),
          const SizedBox(height: 8),
          const Text('Color'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () => setState(() => _item.color = c),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(c),
                    child: _item.color == c ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
