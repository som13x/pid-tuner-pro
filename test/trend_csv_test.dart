import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/trend_csv.dart';

void main() {
  test('semicolon CSV and comma decimal normalize engineering spans', () {
    const csv='time;MV;PV\n0;50,0;20,0\n1;60,0;30,0\n';
    final points=const TrendCsv().parse(csv,
        mvLow:0,mvHigh:200,pvLow:0,pvHigh:40);
    expect(points.length,2);
    expect(points[0].mv,25);
    expect(points[1].pv,75);
  });
  test('quoted header and reordered columns', () {
    const csv='"pv","time","mv"\n40,0,50\n42,1,55\n';
    final p=const TrendCsv().parse(csv);
    expect(p.last.seconds,1);
    expect(p.last.mv,55);
  });
  test('rejects duplicate timestamps', () {
    expect(() => const TrendCsv().parse('time,mv,pv\n0,1,2\n0,3,4'),
        throwsFormatException);
  });
  test('rejects missing column', () {
    expect(() => const TrendCsv().parse('time,mv,x\n0,1,2\n1,2,3'),
        throwsFormatException);
  });
  test('rejects invalid engineering span', () {
    expect(() => const TrendCsv().parse('time,mv,pv\n0,1,2\n1,2,3',
        mvLow:10,mvHigh:10), throwsArgumentError);
  });
}
