import 'package:flutter/material.dart';
import '../../features/media/domain/media.dart';

class VaultLogo extends StatelessWidget {
  const VaultLogo({super.key, this.compact = false, this.size = 36});
  final bool compact;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: compact ? size : size * 4.1,
      height: size,
      child: Row(children: [
        Semantics(
            label: 'Mynube',
            image: true,
            child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                    color: const Color(0xFFB94F38),
                    borderRadius: BorderRadius.circular(size * .3)),
                child: CustomPaint(painter: const _MarkPainter(Colors.white)))),
        if (!compact) ...[
          const SizedBox(width: 11),
          Expanded(
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('mynube',
                      style: TextStyle(
                          fontSize: size * .65,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.4,
                          color: Theme.of(context).colorScheme.onSurface))))
        ],
      ]));
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 36, size.height / 36);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(11, 25.5)
      ..cubicTo(8.1, 25.5, 5.8, 23.2, 5.8, 20.4)
      ..cubicTo(5.8, 17.9, 7.6, 15.8, 10, 15.3)
      ..cubicTo(10.9, 11.6, 13.9, 9.4, 17.5, 9.4)
      ..cubicTo(21, 9.4, 24, 11.8, 24.7, 15.1)
      ..cubicTo(27.8, 15.4, 30.2, 17.7, 30.2, 20.4)
      ..cubicTo(30.2, 23.2, 27.8, 25.5, 24.7, 25.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => color != oldDelegate.color;
}

class VaultEyebrow extends StatelessWidget {
  const VaultEyebrow(this.text, {super.key, this.textAlign = TextAlign.start});
  final String text;
  final TextAlign textAlign;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      textAlign: textAlign,
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 10,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w700));
}

class VaultPill extends StatelessWidget {
  const VaultPill(this.label,
      {super.key, this.icon, this.selected = false, this.onTap});
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
        selected: selected,
        button: onTap != null,
        child: Material(
            color: selected ? colors.onSurface : colors.surface,
            shape: StadiumBorder(
                side: BorderSide(
                    color:
                        selected ? colors.onSurface : colors.outlineVariant)),
            child: InkWell(
                onTap: onTap,
                customBorder: const StadiumBorder(),
                child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 17, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[
                        Icon(icon,
                            size: 16,
                            color: selected
                                ? colors.surface
                                : colors.onSurfaceVariant),
                        const SizedBox(width: 7)
                      ],
                      Text(label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color:
                                  selected ? colors.surface : colors.onSurface))
                    ])))));
  }
}

class VaultEnter extends StatelessWidget {
  const VaultEnter({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Duration(milliseconds: 220 + (index % 6) * 35),
      builder: (_, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, 12 * (1 - value)), child: child)),
      child: child);
}

class VaultImage extends StatelessWidget {
  const VaultImage(
      {super.key,
      required this.url,
      this.fit = BoxFit.cover,
      this.label,
      this.onError});
  final String? url;
  final BoxFit fit;
  final String? label;
  final VoidCallback? onError;
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
            child: Icon(Icons.photo_outlined,
                size: 32,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: .5))));
    if (url == null) return placeholder();
    if (url!.startsWith('asset:')) {
      return Image.asset(url!.substring(6),
          fit: fit,
          semanticLabel: label,
          errorBuilder: (_, __, ___) => placeholder());
    }
    return Image.network(url!,
        fit: fit,
        semanticLabel: label,
        gaplessPlayback: true, errorBuilder: (_, __, ___) {
      onError?.call();
      return placeholder();
    });
  }
}

class MemoryMasonry extends StatelessWidget {
  const MemoryMasonry({super.key, required this.items, required this.builder});
  final List<Media> items;
  final Widget Function(Media media, int index) builder;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 600
            ? 2
            : constraints.maxWidth < 950
                ? 3
                : constraints.maxWidth < 1300
                    ? 4
                    : 5;
        final gap = constraints.maxWidth < 600 ? 10.0 : 18.0;
        final buckets = List.generate(columns, (_) => <int>[]);
        final heights = List.filled(columns, 0.0);
        for (var i = 0; i < items.length; i++) {
          var target = 0;
          for (var n = 1; n < columns; n++) {
            if (heights[n] < heights[target]) target = n;
          }
          buckets[target].add(i);
          final media = items[i];
          final aspect = media.height > 0
              ? (media.width / media.height).clamp(.62, 1.5)
              : .8;
          heights[target] += 1 / aspect + .12;
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var n = 0; n < columns; n++) ...[
            if (n > 0) SizedBox(width: gap),
            Expanded(
                child: Column(children: [
              for (final i in buckets[n])
                Padding(
                    padding: EdgeInsets.only(bottom: gap),
                    child: VaultEnter(
                        key: ValueKey(items[i].id),
                        index: i,
                        child: builder(items[i], i)))
            ]))
          ]
        ]);
      });
}
