import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
import 'ble_scan_page.dart';
import 'control_editor_page.dart';

/// Shows a single text field dialog. Returns null if cancelled.
Future<String?> editTextDialog(BuildContext context, String title, String initial,
    {bool number = false, String? helper, bool multiline = false}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: number ? TextInputType.number : (multiline ? TextInputType.multiline : TextInputType.text),
        maxLines: multiline ? 12 : 1,
        style: multiline ? const TextStyle(fontFamily: 'monospace', fontSize: 12) : null,
        decoration: InputDecoration(helperText: helper, helperMaxLines: 3),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
      ],
    ),
  );
}

/// A list tile showing a value, editable through a dialog.
class TextSettingTile extends StatelessWidget {
  const TextSettingTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.number = false,
    this.helper,
    this.icon,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;
  final bool number;
  final String? helper;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon != null ? Icon(icon) : null,
      title: Text(title),
      subtitle: Text(value.isEmpty ? '(empty)' : value, style: const TextStyle(fontFamily: 'monospace')),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: () async {
        final v = await editTextDialog(context, title, value, number: number, helper: helper);
        if (v != null) onChanged(v);
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.active;
    void set(void Function(Profile p) f) => state.updateActive(f);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ------------------------------------------------------------ profile
        const _Header('Profile'),
        ListTile(
          leading: const Icon(Icons.folder_special),
          title: DropdownButton<String>(
            value: p.id,
            isExpanded: true,
            items: [for (final pr in state.profiles) DropdownMenuItem(value: pr.id, child: Text(pr.name))],
            onChanged: (id) => id != null ? state.selectProfile(id) : null,
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => _profileAction(context, state, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'new', child: Text('New (RC car template)')),
              const PopupMenuItem(value: 'empty', child: Text('New (empty)')),
              const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
              const PopupMenuItem(value: 'export', child: Text('Export (copy JSON)')),
              const PopupMenuItem(value: 'import', child: Text('Import (paste JSON)')),
              if (state.profiles.length > 1) const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),

        // --------------------------------------------------------- connection
        const _Header('Connection'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<ConnectionType>(
            segments: const [
              ButtonSegment(value: ConnectionType.ble, icon: Icon(Icons.bluetooth), label: Text('Bluetooth LE')),
              ButtonSegment(value: ConnectionType.wifi, icon: Icon(Icons.wifi), label: Text('WiFi')),
            ],
            selected: {p.connectionType},
            onSelectionChanged: state.isConnected
                ? null
                : (s) => set((p) => p.connectionType = s.first),
          ),
        ),
        if (state.isConnected)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Disconnect to change connection settings.', style: TextStyle(color: Colors.grey)),
          ),
        if (p.connectionType == ConnectionType.ble) ...[
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: Text(p.ble.deviceId.isEmpty ? 'No device selected' : (p.ble.deviceName.isEmpty ? '(no name)' : p.ble.deviceName)),
            subtitle: Text(p.ble.deviceId.isEmpty ? 'Tap to scan' : p.ble.deviceId),
            trailing: const Icon(Icons.chevron_right),
            onTap: state.isConnected
                ? null
                : () async {
                    final r = await Navigator.push<BleScanResult>(
                      context,
                      MaterialPageRoute(builder: (_) => BleScanPage(serviceUuid: p.ble.serviceUuid)),
                    );
                    if (r != null) {
                      set((p) {
                        p.ble.deviceId = r.id;
                        p.ble.deviceName = r.name;
                      });
                    }
                  },
          ),
          ExpansionTile(
            leading: const Icon(Icons.tune),
            title: const Text('Advanced BLE (UUIDs)'),
            children: [
              TextSettingTile(
                  title: 'Service UUID', value: p.ble.serviceUuid, onChanged: (v) => set((p) => p.ble.serviceUuid = v.trim())),
              TextSettingTile(
                  title: 'RX characteristic (phone → ESP32, write)',
                  value: p.ble.rxUuid,
                  onChanged: (v) => set((p) => p.ble.rxUuid = v.trim())),
              TextSettingTile(
                  title: 'TX characteristic (ESP32 → phone, notify)',
                  value: p.ble.txUuid,
                  onChanged: (v) => set((p) => p.ble.txUuid = v.trim())),
              TextButton(
                onPressed: () => set((p) {
                  final d = BleSettings();
                  p.ble
                    ..serviceUuid = d.serviceUuid
                    ..rxUuid = d.rxUuid
                    ..txUuid = d.txUuid;
                }),
                child: const Text('Reset to Nordic UART defaults'),
              ),
            ],
          ),
        ] else ...[
          TextSettingTile(
            icon: Icons.router,
            title: 'ESP32 IP / host',
            value: p.wifi.host,
            helper: 'ESP32 in hotspot (AP) mode is usually 192.168.4.1',
            onChanged: (v) => set((p) => p.wifi.host = v.trim()),
          ),
          TextSettingTile(
            icon: Icons.numbers,
            title: 'WebSocket port',
            value: '${p.wifi.port}',
            number: true,
            onChanged: (v) => set((p) => p.wifi.port = int.tryParse(v) ?? p.wifi.port),
          ),
          TextSettingTile(
            icon: Icons.alt_route,
            title: 'Path',
            value: p.wifi.path,
            onChanged: (v) => set((p) => p.wifi.path = v.startsWith('/') ? v : '/$v'),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline),
            title: Text('URL: ${p.wifi.uri}'),
            subtitle: const Text('Join the ESP32 WiFi network first. If it fails, turn mobile data off.'),
          ),
        ],

        // ----------------------------------------------------------- messages
        const _Header('Messages'),
        ListTile(
          leading: const Icon(Icons.keyboard_return),
          title: const Text('Line ending (added to every message)'),
          trailing: DropdownButton<LineEnding>(
            value: p.lineEnding,
            items: const [
              DropdownMenuItem(value: LineEnding.none, child: Text('None')),
              DropdownMenuItem(value: LineEnding.lf, child: Text(r'\n')),
              DropdownMenuItem(value: LineEnding.crlf, child: Text(r'\r\n')),
            ],
            onChanged: (v) => set((p) => p.lineEnding = v!),
          ),
        ),
        TextSettingTile(
          icon: Icons.stop_circle,
          title: 'STOP message',
          value: p.stopMessage,
          helper: 'Sent by the STOP button and before disconnecting.',
          onChanged: (v) => set((p) => p.stopMessage = v),
        ),

        // ---------------------------------------------------------- joysticks
        const _Header('Joysticks'),
        _StickSettings(title: 'Left joystick', cfg: p.leftStick, set: set),
        _StickSettings(title: 'Right joystick', cfg: p.rightStick, set: set),
        TextSettingTile(
          icon: Icons.straighten,
          title: 'Max value (range is -max..+max)',
          value: '${p.maxValue}',
          number: true,
          onChanged: (v) => set((p) => p.maxValue = (int.tryParse(v) ?? p.maxValue).clamp(1, 100000)),
        ),
        TextSettingTile(
          icon: Icons.speed,
          title: 'Send rate (Hz)',
          value: '${p.sendRateHz}',
          number: true,
          helper: '1 to 100. 20 is a good default for BLE.',
          onChanged: (v) => set((p) => p.sendRateHz = (int.tryParse(v) ?? p.sendRateHz).clamp(1, 100)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.repeat),
          title: const Text('Repeat values while held'),
          subtitle: const Text('Keeps sending while a stick is off-center, so the ESP32 can '
              'stop the motors if messages stop arriving (failsafe).'),
          value: p.repeatWhileHeld,
          onChanged: (v) => set((p) => p.repeatWhileHeld = v),
        ),

        // ----------------------------------------------------------- controls
        _Header('Buttons & sliders (${p.controls.length})'),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) => set((p) => p.controls.insert(b, p.controls.removeAt(a))),
          children: [
            for (var i = 0; i < p.controls.length; i++)
              ListTile(
                key: ValueKey(p.controls[i].id),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_indicator, color: Color(p.controls[i].color)),
                ),
                title: Text(p.controls[i].label),
                subtitle: Text(
                  '${p.controls[i].type.name}${p.controls[i].showOnController ? ' · on controller' : ''}\n'
                  '${p.controls[i].pressMsg}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => set((p) {
                    if (v == 'dup') p.controls.insert(i + 1, p.controls[i].copy());
                    if (v == 'del') p.controls.removeAt(i);
                  }),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                    PopupMenuItem(value: 'del', child: Text('Delete')),
                  ],
                ),
                onTap: () => _editControl(context, state, p.controls[i]),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _editControl(context, state, null),
            icon: const Icon(Icons.add),
            label: const Text('Add button / toggle / slider'),
          ),
        ),
      ],
    );
  }

  Future<void> _editControl(BuildContext context, AppState state, ControlItem? existing) async {
    final result = await Navigator.push<ControlItem>(
      context,
      MaterialPageRoute(builder: (_) => ControlEditorPage(initial: existing)),
    );
    if (result == null) return;
    state.updateActive((p) {
      final i = p.controls.indexWhere((c) => c.id == result.id);
      if (i >= 0) {
        p.controls[i] = result;
      } else {
        p.controls.add(result);
      }
    });
  }

  Future<void> _profileAction(BuildContext context, AppState state, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'rename':
        final name = await editTextDialog(context, 'Profile name', state.active.name);
        if (name != null && name.trim().isNotEmpty) state.updateActive((p) => p.name = name.trim());
      case 'new':
        state.addProfile(Profile.rcCar()..name = 'RC Car ${state.profiles.length + 1}');
      case 'empty':
        state.addProfile(Profile(name: 'Profile ${state.profiles.length + 1}'));
      case 'dup':
        state.duplicateActive();
      case 'export':
        await Clipboard.setData(ClipboardData(text: state.exportActive()));
        messenger.showSnackBar(const SnackBar(content: Text('Profile JSON copied to clipboard')));
      case 'import':
        final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        if (!context.mounted) return;
        final text = await editTextDialog(context, 'Paste profile JSON', clip, multiline: true);
        if (text == null) return;
        try {
          state.importProfile(text);
          messenger.showSnackBar(const SnackBar(content: Text('Profile imported')));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text('Invalid profile JSON: $e')));
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Delete "${state.active.name}"?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) state.deleteActive();
    }
  }
}

class _StickSettings extends StatelessWidget {
  const _StickSettings({required this.title, required this.cfg, required this.set});

  final String title;
  final JoystickConfig cfg;
  final void Function(void Function(Profile p)) set;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.gamepad),
      title: Text(title),
      subtitle: Text(cfg.template, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      children: [
        TextSettingTile(title: 'Label', value: cfg.label, onChanged: (v) => set((_) => cfg.label = v)),
        TextSettingTile(
          title: 'Message template',
          value: cfg.template,
          helper: 'Use {x} and {y} for the values. Example: {"j":"L","x":{x},"y":{y}}',
          onChanged: (v) => set((_) => cfg.template = v),
        ),
        ListTile(
          title: const Text('Axes'),
          trailing: DropdownButton<JoystickAxes>(
            value: cfg.axes,
            items: const [
              DropdownMenuItem(value: JoystickAxes.both, child: Text('X and Y')),
              DropdownMenuItem(value: JoystickAxes.xOnly, child: Text('X only (left/right)')),
              DropdownMenuItem(value: JoystickAxes.yOnly, child: Text('Y only (up/down)')),
            ],
            onChanged: (v) => set((_) => cfg.axes = v!),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
