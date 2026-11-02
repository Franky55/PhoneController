import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
import '../widgets/control_widgets.dart';

class ButtonsPage extends StatelessWidget {
  const ButtonsPage({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final controls = context.watch<AppState>().active.controls;
    if (controls.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No buttons yet.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.add),
            label: const Text('Add buttons in Settings'),
          ),
        ]),
      );
    }
    final pads = controls.where((c) => c.type != ControlType.slider).toList();
    final sliders = controls.where((c) => c.type == ControlType.slider).toList();
    return LayoutBuilder(builder: (context, box) {
      // The page can be laid out with ~0 width while hidden or mid-rotation.
      if (box.maxWidth < 64) return const SizedBox.shrink();
      return _buildList(pads, sliders);
    });
  }

  Widget _buildList(List<ControlItem> pads, List<ControlItem> sliders) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.extent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final c in pads) ControlTile(item: c)],
        ),
        const SizedBox(height: 12),
        for (final c in sliders) ControlTile(item: c),
      ],
    );
  }
}
