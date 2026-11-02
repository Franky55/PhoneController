import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/connection.dart';
import '../state/app_state.dart';

/// Renders one configurable control (button, toggle or slider).
class ControlTile extends StatelessWidget {
  const ControlTile({super.key, required this.item, this.compact = false});

  final ControlItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final color = Color(item.color);
    switch (item.type) {
      case ControlType.button:
        return _MomentaryButton(item: item, color: color, compact: compact);
      case ControlType.toggle:
        final on = state.toggleStates[item.id] ?? false;
        return _Pad(
          color: color,
          filled: on,
          compact: compact,
          onDown: () => state.pressControl(item),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.toggle_on : Icons.toggle_off, size: compact ? 20 : 32),
              Text(item.label, textAlign: TextAlign.center),
            ],
          ),
        );
      case ControlType.slider:
        final v = state.sliderValue(item);
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${item.label}: ${v.round()}'),
                Slider(
                  value: v,
                  min: item.min,
                  max: item.max,
                  divisions: item.divisions > 0 ? item.divisions : null,
                  activeColor: color,
                  // Update the label live, send when the finger lifts (avoids flooding).
                  onChanged: (nv) => state.setSlider(item, nv, sendNow: false),
                  onChangeEnd: (nv) => state.setSlider(item, nv),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _MomentaryButton extends StatefulWidget {
  const _MomentaryButton({required this.item, required this.color, required this.compact});
  final ControlItem item;
  final Color color;
  final bool compact;

  @override
  State<_MomentaryButton> createState() => _MomentaryButtonState();
}

class _MomentaryButtonState extends State<_MomentaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return _Pad(
      color: widget.color,
      filled: _down,
      compact: widget.compact,
      onDown: () {
        setState(() => _down = true);
        state.pressControl(widget.item);
      },
      onUp: () {
        if (!_down) return;
        setState(() => _down = false);
        state.releaseControl(widget.item);
      },
      child: Text(widget.item.label, textAlign: TextAlign.center),
    );
  }
}

/// A press/release aware pad. Uses raw pointer events so it works while a
/// joystick is held with the other thumb.
class _Pad extends StatelessWidget {
  const _Pad({
    required this.color,
    required this.filled,
    required this.child,
    required this.onDown,
    this.onUp,
    this.compact = false,
  });

  final Color color;
  final bool filled;
  final Widget child;
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = filled
        ? (ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black)
        : color;
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp?.call(),
      onPointerCancel: (_) => onUp?.call(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        constraints: BoxConstraints(minWidth: compact ? 64 : 88, minHeight: compact ? 44 : 72),
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.12),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          child: IconTheme.merge(data: IconThemeData(color: fg), child: child),
        ),
      ),
    );
  }
}

/// Connect / disconnect button with status color, for app bars.
class ConnectionButton extends StatelessWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final (icon, color, tip) = switch (state.linkState) {
      LinkState.connected => (Icons.link, Colors.green, 'Disconnect'),
      LinkState.connecting => (Icons.sync, Colors.orange, 'Connecting...'),
      LinkState.disconnected => (Icons.link_off, Colors.red, 'Connect'),
    };
    final typeIcon = state.active.connectionType == ConnectionType.ble ? Icons.bluetooth : Icons.wifi;
    return TextButton.icon(
      onPressed: switch (state.linkState) {
        LinkState.connected => state.disconnect,
        LinkState.disconnected => () async {
            await state.connect();
            if (state.lastError != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.lastError!)));
            }
          },
        LinkState.connecting => null,
      },
      icon: Icon(icon, color: color),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(typeIcon, size: 18),
        const SizedBox(width: 4),
        Text(tip),
      ]),
    );
  }
}
