import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/net/remote_image.dart';
import '../../../core/ui/lift_menu.dart' show globalRectOf;
import '../../../core/theme/app_skin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/fade_in_once.dart';
import '../artist_models.dart';
import '../tag_models.dart';
import 'preview_tone.dart';

/// 打码时预览只解出这么多像素宽,再按最近邻放大成方块。
const _kMosaicCells = 12;

/// 卡片预览图:无图 = 名称定色相的斜纹占位;http 走磁盘缓存;本机路径直读。
/// 加载完淡入,让预览逐张柔和显现而非硬蹦(只淡第一次,见 [FadeInOnce])。
/// 灵感页网格、选角色面板、角色卡头像共用。
class TagCardPreview extends StatelessWidget {
  const TagCardPreview({
    super.key,
    required this.url,
    required this.name,
    this.decodeWidth,
    this.placeholder,
    this.mosaic = false,
    this.overlay,
    this.hold = false,
    this.onShown,
  });

  final String? url;
  final String name;

  /// 解码宽(逻辑像素);null = 远端按布局宽、本机图按原尺寸。
  /// 图像缓存存的是解码后的位图:角色卡头像只画 46dp,整张 832×1216 解出来
  /// 要占 4MB,所以本机图也按这个宽解。
  final double? decodeWidth;

  /// 无图 / 读图失败时的占位;null = 名称定色相的斜纹。
  final Widget? placeholder;

  /// 打成马赛克(忽略 [decodeWidth])。
  final bool mosaic;

  /// 叠在图上、和图一起淡入的一层;无图 / 读图失败时画在占位上。
  final Widget? overlay;

  /// 图出帧了也先不露面,放开后连同 [overlay] 一起淡入。
  final bool hold;

  /// 图头一回出帧(见 [FadeInOnce.onShown])。
  final VoidCallback? onShown;

  Widget get _empty => _over(placeholder ?? _HueStripes(name: name));

  Widget _over(Widget base) => switch (overlay) {
    null => base,
    final o => Stack(fit: StackFit.expand, children: [base, o]),
  };

  Widget _stripes(BuildContext context, Object error, StackTrace? stack) =>
      _empty;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final quality = mosaic ? FilterQuality.none : FilterQuality.medium;
    return switch (url) {
      null => _empty,
      final u => FadeInOnce(
        source: u,
        hold: hold,
        onShown: onShown,
        builder: (context, fade) {
          Widget frame(BuildContext c, Widget child, int? f, bool sync) =>
              fade(c, _over(child), f, sync);
          return u.startsWith('http')
              ? RemoteImage(
                  u,
                  fit: BoxFit.cover,
                  decodeWidth: mosaic ? _kMosaicCells / dpr : decodeWidth,
                  filterQuality: quality,
                  gaplessPlayback: true,
                  frameBuilder: frame,
                  errorBuilder: _stripes,
                )
              : Image.file(
                  File(u),
                  fit: BoxFit.cover,
                  cacheWidth: mosaic
                      ? _kMosaicCells
                      : switch (decodeWidth) {
                          null => null,
                          final w => (w * dpr).round(),
                        },
                  filterQuality: quality,
                  gaplessPlayback: true,
                  frameBuilder: frame,
                  errorBuilder: _stripes,
                );
        },
      ),
    };
  }
}

/// 网格卡:满铺预览图(无图=名称定色相的斜纹占位)+ 底部名字胶囊;
/// 左上选择圈。点卡选择;长按给了 [onLift] 就交出卡片在屏幕上的矩形
/// (抬起菜单从这里长出来),否则走 [onLongPress]。
class TagCard extends StatelessWidget {
  const TagCard({
    super.key,
    required this.entry,
    this.previewUrl,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onLift,
    this.decodeWidth,
    this.showCheck = true,
    this.mosaic = false,
  });

  final TagEntry entry;

  /// 实际渲染的预览(可能是按 publicId 从公共库补的 http,覆盖 entry 自身)。
  final String? previewUrl;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Rect>? onLift;

  /// 左上的选择圈,进入多选后才画。点一下就选定的场合(给单张角色卡换人)不画。
  final bool showCheck;

  /// 远端预览的解码宽(逻辑像素)。
  final double? decodeWidth;

  /// 预览打码,正中一枚闭眼标;点卡做什么由调用方定。
  final bool mosaic;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // 捏到三四列以后卡片很小:选择圈和名牌收小一档,名牌只留名字。
    // 按实测尺寸判,换档过渡途中越过门槛就换。
    builder: (context, c) => _card(
      context,
      compact: c.maxWidth < 100 || c.maxHeight < 100,
      centered: c.maxHeight > c.maxWidth * 1.1,
    ),
  );

  Widget _card(
    BuildContext context, {
    required bool compact,
    required bool centered,
  }) {
    final scheme = context.scheme;
    final inset = compact ? 4.0 : 5.0;
    return AnimatedContainer(
      duration: Motion.fast,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? scheme.primary
              : context.skin.edge ?? scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: scheme.surfaceContainer,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLift == null
              ? onLongPress
              : () {
                  if (globalRectOf(context) case final r?) onLift!(r);
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TonedPreview(
                url: previewUrl,
                name: entry.name,
                decodeWidth: decodeWidth,
                mosaic: mosaic,
                left: !centered,
                overlay: (dark) => Positioned(
                  left: inset + 1,
                  right: inset + 1,
                  bottom: inset + 1,
                  child: _namePlate(dark, compact: compact, centered: centered),
                ),
              ),
              if (mosaic)
                Center(
                  child: Container(
                    width: compact ? 30 : 40,
                    height: compact ? 30 : 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .42),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.visibility_off_outlined,
                      size: compact ? 17 : 21,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (showCheck)
                Positioned(
                  top: inset + 1,
                  left: inset + 1,
                  child: _check(scheme, compact: compact),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左上选择圈(进入多选后才画):选中为主色实心勾,未选为半透明空圈;
  /// 两种都带白边,亮图暗图上都看得出。
  Widget _check(ColorScheme scheme, {required bool compact}) {
    final size = compact ? 18.0 : 22.0;
    return AnimatedContainer(
      duration: Motion.fast,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.black.withValues(alpha: .22),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: selected
          ? Icon(Icons.check, size: size - 8, color: scheme.onPrimary)
          : null,
    );
  }

  /// 底部名字胶囊(竖卡居中,横卡 / 方卡靠左);非紧凑时名字后跟适用模型
  /// (按分档归并,没标注的不画)和推荐参数图标。
  Widget _namePlate(
    bool dark, {
    required bool compact,
    required bool centered,
  }) {
    final modelGroups = compact
        ? const <ArtistModelGroup>[]
        : artistModelGroups(entry.models);
    return _NamePill(
      name: entry.name,
      models: [
        for (final g in modelGroups.take(2)) g.label,
        if (modelGroups.length > 2) '+${modelGroups.length - 2}',
      ].join(' '),
      recipe: entry.recipe != null && !compact,
      selected: selected,
      dark: dark,
      compact: compact,
      centered: centered,
    );
  }
}

/// 预览图 + 名字胶囊。胶囊深浅跟着底下那块图的亮度走(见 [PreviewTone]);
/// 亮度量出来之前图和胶囊都先不露面,量完一起淡入,不会先浅后深闪一下。
///
/// 图出帧后才去量:这时字节已在本地,不会另起下载;快速滑动时图本身推迟加载,
/// 划过去的卡也就不会去量。
class _TonedPreview extends StatefulWidget {
  const _TonedPreview({
    required this.url,
    required this.name,
    required this.decodeWidth,
    required this.mosaic,
    required this.left,
    required this.overlay,
  });

  final String? url;
  final String name;
  final double? decodeWidth;
  final bool mosaic;

  /// 胶囊靠左(否则居中),量亮度的取样区跟着换。
  final bool left;

  /// 胶囊;dark = 底下是亮图,该用深色胶囊。
  final Widget Function(bool dark) overlay;

  @override
  State<_TonedPreview> createState() => _TonedPreviewState();
}

class _TonedPreviewState extends State<_TonedPreview> {
  /// 亮度高过这一档就换深色胶囊。
  static const _lightAbove = .62;

  /// 图出帧以后,最多再为量亮度压住它这么久。
  static const _graceAfterFrame = Duration(milliseconds: 400);

  double? _tone;
  bool _ready = false;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void didUpdateWidget(_TonedPreview old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.left != widget.left) _measure();
  }

  void _measure() {
    _wait?.cancel();
    _wait = null;
    final url = widget.url;
    _tone = url == null ? null : PreviewTone.peek(url, left: widget.left);
    _ready = url == null || _tone != null;
  }

  /// 图出帧:开始量亮度。量得慢或量不出来就不等了 —— 图照常露面,
  /// 胶囊先按浅色,量出来再换。
  void _onShown() {
    if (!mounted) return;
    final url = widget.url;
    if (url == null || _ready || _wait != null) return;
    _wait = Timer(_graceAfterFrame, () => _release(url));
    final left = widget.left;
    PreviewTone.of(url, left: left).then((v) {
      if (!mounted || widget.url != url || widget.left != left) return;
      setState(() {
        _tone = v ?? _tone;
        _ready = true;
      });
    }, onError: (_) => _release(url));
  }

  void _release(String? url) {
    if (mounted && widget.url == url && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TagCardPreview(
    url: widget.url,
    name: widget.name,
    decodeWidth: widget.decodeWidth,
    mosaic: widget.mosaic,
    hold: !_ready,
    onShown: _onShown,
    overlay: widget.overlay((_tone ?? 0) > _lightAbove),
  );
}

/// 名字胶囊,只包住名字。亮图上用深色胶囊白字,暗图 / 中间调上用浅色胶囊
/// 深字,纯白、纯黑的预览都托得出来。选中时换成主色底。名字过长先省略名字。
class _NamePill extends StatelessWidget {
  const _NamePill({
    required this.name,
    required this.models,
    required this.recipe,
    required this.selected,
    required this.dark,
    required this.compact,
    required this.centered,
  });

  final String name;
  final String models;
  final bool recipe;
  final bool selected;
  final bool dark;
  final bool compact;

  /// 竖卡居中,横卡 / 方卡靠左。
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final Color fill;
    final Color fg;
    final Color meta;
    final Color edge;
    if (selected) {
      fill = scheme.primary;
      fg = scheme.onPrimary;
      meta = scheme.onPrimary.withValues(alpha: .8);
      edge = Colors.white.withValues(alpha: .3);
    } else if (dark) {
      fill = Colors.black.withValues(alpha: .58);
      fg = Colors.white;
      meta = Colors.white.withValues(alpha: .78);
      edge = Colors.white.withValues(alpha: .12);
    } else {
      fill = Colors.white.withValues(alpha: .9);
      fg = const Color(0xFF14191F);
      meta = const Color(0xFF4A515B);
      edge = Colors.white.withValues(alpha: .4);
    }
    return Align(
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            if (models.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                models,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: meta,
                ),
              ),
            ],
            if (recipe) ...[
              const SizedBox(width: 4),
              Icon(Icons.tune, size: 12, color: meta),
            ],
          ],
        ),
      ),
    );
  }
}

/// 无预览图的占位:名称哈希定色相的深色渐变 + 斜纹 + 名称水印
/// (对齐 web HorizontalCard 的 hashHue 占位,同名恒同色)。
class _HueStripes extends StatelessWidget {
  const _HueStripes({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    return CustomPaint(
      painter: _HueStripePainter(hue),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Colors.white.withValues(alpha: .2),
            ),
          ),
        ),
      ),
    );
  }
}

class _HueStripePainter extends CustomPainter {
  const _HueStripePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final a = HSLColor.fromAHSL(1, hue, .38, .20).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 24) % 360, .42, .13).toColor();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ).createShader(Offset.zero & size),
    );
    final stripe = Paint()..color = Colors.black.withValues(alpha: .16);
    const w = 14.0;
    for (double x = -size.height; x < size.width; x += w * 2.4) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + w, 0)
        ..lineTo(x + w, size.height)
        ..close();
      canvas.drawPath(path, stripe);
    }
  }

  @override
  bool shouldRepaint(covariant _HueStripePainter old) => old.hue != hue;
}
