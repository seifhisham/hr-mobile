import 'package:hodour/src/imports/imports.dart';
import '../../data/models/sales_activity.dart';
import 'sales_widgets.dart';

/// Pick what was completed: three big, clearly labelled choices instead of
/// a dropdown, so the form below can adapt to it at a glance.
class SalesKindSelector extends StatelessWidget {
  const SalesKindSelector(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
          builder: (context, constraints) {
        final stacked = constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        final gap = AppSpacing.sm;
        final tiles = [
          for (final kind in salesKinds)
            _KindTile(
                kind: kind,
                selected: kind == value,
                stacked: stacked,
                onTap: enabled ? () => onChanged(kind) : null),
        ];
        if (stacked) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              tiles[i],
            ],
          ]);
        }
        return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: tiles[i]),
          ],
        ]));
      });
}

class _KindTile extends StatelessWidget {
  const _KindTile(
      {required this.kind,
      required this.selected,
      required this.stacked,
      required this.onTap});
  final String kind;
  final bool selected, stacked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurface;
    final icon = ExcludeSemantics(
        child: Icon(salesKindIcon(kind),
            size: 28,
            color: selected ? colors.primary : colors.onSurfaceVariant));
    final label = Text(salesKindLabel(kind),
        textAlign: stacked ? TextAlign.start : TextAlign.center,
        style: context.textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500));
    return Semantics(
        button: true,
        selected: selected,
        enabled: onTap != null,
        child: Material(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
                borderRadius: AppBorders.lg,
                side: BorderSide(
                    color: selected ? colors.primary : colors.outlineVariant,
                    width: selected ? 2 : 1)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: onTap,
                child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.md),
                    child: stacked
                        ? Row(children: [
                            icon,
                            SizedBox(width: AppSpacing.md),
                            Expanded(child: label),
                            if (selected)
                              ExcludeSemantics(
                                  child: Icon(Icons.check_circle_rounded,
                                      color: colors.primary)),
                          ])
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                icon,
                                SizedBox(height: AppSpacing.sm),
                                label,
                              ])))));
  }
}

/// A titled group of fields with even spacing between them.
class SalesFormSection extends StatelessWidget {
  const SalesFormSection(
      {super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
            header: true,
            child: Text(title,
                style: context.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700))),
        for (final child in children) ...[
          SizedBox(height: AppSpacing.md),
          child,
        ],
      ]));
}

/// A small muted line under a field.
class SalesFieldHint extends StatelessWidget {
  const SalesFieldHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: context.textTheme.bodySmall
          ?.copyWith(color: context.colors.onSurfaceVariant));
}
