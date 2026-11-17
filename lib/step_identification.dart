import 'dart:math' as math;
import 'auto_tune.dart';

/// Timestamped samples, with MV/PV in percent of their respective spans.
class TrendPoint {
  final double seconds, mv, pv;
  const TrendPoint(this.seconds, this.mv, this.pv);
}

class IdentificationResult {
  final Plant plant;
  final double stepAt, mvBefore, mvAfter, pvBefore;
  final double rmse, rSquared, normalizedRmse;
  final int fittedPoints;
  const IdentificationResult({required this.plant, required this.stepAt,
    required this.mvBefore, required this.mvAfter, required this.pvBefore,
    required this.rmse, required this.rSquared,
    required this.normalizedRmse, required this.fittedPoints});
  bool get suitableForAutoTune => fittedPoints >= 20 &&
      rSquared >= 0.90 && normalizedRmse <= 0.10;
}

/// Fits a FOPDT step response by deterministic bounded grid search.
/// Assumptions: one isolated, sustained MV step; near-steady initial PV;
/// constant operating point; approximately uniform timestamps.
class StepIdentifier {
  final double minStep, minPreSeconds;
  const StepIdentifier({this.minStep = 2, this.minPreSeconds = 5});

  IdentificationResult identify(List<TrendPoint> points, {double? manualStepAt}) {
    if (points.length < 30) throw ArgumentError('At least 30 samples required');
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (![p.seconds,p.mv,p.pv].every((v) => v.isFinite) ||
          (i > 0 && p.seconds <= points[i-1].seconds)) {
        throw ArgumentError('Invalid or unsorted trend');
      }
    }
    final dt = (points.last.seconds - points.first.seconds) /
        (points.length - 1);
    if (dt <= 0) throw ArgumentError('Invalid timebase');
    for (var i = 1; i < points.length; i++) {
      final delta = points[i].seconds - points[i-1].seconds;
      if ((delta-dt).abs() > dt * .10) {
        throw ArgumentError('Resample trend to a uniform timebase');
      }
    }
    final preCount = math.max(5, (minPreSeconds/dt).ceil());
    if (preCount >= points.length ~/ 3) {
      throw ArgumentError('Insufficient pre-step baseline');
    }
    final mv0 = _mean(points.take(preCount).map((p) => p.mv));
    final pv0 = _mean(points.take(preCount).map((p) => p.pv));
    final beforeNoise = math.sqrt(_mean(points.take(preCount)
        .map((p) => math.pow(p.pv-pv0, 2).toDouble())));
    int? stepIndex;
    if (manualStepAt != null) {
      if (!manualStepAt.isFinite) throw ArgumentError('Invalid manual step time');
      for (var i = preCount; i < points.length-20; i++) {
        if (points[i].seconds >= manualStepAt) { stepIndex = i; break; }
      }
      if (stepIndex == null || (points[stepIndex].mv-mv0).abs() < minStep ||
          (points[stepIndex-1].mv-mv0).abs() >= minStep) {
        throw ArgumentError('Manual step time must coincide with a sustained MV step');
      }
    } else {
      for (var i = preCount; i < points.length-20; i++) {
        if ((points[i].mv-mv0).abs() >= minStep) { stepIndex = i; break; }
      }
    }
    if (stepIndex == null) throw ArgumentError('No sustained MV step');
    final index = stepIndex;
    final mv1 = _mean(points.skip(index).take(5).map((p) => p.mv));
    final deltaMv = mv1-mv0;
    if (deltaMv.abs() < minStep) throw ArgumentError('MV step too small');
    // Reject repeated or drifting MV after the step.
    if (points.skip(index).any((p) => (p.mv-mv1).abs() >
        math.max(.5, deltaMv.abs()*.08))) {
      throw ArgumentError('Multiple steps or MV drift detected');
    }
    final post = points.skip(index).toList();
    final stepAt = points[index].seconds;
    final horizon = post.last.seconds-stepAt;
    if (horizon <= 10*dt) throw ArgumentError('Insufficient post-step data');
    final pvSpan = post.map((p) => (p.pv-pv0).abs()).reduce(math.max);
    if (pvSpan < math.max(.1, beforeNoise*5)) {
      throw ArgumentError('PV response below noise floor');
    }
    // y(t)=K*deltaMV*(1-exp(-(t-L)/tau)) for t>L.
    // For fixed (L,tau), solve least-squares gain analytically.
    double bestSse = double.infinity, bestL = 0, bestTau = 0, bestK = 0;
    final maxDelay = horizon*.65;
    final minTau = math.max(dt*.5, 1e-6);
    final maxTau = horizon*4;
    void evaluate(double delay, double tau) {
      var xy=0.0, xx=0.0, sse=0.0;
      for (final p in post) {
        final elapsed=p.seconds-stepAt-delay;
        final x=elapsed<=0?0.0:deltaMv*(1 - math.exp(-elapsed/tau));
        final y=p.pv-pv0;
        xy+=x*y; xx+=x*x;
      }
      if (xx < 1e-12) return;
      final k=xy/xx;
      if (!k.isFinite || k.abs()<1e-8) return;
      for (final p in post) {
        final elapsed=p.seconds-stepAt-delay;
        final x=elapsed<=0?0.0:deltaMv*(1 - math.exp(-elapsed/tau));
        final residual=(p.pv-pv0)-k*x;
        sse+=residual*residual;
      }
      if (sse<bestSse) {bestSse=sse;bestL=delay;bestTau=tau;bestK=k;}
    }
    for (var i=0;i<=40;i++) {
      final l=maxDelay*i/40;
      for (var j=0;j<=60;j++) {
        final tau=minTau*math.pow(maxTau/minTau,j/60).toDouble();
        evaluate(l,tau);
      }
    }
    for (var round=0;round<3;round++) {
      final lRange=maxDelay/math.pow(40,round+1);
      final tRange=bestTau*.3/math.pow(3,round);
      final centerL=bestL,centerT=bestTau;
      for (var i=-8;i<=8;i++) {
        final l=(centerL+i*lRange/8).clamp(0.0,maxDelay).toDouble();
        for (var j=-8;j<=8;j++) {
          final tau=(centerT+j*tRange/8).clamp(minTau,maxTau).toDouble();
          evaluate(l,tau);
        }
      }
    }
    final total=post.fold<double>(0,(s,p)=>s+math.pow(p.pv-pv0,2));
    final rmse=math.sqrt(bestSse/post.length);
    final r2=total<=0?0.0:1-bestSse/total;
    return IdentificationResult(plant:Plant(gain:bestK,tau:bestTau,delay:bestL),
      stepAt:stepAt,mvBefore:mv0,mvAfter:mv1,pvBefore:pv0,
      rmse:rmse,rSquared:r2,normalizedRmse:rmse/pvSpan,
      fittedPoints:post.length);
  }

  static double _mean(Iterable<double> values) {
    var sum=0.0,n=0;
    for (final v in values) {sum+=v;n++;}
    return sum/n;
  }
}
