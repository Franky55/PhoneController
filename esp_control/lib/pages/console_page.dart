import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _showStream = false;
  bool _autoScroll = true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(AppState state) {
    final text = _input.text;
    if (text.isEmpty) return;
    state.send(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final entries = state.log.where((e) => _showStream || !e.stream).toList();
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Joystick traffic'),
                selected: _showStream,
                onSelected: (v) => setState(() => _showStream = v),
              ),
              FilterChip(
                label: const Text('Auto-scroll'),
                selected: _autoScroll,
                onSelected: (v) => setState(() => _autoScroll = v),
              ),
              TextButton.icon(
                onPressed: state.clearLog,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: entries.length,
            itemBuilder: (context, i) => _LogLine(entries[i]),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: state.isConnected,
                  decoration: InputDecoration(
                    hintText: state.isConnected ? 'Raw message to send' : 'Connect first',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(state),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: state.isConnected ? () => _send(state) : null,
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine(this.e);
  final LogEntry e;

  @override
  Widget build(BuildContext context) {
    final (prefix, color) = switch (e.kind) {
      LogKind.tx => ('>>', Colors.blue),
      LogKind.rx => ('<<', Colors.green),
      LogKind.info => ('--', Colors.grey),
      LogKind.error => ('!!', Colors.red),
    };
    final t = e.time;
    final ts = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: SelectableText.rich(
        TextSpan(style: const TextStyle(fontFamily: 'monospace', fontSize: 13), children: [
          TextSpan(text: '$ts ', style: const TextStyle(color: Colors.grey)),
          TextSpan(text: '$prefix ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          TextSpan(text: e.text, style: TextStyle(color: e.kind == LogKind.error ? Colors.red : null)),
        ]),
      ),
    );
  }
}
