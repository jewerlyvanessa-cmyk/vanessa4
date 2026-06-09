import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Scroll behavior: simulator/desktop mouse + touch (iOS/Android).
class VanessaScrollBehavior extends MaterialScrollBehavior {
  const VanessaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// Breakpoint & helper layout untuk web, APK, dan layar sempit.
abstract final class ResponsiveLayout {
  ResponsiveLayout._();

  /// Layar ponsel / sempit (portrait).
  static const double compactMax = 600;

  /// Tablet kecil / landscape phone.
  static const double mediumMax = 900;

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) =>
      widthOf(context) < compactMax;

  static bool isMediumOrBelow(BuildContext context) =>
      widthOf(context) < mediumMax;

  static EdgeInsets pagePadding(BuildContext context) {
    final w = widthOf(context);
    final base = w < 360
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
        : w < compactMax
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
    // Ruang ekstra di bawah form scroll.
    return base.copyWith(
      bottom: base.bottom + scrollEndGap(context),
    );
  }

  /// Jarak tambahan di akhir daftar scroll (ruang visual, bukan inset sistem).
  static double scrollEndGap(BuildContext context) {
    if (kIsWeb) return 8;
    return isCompact(context) ? 16 : 8;
  }

  /// Inset bawah sistem (navigation bar / gesture bar).
  static double systemBottomInset(BuildContext context) {
    if (kIsWeb) return 0;
    return MediaQuery.viewPaddingOf(context).bottom;
  }

  /// Padding scroll + navigation bar (tanpa mengganggu AppBar).
  static EdgeInsets safeScrollPadding(BuildContext context) {
    final pad = pagePadding(context);
    if (kIsWeb) return pad;
    return pad.copyWith(
      bottom: pad.bottom + systemBottomInset(context),
    );
  }

  /// Padding bawah [ListView]/[Column] isi halaman.
  static EdgeInsets contentPadding(BuildContext context) =>
      safeScrollPadding(context);

  /// Padding bawah daftar — dipakai di dalam [scaffoldBody] / [RoleMenuBody].
  static EdgeInsets listBottomPadding(BuildContext context) {
    return EdgeInsets.only(bottom: scrollEndGap(context));
  }

  /// Padding [SingleChildScrollView] / [ListView] utama di [Scaffold.body].
  /// Setara `EdgeInsets.all(16)` tapi bottom menyertakan tinggi navigation/gesture bar.
  /// Gunakan sebagai pengganti `const EdgeInsets.all(16)` di halaman dengan tombol di bawah.
  static EdgeInsets bodyPadding(BuildContext context, {
    double horizontal = 16,
    double top = 16,
    double bottom = 16,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottom + systemBottomInset(context),
    );
  }

  /// Padding header (nama cabang / role) di dashboard menu.
  static const EdgeInsets roleMenuHeaderPadding = EdgeInsets.only(
    left: 24,
    top: 24,
    right: 24,
    bottom: 8,
  );

  static const EdgeInsets roleMenuHorizontalPadding =
      EdgeInsets.symmetric(horizontal: 16);

  /// Padding bawah [ListView] menu role (antrian, transfer pending, dll.).
  static EdgeInsets roleMenuListPadding(BuildContext context) =>
      listBottomPadding(context);

  /// Padding bawah [SingleChildScrollView] isi menu.
  static EdgeInsets roleMenuScrollPadding(BuildContext context) =>
      listBottomPadding(context);

  /// Physics scroll konsisten (iOS bounce + selalu bisa drag meski konten pendek).
  static const ScrollPhysics scrollPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );

  /// Body [Scaffold] — lindungi konten dari navigation/gesture bar bawah.
  /// [top: false] — AppBar sudah ditangani oleh Scaffold sendiri.
  /// [maintainBottomViewPadding: false] — descendant melihat viewPadding.bottom = 0
  /// sehingga [safeScrollPadding] di dalam tidak double-count inset nav bar.
  static Widget scaffoldBody(Widget child) {
    if (kIsWeb) return child;
    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      minimum: EdgeInsets.zero,
      child: child,
    );
  }

  /// Alias untuk [scaffoldBody].
  static Widget avoidSystemBars(Widget child) => scaffoldBody(child);

  /// Safe area web mobile (notch / gesture bar browser).
  static Widget appChrome(Widget child) {
    if (!kIsWeb) return child;
    return SafeArea(
      minimum: EdgeInsets.zero,
      child: child,
    );
  }

  /// @deprecated — tidak dipakai; Gunakan [scaffoldBody] untuk Scaffold body.
  static Widget webMobileChrome(Widget child) => appChrome(child);

  /// Form panjang — [SingleChildScrollView] + [Column] (andalan iOS/simulator).
  static Widget scrollableForm({
    required BuildContext context,
    required GlobalKey<FormState> formKey,
    required List<Widget> children,
  }) {
    return SingleChildScrollView(
      primary: false,
      physics: scrollPhysics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: safeScrollPadding(context),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  /// Alias [scrollableForm] — API lama tetap dipakai halaman Ambil.
  static Widget scrollableFormColumn({
    required BuildContext context,
    required GlobalKey<FormState> formKey,
    required List<Widget> children,
  }) =>
      scrollableForm(
        context: context,
        formKey: formKey,
        children: children,
      );

  /// Halaman isi [Column] / widget tunggal — bukan form ListView.
  static Widget scrollablePage({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return SingleChildScrollView(
      primary: false,
      physics: scrollPhysics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: padding ?? safeScrollPadding(context),
      child: child,
    );
  }

  /// Scroll aman + konten di tengah vertikal jika layar lebih tinggi dari isi (mis. login).
  static Widget scrollableCenteredPage({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    final resolvedPadding = padding ?? safeScrollPadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = resolvedPadding.resolve(Directionality.of(context));
        final minHeight = (constraints.maxHeight - pad.vertical)
            .clamp(0.0, double.infinity);
        return SingleChildScrollView(
          primary: false,
          physics: scrollPhysics,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: resolvedPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// [ListView] menu role / daftar dengan pull-to-refresh.
  static Widget roleMenuListView({
    required BuildContext context,
    required List<Widget> children,
  }) {
    return ListView(
      primary: false,
      physics: scrollPhysics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: roleMenuListPadding(context),
      children: children,
    );
  }

  /// [SingleChildScrollView] di dalam [Expanded] pada dashboard menu.
  static Widget roleMenuScroll({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return SingleChildScrollView(
      primary: false,
      physics: scrollPhysics,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: padding ?? roleMenuScrollPadding(context),
      child: child,
    );
  }

  static double labelColumnWidth(BuildContext context) {
    final w = widthOf(context);
    if (w < 360) return 0;
    if (w < compactMax) return 100;
    return 120;
  }

  /// Mencegah teks sistem terlalu besar/kecil sehingga layout pecah (terutama web di HP).
  static MediaQueryData clampMediaQuery(MediaQueryData mq) {
    final onWeb = kIsWeb;
    return mq.copyWith(
      textScaler: mq.textScaler.clamp(
        minScaleFactor: onWeb ? 1.0 : 0.9,
        maxScaleFactor: onWeb ? 1.25 : 1.2,
      ),
    );
  }
}
