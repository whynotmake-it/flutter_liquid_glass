part of 'menu_fusion.dart';

/// The union of two rounded boxes on a grid and its Gaussian blur, both
/// evaluated on demand: the trace and field grid of [menuSilhouetteParts]
/// padded by the kernel's reach, node (i, j) of the trace grid at padded
/// node (i + reach, j + reach).
///
/// The unblurred distance and the horizontal pass of the separable blur
/// are remembered per node in buffers kept across calls (statics are per
/// isolate, and each isolate fuses one outline at a time), so each is
/// computed once.
class _BlurredUnion {
  _BlurredUnion(
    OutlineBoxes boxes,
    Rect area,
    double step,
    this.cols,
    int rows,
    this.kernel,
  ) : reach = kernel.length ~/ 2,
      width = cols + kernel.length - 1,
      height = rows + kernel.length - 1,
      window = (kernel.length ~/ 2) * step,
      _dense = step >= 4,
      deviation = _deviationOf(kernel, step),
      _menuX = Float64List(cols + kernel.length - 1),
      _menuY = Float64List(rows + kernel.length - 1),
      _sourceX = Float64List(cols + kernel.length - 1),
      _sourceY = Float64List(rows + kernel.length - 1),
      _menuRadius = boxes.radius(0),
      _sourceRadius = boxes.radius(1),
      _menuInner = Offset(
        boxes.halfX(0) - boxes.radius(0),
        boxes.halfY(0) - boxes.radius(0),
      ),
      _sourceInner = Offset(
        boxes.halfX(1) - boxes.radius(1),
        boxes.halfY(1) - boxes.radius(1),
      ) {
    final left = area.left - reach * step;
    final top = area.top - reach * step;
    for (var i = 0; i < width; i++) {
      final x = left + i * step;
      _menuX[i] = (x - boxes.centerX(0)).abs() - _menuInner.dx;
      _sourceX[i] = (x - boxes.centerX(1)).abs() - _sourceInner.dx;
    }
    for (var j = 0; j < height; j++) {
      final y = top + j * step;
      _menuY[j] = (y - boxes.centerY(0)).abs() - _menuInner.dy;
      _sourceY[j] = (y - boxes.centerY(1)).abs() - _sourceInner.dy;
    }
    _Scratch.begin(width * height, cols * height);
    _rawValues = _Scratch.raw;
    _rawStamps = _Scratch.rawStamp;
    _acrossValues = _Scratch.across;
    _acrossStamps = _Scratch.acrossStamp;
    _generation = _Scratch.generation;
    if (_dense) {
      for (var j = 0; j < height; j++) {
        final menuY = _menuY[j];
        final sourceY = _sourceY[j];
        final row = j * width;
        for (var i = 0; i < width; i++) {
          final dg = boxDistance(_menuX[i], menuY, _menuRadius);
          final ds = boxDistance(
            _sourceX[i],
            sourceY,
            _sourceRadius,
          );
          _rawValues[row + i] = dg < ds ? dg : ds;
        }
      }
    }
  }

  static double _deviationOf(Float64List kernel, double step) {
    final reach = kernel.length ~/ 2;
    var variance = 0.0;
    for (var k = 0; k < kernel.length; k++) {
      final x = (k - reach) * step;
      variance += kernel[k] * x * x;
    }
    return math.sqrt(variance);
  }

  final int cols;
  final Float64List kernel;
  final int reach;
  final int width;
  final int height;

  /// The distance from a node to the farthest node of its blur window
  /// along each axis.
  final double window;

  /// Whether the whole grid is sampled up front: at a coarse step the band
  /// the blur reaches covers most of it, and a plain array beats a memo.
  final bool _dense;

  /// The standard deviation of the truncated kernel along each axis.
  final double deviation;

  final Float64List _menuX;
  final Float64List _menuY;
  final Float64List _sourceX;
  final Float64List _sourceY;
  final double _menuRadius;
  final double _sourceRadius;
  final Offset _menuInner;
  final Offset _sourceInner;

  /// The menu's distance at trace node (i, j).
  double menuDistance(int i, int j) =>
      boxDistance(_menuX[i + reach], _menuY[j + reach], _menuRadius);

  /// The button's distance at trace node (i, j).
  double sourceDistance(int i, int j) =>
      boxDistance(_sourceX[i + reach], _sourceY[j + reach], _sourceRadius);

  Float64List _rawValues = _Scratch.raw;
  Int32List _rawStamps = _Scratch.rawStamp;
  Float64List _acrossValues = _Scratch.across;
  Int32List _acrossStamps = _Scratch.acrossStamp;
  int _generation = 0;

  /// Remembers [raw], the unblurred union at trace node (i, j), for the
  /// blur windows that will read it.
  void remember(int i, int j, double raw) {
    if (_dense) return;
    final at = (j + reach) * width + i + reach;
    _rawStamps[at] = _generation;
    _rawValues[at] = raw;
  }

  /// The blurred union at trace node (i, j).
  @pragma('vm:unsafe:no-bounds-checks')
  double blurred(int i, int j) {
    final kernel = this.kernel;
    final taps = kernel.length;
    final generation = _generation;
    final acrossValues = _acrossValues;
    final acrossStamps = _acrossStamps;
    final rawValues = _rawValues;
    final rawStamps = _rawStamps;
    final menuX = _menuX;
    final sourceX = _sourceX;
    final menuRadius = _menuRadius;
    final sourceRadius = _sourceRadius;
    var v = 0.0;
    for (var k = 0; k < taps; k++) {
      final row = j + k;
      final at = row * cols + i;
      double h;
      if (acrossStamps[at] == generation) {
        h = acrossValues[at];
      } else {
        h = 0;
        final menuY = _menuY[row];
        final sourceY = _sourceY[row];
        final base = row * width + i;
        if (_dense) {
          for (var m = 0; m < taps; m++) {
            h += kernel[m] * rawValues[base + m];
          }
          acrossStamps[at] = generation;
          acrossValues[at] = h;
          v += kernel[k] * h;
          continue;
        }
        for (var m = 0; m < taps; m++) {
          final node = base + m;
          double raw;
          if (rawStamps[node] == generation) {
            raw = rawValues[node];
          } else {
            raw = math.min(
              boxDistance(menuX[i + m], menuY, menuRadius),
              boxDistance(sourceX[i + m], sourceY, sourceRadius),
            );
            rawStamps[node] = generation;
            rawValues[node] = raw;
          }
          h += kernel[m] * raw;
        }
        acrossStamps[at] = generation;
        acrossValues[at] = h;
      }
      v += kernel[k] * h;
    }
    return v;
  }

  /// The blurred union at trace node (i, j), where the menu's distance is
  /// [dg] and the button's [ds].
  ///
  /// Where one shape is nearer over the whole blur window, the window may
  /// see one straight side of it, where the field is linear and the
  /// symmetric kernel leaves it unchanged, or one round corner, where the
  /// field is the distance from the corner's center less its radius and
  /// its blur is the mean of a Rice distribution (taken with the kernel's
  /// own variance). Elsewhere the kernel is applied.
  double smoothed(int i, int j, double dg, double ds) {
    final raw = dg < ds ? dg : ds;
    if ((dg - ds).abs() < 2 * math.sqrt2 * window) return blurred(i, j);
    final menu = dg < ds;
    final qx = menu ? _menuX[i + reach] : _sourceX[i + reach];
    final qy = menu ? _menuY[j + reach] : _sourceY[j + reach];
    final inner = menu ? _menuInner : _sourceInner;
    final r = window;
    if ((qx + r <= 0 && qy - qx >= 2 * r && qy + inner.dy >= r) ||
        (qy + r <= 0 && qx - qy >= 2 * r && qx + inner.dx >= r)) {
      return raw;
    }
    if ((inner.dx <= 0 || qx >= r) && (inner.dy <= 0 || qy >= r)) {
      return riceMean(math.sqrt(qx * qx + qy * qy), deviation) -
          (menu ? _menuRadius : _sourceRadius);
    }
    return blurred(i, j);
  }
}

/// The mean distance from the origin of a point drawn from a 2D isotropic
/// Gaussian of standard deviation [sigma] per axis centered [nu] away: the
/// mean of a Rice distribution, `sigma sqrt(pi / 2) L_1/2(-nu^2 / 2
/// sigma^2)`, with the Bessel functions from Abramowitz and Stegun 9.8
/// (relative error under 2e-7).
@internal
double riceMean(double nu, double sigma) {
  final t = nu * nu / (4 * sigma * sigma);
  double i0e;
  double i1e;
  if (t < 3.75) {
    final u = (t / 3.75) * (t / 3.75);
    final decay = math.exp(-t);
    i0e = _horner(_i0Small, u) * decay;
    i1e = t * _horner(_i1Small, u) * decay;
  } else {
    final v = 3.75 / t;
    final root = math.sqrt(t);
    i0e = _horner(_i0Large, v) / root;
    i1e = _horner(_i1Large, v) / root;
  }
  return sigma * math.sqrt(math.pi / 2) * ((1 + 2 * t) * i0e + 2 * t * i1e);
}

// The polynomial approximations of the scaled modified Bessel functions
// I0 and I1 (Abramowitz and Stegun 9.8.1 - 9.8.4), lowest power first.
const _i0Small = [
  1.0, 3.5156229, 3.0899424, 1.2067492, 0.2659732, 0.0360768, 0.0045813, //
];

const _i1Small = [
  0.5, 0.87890594, 0.51498869, 0.15084934, 0.02658733, 0.00301532, //
  0.00032411,
];

const _i0Large = [
  0.39894228, 0.01328592, 0.00225319, -0.00157565, 0.00916281, //
  -0.02057706, 0.02635537, -0.01647633, 0.00392377,
];

const _i1Large = [
  0.39894228, -0.03988024, -0.00362018, 0.00163801, -0.01031555, //
  0.02282967, -0.02895312, 0.01787654, -0.00420059,
];

double _horner(List<double> c, double x) {
  var acc = c.last;
  for (var k = c.length - 2; k >= 0; k--) {
    acc = c[k] + x * acc;
  }
  return acc;
}

/// The buffers [_BlurredUnion] remembers its nodes in, kept across calls
/// and invalidated by a generation count instead of being cleared.
abstract final class _Scratch {
  static Float64List raw = Float64List(0);
  static Int32List rawStamp = Int32List(0);
  static Float64List across = Float64List(0);
  static Int32List acrossStamp = Int32List(0);
  static int generation = 0;
  static Float64List _trace = Float64List(0);
  static final List<Float64List> _fields = [
    for (var i = 0; i < 4; i++) Float64List(0),
  ];

  /// Field grid buffer [index] with room for at least [values] values,
  /// overwritten by every call.
  static Float64List field(int index, int values) {
    if (_fields[index].length < values) {
      _fields[index] = Float64List(values + values ~/ 2);
    }
    return _fields[index];
  }

  static final List<Float64List> _optics = [
    for (var i = 0; i < 4; i++) Float64List(0),
  ];

  /// Optical corner buffer [index] with room for at least [values] values,
  /// overwritten by every call.
  static Float64List optics(int index, int values) {
    if (_optics[index].length < values) {
      _optics[index] = Float64List(values + values ~/ 2);
    }
    return _optics[index];
  }

  static Uint8List _columns = Uint8List(0);

  /// A byte per field column, overwritten by every call.
  static Uint8List columns(int count) {
    if (_columns.length < count) _columns = Uint8List(count + count ~/ 2);
    return _columns;
  }

  /// A trace grid of at least [nodes] nodes; only the nodes a caller
  /// writes are meaningful.
  static Float64List trace(int nodes) {
    if (_trace.length < nodes) _trace = Float64List(nodes + nodes ~/ 2);
    return _trace;
  }

  static void begin(int rawNodes, int acrossNodes) {
    if (raw.length < rawNodes) {
      raw = Float64List(rawNodes + rawNodes ~/ 2);
      rawStamp = Int32List(raw.length);
      rawStamp.fillRange(0, rawStamp.length, generation);
    }
    if (across.length < acrossNodes) {
      across = Float64List(acrossNodes + acrossNodes ~/ 2);
      acrossStamp = Int32List(across.length);
      acrossStamp.fillRange(0, acrossStamp.length, generation);
    }
    generation++;
    if (generation == 0x3FFFFFFF) {
      generation = 1;
      rawStamp.fillRange(0, rawStamp.length, 0);
      acrossStamp.fillRange(0, acrossStamp.length, 0);
    }
  }
}
