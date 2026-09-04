library;

/// 角色定位:`position` 字段的两种格式统一解析(对齐 web `utils/characterPosition.ts`)。
///   · 网格 id   'A1'..'E5'   —— V4/V4.5(列 A-E × 行 1-5)
///   · 自由坐标  '0.42,0.67'  —— NAI Diffusion V5 自由定位(x,y 均 0~1)
///
/// V5 官方 "No more tiny grids":可在画布任意连续坐标放角色,且单图最多 32 个 ——
/// 25 个格子根本摆不下。两种格式在发送层由 [resolveCharacterCenter] 统一解析,
/// 空 / 非法 = AUTO(交给发送层按序自动排布)。

final _gridRe = RegExp(r'^[A-E][1-5]$');
final _freeRe = RegExp(r'^\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)\s*$');

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// 5×5 每一格的格心坐标(官方 bundle 里那张 `[.1,.3,.5,.7,.9]`)。列行同表。
const kGridCenters = [0.1, 0.3, 0.5, 0.7, 0.9];

/// 一个轴上的坐标 → 格子下标 0..4。
///
/// 官方是 **floor 分桶**而不是四舍五入:`[0,0.2)→0`、`[0.2,0.4)→1`……这里逐字
/// 照抄,因为 [quantizeCenterToGrid] 发出去的数字要和官方**逐位相同**,换成
/// round 在 0.2 / 0.4 这些边界上会差一格。
int _gridIndex(double v) => (5 * v).floor().clamp(0, 4);

/// 网格 id → 格心归一化坐标;非网格 id 返回 null。
({double x, double y})? _gridCenter(String pos) {
  if (!_gridRe.hasMatch(pos)) return null;
  return (
    x: kGridCenters['ABCDE'.indexOf(pos[0])],
    y: kGridCenters[int.parse(pos[1]) - 1],
  );
}

/// `position` → 归一化中心坐标 {x,y}。网格 id / 自由坐标统一入口;空 / 非法 → null。
({double x, double y})? resolveCharacterCenter(String? pos) {
  if (pos == null || pos.isEmpty) return null;
  final g = _gridCenter(pos);
  if (g != null) return g;
  final m = _freeRe.firstMatch(pos);
  if (m != null) {
    return (
      x: _clamp01(double.parse(m.group(1)!)),
      y: _clamp01(double.parse(m.group(2)!)),
    );
  }
  return null;
}

/// 0~1 坐标 → 自由坐标串(写进 `position`)。
String formatFreeformPosition(double x, double y) =>
    '${_clamp01(x).toStringAsFixed(4)},${_clamp01(y).toStringAsFixed(4)}';

/// `position` 是否为自由坐标串(而非网格 id / AUTO)。
bool isFreeformPosition(String? pos) => pos != null && _freeRe.hasMatch(pos);

/// 把连续坐标吸附到 5×5 格心 —— 官方 `$n` 的移植。
///
/// 官方在**发送前**对所有 `freeformCharacterPosition: false` 的模型(V4 / V4.5
/// 及它们的 inpainting 变体)套这一层,存着的坐标一个字节都不改。所以「V5 摆好
/// → 切 V4.5 → 切回 V5」精确坐标不丢,网格只是同一份坐标的另一个视图。这条分工
/// 我们照搬:发送层([buildNaiPayload])按最终模型决定吸不吸,UI 不改写 position。
({double x, double y}) quantizeCenterToGrid(double x, double y) =>
    (x: kGridCenters[_gridIndex(x)], y: kGridCenters[_gridIndex(y)]);

/// `position` → 它落在的那一格 id(自由坐标串同样算得出来);AUTO/非法 → null。
///
/// 网格 UI 的高亮判断必须走它,不能拿 position 字符串直接比 —— 从 V5 带过来的
/// '0.42,0.67' 跟任何格子 id 都不相等,25 个格子会全显示未选中,但请求里发的是
/// C4。连 '0.7000,0.3000' 这种正正压在格心上的也一样比不中。
String? gridCellForPosition(String? pos) {
  final c = resolveCharacterCenter(pos);
  if (c == null) return null;
  return '${'ABCDE'[_gridIndex(c.x)]}${_gridIndex(c.y) + 1}';
}

/// 位置徽章文案:AUTO / 网格 id / 自由坐标百分比(如 '42,67%')。
///
/// [grid] 用在当前模型只能落格子的场合(V4/V4.5):显示它实际会被吸附到的那一
/// 格。否则徽章写着 '42,67%'、请求里发的却是 C4 的格心,两边对不上。
String positionChipLabel(String? pos, {bool grid = false}) {
  if (pos == null || pos.isEmpty) return 'AUTO';
  if (_gridRe.hasMatch(pos)) return pos;
  final m = _freeRe.firstMatch(pos);
  if (m == null) return 'AUTO';
  if (grid) return gridCellForPosition(pos) ?? 'AUTO';
  final x = (_clamp01(double.parse(m.group(1)!)) * 100).round();
  final y = (_clamp01(double.parse(m.group(2)!)) * 100).round();
  return '$x,$y%';
}

/// 两组宽高的横竖比是否一致(判断能否拿主页现有图当角色定位画布)。
bool aspectRatiosMatch(int w1, int h1, int w2, int h2) =>
    w1 > 0 && h1 > 0 && w2 > 0 && h2 > 0 && (w1 / h1 - w2 / h2).abs() < 0.01;

/// 官方给**新角色**挑初始位置的候选序(bundle 里那张 `lc` 表)。
///
/// 先中间那一横排、由内向外(正中 → 两侧);再把其余四行按「到画面中心的距离」
/// 铺开,同距的按「离中线的高度差 → x → y」定序。加角色时取候选序里第一个
/// **还没被占**的格子。
///
/// 为什么要照抄这张表:官方在**创建角色那一刻**就把坐标写进 state,之后不再变。
/// 我们早先是发送时按角色下标现算,后果是删掉前面一个角色,后面那个会跟着挪窝
/// —— 用户什么都没动,出图就变了。
final List<({double x, double y})> kSpawnCenters = List.unmodifiable([
  for (final x in const [0.5, 0.3, 0.7, 0.1, 0.9]) (x: x, y: 0.5),
  ...[
    for (final y in const [0.1, 0.3, 0.7, 0.9])
      for (final x in kGridCenters) (x: x, y: y),
  ]..sort((a, b) {
      double d(({double x, double y}) p) {
        final dx = p.x - .5, dy = p.y - .5;
        return dx * dx + dy * dy; // 比距离不用开方，同序
      }

      final c = d(a).compareTo(d(b));
      if (c != 0) return c;
      final h = (a.y - .5).abs().compareTo((b.y - .5).abs());
      if (h != 0) return h;
      final x = a.x.compareTo(b.x);
      return x != 0 ? x : a.y.compareTo(b.y);
    }),
]);

/// 这个候选格心算不算已被占用。
///
/// [freeform] = V5(自由坐标):按欧氏距离 < 0.1;其余模型量化后同格即算占用
/// —— 与官方 `$n()` 的判据一致。
bool _spawnTaken(
  ({double x, double y}) c,
  List<({double x, double y})> taken,
  bool freeform,
) {
  for (final t in taken) {
    if (freeform) {
      final dx = t.x - c.x, dy = t.y - c.y;
      if (dx * dx + dy * dy < 0.01) return true; // 0.1²
    } else {
      final q = quantizeCenterToGrid(t.x, t.y);
      if ((q.x - c.x).abs() < 1e-9 && (q.y - c.y).abs() < 1e-9) return true;
    }
  }
  return false;
}

/// 给新角色挑初始位置:候选序里第一个没被占的格心;25 格全满则回落正中(同官方)。
({double x, double y}) nextSpawnCenter(
  List<({double x, double y})> taken, {
  required bool freeform,
}) {
  for (final c in kSpawnCenters) {
    if (!_spawnTaken(c, taken, freeform)) return c;
  }
  return (x: 0.5, y: 0.5);
}

/// [nextSpawnCenter] 的 `position` 版:传现有角色的 position 串,回新角色该用的那个。
String nextSpawnPosition(
  Iterable<String?> existing, {
  required bool freeform,
}) {
  final taken = <({double x, double y})>[];
  for (final p in existing) {
    final c = resolveCharacterCenter(p);
    if (c != null) taken.add(c);
  }
  final c = nextSpawnCenter(taken, freeform: freeform);
  return positionOfCenter(c.x, c.y)!;
}

/// 元数据 center(0~1)→ `position`:恰好落 5×5 格心 → 网格 id(V4/V4.5 干净往返);
/// 否则保留精确自由坐标串(V5 自由坐标不吸附丢位置);无坐标 → null=AUTO。
String? positionOfCenter(double? x, double? y) {
  if (x == null || y == null) return null;
  final grid = '${'ABCDE'[_gridIndex(x)]}${_gridIndex(y) + 1}';
  final gc = _gridCenter(grid)!;
  if ((gc.x - x).abs() < 1e-3 && (gc.y - y).abs() < 1e-3) return grid;
  return formatFreeformPosition(x, y);
}
