import 'package:flutter/material.dart';

/// Small reusable stat card.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? accent;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: accent ?? cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label.toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: .4, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Shows the estimated range for the three riding modes (Eco / Normal / Sport),
/// like the Elfa app. [modes] maps mode name → km.
class RangeModesCard extends StatelessWidget {
  final Map<String, double> modes;
  const RangeModesCard({super.key, required this.modes});

  static const _icons = {
    'Eco': Icons.eco,
    'Normal': Icons.pedal_bike,
    'Sport': Icons.bolt,
  };
  static const _colors = {
    'Eco': Colors.green,
    'Normal': Colors.blue,
    'Sport': Colors.deepOrange,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.route, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('ESTIMATED RANGE',
                  style: TextStyle(fontSize: 11, letterSpacing: .4, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('est.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final name in const ['Eco', 'Normal', 'Sport'])
                  if (modes[name] != null) _mode(context, name, modes[name]!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mode(BuildContext context, String name, double km) {
    final cs = Theme.of(context).colorScheme;
    final color = _colors[name] ?? cs.primary;
    return Column(children: [
      Icon(_icons[name], color: color, size: 22),
      const SizedBox(height: 6),
      Text('${km.round()}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text('km', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      const SizedBox(height: 2),
      Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]);
  }
}

String timeAgo(DateTime? t) {
  if (t == null) return '—';
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${(s / 60).round()} min ago';
  if (s < 86400) return '${(s / 3600).round()} h ago';
  return '${(s / 86400).round()} d ago';
}
