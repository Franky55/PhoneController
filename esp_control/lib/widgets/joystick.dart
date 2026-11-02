import 'dart:math';

import 'package:flutter/material.dart';

import '../models/profile.dart';

/// A virtual thumbstick. Reports x/y in -1..1 (right and up are positive).
/// Uses raw pointer events so two sticks work at the same time.
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    required this.onChanged,
    this.axes = JoystickAxes.both,
    this.size = 180,
    this.label = '',
  });

  final void Function(double x, double y) onChanged;
  final JoystickAxes axes;
  final double size;
  final String label;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero; // -1..1 in screen coordinates (y down)
  int? _pointer;

  void _update(Offset local) {
    final r = widget.size / 2;
    var d = (local - Offset(r, r)) / r;
    if (widget.axes == JoystickAxes.xOnly) d = Offset(d.dx, 0);
    if (widget.axes == JoystickAxes.yOnly) d = Offset(0, d.dy);
    if (d.distance > 1) d = d / d.distance;
    setState(() => _knob = d);
    widget.onChanged(d.dx, -d.dy);
  }

  void _release() {
    _pointer = null;
    setState(() => _knob = Offset.zero);
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerDown: (e) {
            if (_pointer != null) return;
            _pointer = e.pointer;
            _update(e.localPosition);
          },
          onPointerMove: (e) {
            if (e.pointer == _pointer) _update(e.localPosition);
          },
          onPointerUp: (e) {
            if (e.pointer == _pointer) _release();
          },
          onPointerCancel: (e) {
            if (e.pointer == _pointer) _release();
          },
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _JoystickPainter(_knob, widget.axes, scheme),
          ),
        ),
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
          ),
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter(this.knob, this.axes, this.scheme);

  final Offset knob;
  final JoystickAxes axes;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = scheme.surfaceContainerHighest);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.outline);

    // Guide line for locked axes.
    final guide = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = r * 0.5
      ..strokeCap = StrokeCap.round;
    if (axes == JoystickAxes.xOnly) canvas.drawLine(c - Offset(r * 0.6, 0), c + Offset(r * 0.6, 0), guide);
    if (axes == JoystickAxes.yOnly) canvas.drawLine(c - Offset(0, r * 0.6), c + Offset(0, r * 0.6), guide);

    final knobR = max(24.0, r * 0.35);
    final travel = r - knobR;
    canvas.drawCircle(c + knob * travel, knobR, Paint()..color = scheme.primary);
  }

  @override
  bool shouldRepaint(_JoystickPainter old) => old.knob != knob || old.axes != axes || old.scheme != scheme;
}
