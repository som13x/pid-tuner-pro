import 'dart:math' as math;
import 'step_identification.dart';

/// Converts exported historian CSV into normalized MV/PV (% of span).
/// Supports comma, semicolon and tab separators, quoted fields and
/// comma decimals when separator is semicolon or tab.
class TrendCsv {
  const TrendCsv();

  List<TrendPoint> parse(String csv, {
    String timeColumn = 'time', String mvColumn = 'mv',
    String pvColumn = 'pv', double mvLow = 0, double mvHigh = 100,
    double pvLow = 0, double pvHigh = 100,
  }) {
    if (![mvLow,mvHigh,pvLow,pvHigh].every((v) => v.isFinite) ||
        mvHigh <= mvLow || pvHigh <= pvLow) {
      throw ArgumentError('Invalid engineering spans');
    }
    final lines = csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
        .split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 3) throw FormatException('CSV requires header and data');
    final first = lines.first.replaceFirst('\uFEFF', '');
    final delimiter = [';', ',', '\t'].reduce((a,b) =>
        _fields(first,b).length > _fields(first,a).length ? b : a);
    final header = _fields(first,delimiter)
        .map((s) => s.trim().toLowerCase()).toList();
    int column(String name) {
      final i = header.indexOf(name.trim().toLowerCase());
      if (i < 0) throw FormatException('Missing CSV column: $name');
      return i;
    }
    final t = column(timeColumn), m = column(mvColumn), p = column(pvColumn);
    double number(String s) {
      final value = double.tryParse(s.trim().replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        throw FormatException('Invalid numeric value: $s');
      }
      return value;
    }
    final result = <TrendPoint>[];
    for (var i=1; i<lines.length; i++) {
      final fields = _fields(lines[i],delimiter);
      if (fields.length != header.length) {
        throw FormatException('Wrong number of columns at row ${i+1}');
      }
      final time=number(fields[t]), mv=number(fields[m]), pv=number(fields[p]);
      if (result.isNotEmpty && time <= result.last.seconds) {
        throw FormatException('Time must increase at row ${i+1}');
      }
      result.add(TrendPoint(time,100*(mv-mvLow)/(mvHigh-mvLow),
          100*(pv-pvLow)/(pvHigh-pvLow)));
    }
    return result;
  }

  static List<String> _fields(String line, String delimiter) {
    final result=<String>[];
    final current=StringBuffer();
    var quoted=false;
    for (var i=0;i<line.length;i++) {
      final c=line[i];
      if (c=='"') {
        if (quoted && i+1<line.length && line[i+1]=='"') {
          current.write('"');i++;
        } else { quoted=!quoted; }
      } else if (c==delimiter && !quoted) {
        result.add(current.toString());current.clear();
      } else {current.write(c);}
    }
    if (quoted) throw FormatException('Unterminated CSV quote');
    result.add(current.toString());
    return result;
  }
}

/// Predicted response for a validated FOPDT fit; output is normalized PV.
List<TrendPoint> fittedResponse(List<TrendPoint> measured,
    IdentificationResult fit) {
  final deltaMv=fit.mvAfter-fit.mvBefore;
  return measured.map((p) {
    final elapsed=p.seconds-fit.stepAt-fit.plant.delay;
    final fraction=elapsed<=0?0.0:(1 - math.exp(-elapsed/fit.plant.tau));
    return TrendPoint(p.seconds,p.mv,
        fit.pvBefore+fit.plant.gain*deltaMv*fraction);
  }).toList();
}
