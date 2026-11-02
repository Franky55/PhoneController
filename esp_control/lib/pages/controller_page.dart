import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
import '../widgets/control_widgets.dart';
import '../widgets/joystick.dart';

class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key});

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _StickState {
  int x = 0, y = 0;
  int? sentX, sentY;
  bool get centered => x == 0 && y == 0;
}

class _ControllerPageState extends State<ControllerPage> {
  final _left = _StickState();
  final _right = _StickState();
  Timer? _timer;
  int _rateHz = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTimer(int hz) {
    if (hz == _rateHz && _timer != null) return;
    _rateHz = hz;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: (1000 / hz.clamp(1, 100)).round()), (_) => _tick());
  }

  void _tick() {
    final state = context.read<AppState>();
    if (!state.isConnected) return;
    final p = state.active;
    _sendStick(state, p, p.leftStick, _left);
    _sendStick(state, p, p.rightStick, _right);
  }

  void _sendStick(AppState state, Profile p, JoystickConfig cfg, _StickState s) {
    final changed = s.x != s.sentX || s.y != s.sentY;
    final repeat = p.repeatWhileHeld && !s.centered;
    if (!changed && !repeat) return;
    s.sentX = s.x;
    s.sentY = s.y;
    state.send(cfg.template.replaceAll('{x}', '${s.x}').replaceAll('{y}', '${s.y}'), stream: true);
  }

  void _onStick(_StickState s, int max, double x, double y) {
    s.x = (x * max).round();
    s.y = (y * max).round();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.active;
    _ensureTimer(p.sendRateHz);
    final quick = p.controls.where((c) => c.showOnController).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // Leave room for the label under each stick (~28 px).
                final stickSize = min(box.maxHeight - 28, box.maxWidth * 0.36).clamp(0.0, 400.0);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Joystick(
                      size: stickSize,
                      axes: p.leftStick.axes,
                      label: p.leftStick.label,
                      onChanged: (x, y) => _onStick(_left, p.maxValue, x, y),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(110, 52),
                            ),
                            onPressed: state.isConnected ? state.sendStop : null,
                            icon: const Icon(Icons.stop_circle),
                            label: const Text('STOP'),
                          ),
                          if (!state.isConnected)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Not connected', style: TextStyle(color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                    Joystick(
                      size: stickSize,
                      axes: p.rightStick.axes,
                      label: p.rightStick.label,
                      onChanged: (x, y) => _onStick(_right, p.maxValue, x, y),
                    ),
                  ],
                );
              },
            ),
          ),
          if (quick.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final c in quick)
                  SizedBox(
                    width: c.type == ControlType.slider ? 260 : null,
                    child: ControlTile(item: c, compact: true),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
