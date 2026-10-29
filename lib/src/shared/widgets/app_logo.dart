import 'package:hodour/src/imports/imports.dart';

/// The app identity; adjacent company/portal text supplies its accessible name.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: AppBorders.input,
        child: Image.asset(AppAssets.logo,
            width: size,
            height: size,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true),
      );
}
