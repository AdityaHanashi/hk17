import 'dart:math';

List<Map<String, dynamic>> parseAndFilterDetections(dynamic output,
    {double confidenceThreshold = 0.45, int inputSize = 640}) {
  List<double> xCenters = [];
  List<double> yCenters = [];
  List<double> widths = [];
  List<double> heights = [];
  List<double> confidences = [];

  try {
    final o = output;

    if (o is List && o.isNotEmpty && o[0] is List && (o[0] as List).length == 8400) {
      // channels-first [5][8400]
      xCenters = (o[0] as List).cast<double>();
      yCenters = (o[1] as List).cast<double>();
      widths = (o[2] as List).cast<double>();
      heights = (o[3] as List).cast<double>();
      confidences = (o[4] as List).cast<double>();
    } else if (o is List &&
        o.isNotEmpty &&
        o.length == 8400 &&
        o[0] is List &&
        (o[0] as List).length >= 5) {
      // anchors-first [8400][5]
      for (var r in o) {
        final row = (r as List).cast<double>();
        xCenters.add(row[0]);
        yCenters.add(row[1]);
        widths.add(row[2]);
        heights.add(row[3]);
        confidences.add(row[4]);
      }
    } else {
      return [];
    }
  } catch (e) {
    print("❌ parseAndFilterDetections: $e");
    return [];
  }

  final int N = confidences.length;
  if (N == 0) return [];

  double maxVal = 0;
  for (int i = 0; i < N; i++) {
    maxVal = max(maxVal, [
      xCenters[i].abs(),
      yCenters[i].abs(),
      widths[i].abs(),
      heights[i].abs()
    ].reduce(max));
  }

  final bool normalized = maxVal <= 1.05;
  double scale = normalized ? 1.0 : 1 / inputSize;

  final List<Map<String, dynamic>> raw = [];
  for (int i = 0; i < N; i++) {
    final conf = confidences[i];
    if (conf < confidenceThreshold) continue;

    final xc = xCenters[i] * scale;
    final yc = yCenters[i] * scale;
    final w = widths[i] * scale;
    final h = heights[i] * scale;

    raw.add({
      'rect': {
        'x': (xc - w / 2).clamp(0.0, 1.0),
        'y': (yc - h / 2).clamp(0.0, 1.0),
        'w': w.clamp(0.0, 1.0),
        'h': h.clamp(0.0, 1.0),
      },
      'confidenceInClass': conf,
    });
  }

  raw.sort((a, b) =>
      (b['confidenceInClass'] as double).compareTo(a['confidenceInClass'] as double));

  const double iouThreshold = 0.25;
  final List<Map<String, dynamic>> kept = [];

  for (final r in raw) {
    bool keep = true;
    final rect = Map<String, double>.from(r['rect']);
    for (final k in kept) {
      final kr = Map<String, double>.from(k['rect']);
      final double xi1 = max(rect['x']!, kr['x']!);
      final double yi1 = max(rect['y']!, kr['y']!);
      final double xi2 = min(rect['x']! + rect['w']!, kr['x']! + kr['w']!);
      final double yi2 = min(rect['y']! + rect['h']!, kr['y']! + kr['h']!);
      final double interW = max(0.0, xi2 - xi1);
      final double interH = max(0.0, yi2 - yi1);
      final double interArea = interW * interH;
      final double aArea = rect['w']! * rect['h']!;
      final double bArea = kr['w']! * kr['h']!;
      final double union = aArea + bArea - interArea;
      final double iou = union <= 0 ? 0.0 : interArea / union;
      if (iou > iouThreshold) {
        keep = false;
        break;
      }
    }
    if (keep) kept.add(r);
  }

  return kept;
}