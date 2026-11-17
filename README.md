# PID Tuner Pro - Auto Tune Studio core

Offline Dart prototype for a PI loop. Run `dart pub get` then `dart test` in this folder.

Default parameters: PB 40..250%, Ti 5..80 s, MV slew 5%/s, PV error limit 10% of span, additive output step disturbance +6% at t=30 s, FOPDT K=0.8, T=12 s, L=3 s, simulation 300 s. Baseline PB=120%, Ti=20 s.

`AutoTune(Plant(gain: 0.8, tau: 12, delay: 3)).search()` returns up to five feasible candidates, evaluated count, and baseline. Ranking: minimum total MV travel, tie-breaker IAE. Rejection: excessive PV deviation, excess MV slew, numerical divergence, no recovery inside horizon.

**Engineering limitations:** Simplified ideal PI with proportional-on-error, conditional integration and an output disturbance; not a validated Yokogawa CENTUM VP PID digital twin. All values normalized to % spans. Initial equilibrium SP=PV=50%, MV=50%. Process model and disturbance are synthetic. No automatic DCS writes. Real use requires identification, controller profile verification, operator authorization and plant-specific safety review. Recovery is assessed within a finite simulation horizon, not a mathematical stability proof. Model uncertainties, noise, external reset tracking, setpoint weighting and interactions are not yet implemented.

## Flutter example

A standalone Flutter example is under `flutter_example/`.
Run from that directory with `flutter run` after installing Flutter SDK.
The screen calls the pure Dart optimizer in a worker isolate (`compute`),
shows up to five candidates, PV and MV trends, baseline comparison, and a
selectable JSON report. It uses the default demonstration FOPDT parameters.
No live DCS connection or controller deployment is implemented.

**Engineering caveats:** This prototype assumes normalized PV/MV spans,
initial equilibrium, additive output disturbance, and a simplified PI structure.
The simulated controller is not a validated Yokogawa CENTUM VP emulator.
The absolute PV deviation threshold is expressed in percent of measurement span.


## v0.3 Step Test identification

`lib/step_identification.dart` identifies a FOPDT plant from uniformly sampled
MV/PV trends containing **one sustained step**. It estimates process gain,
time constant, dead time, RMSE, R², and normalized RMSE using a bounded
grid search with local refinement. The output `IdentificationResult.plant`
can be passed to `AutoTune(plant, config)` after engineering review.

Example:

```dart
final id = const StepIdentifier().identify(trendPoints);
if (!id.suitableForAutoTune) {
  throw StateError('Identification quality too low');
}
final result = AutoTune(id.plant).search();
```

**Limits:** normalized % span required for both MV and PV; one isolated
step; approximately uniform sampling; stationary initial PV; sufficient
response duration. The quality flag is a heuristic, not plant approval.
Do not use for integrating, nonlinear, or strongly interacting processes
without a suitable model. The fitted model must be independently validated
before using proposed settings on a real plant.

Run `dart pub get && dart test` where the Dart SDK is installed.

## v0.4 CSV Step Test screen

- `lib/trend_csv.dart`: local CSV parser (comma/semicolon/tab, quotes,
  decimal commas with semicolon-separated exports), engineering span
  normalization and fitted FOPDT response generator.
- `test/trend_csv_test.dart`: five new parsing/validation tests.
- `flutter_example/lib/main.dart`: Step Test screen accessible from the
  Auto Tune app bar. Paste exported CSV, set MV/PV high spans, identify
  and overlay measured/fitted PV curves.

**Known limitations:** CSV paste, not OS file picking yet; low span fixed to
zero in UI (parser accepts arbitrary low/high spans); no manual step marker
or irregular-timestamp resampling; Step Test is not wired to replace the
Auto Tune demonstration model yet. All fitting assumptions from v0.3 apply.


## v0.5: file import and Step Test → Auto Tune

- Flutter example uses `file_picker` to import UTF-8 CSV/TXT (max 10 MB).
- Optional manual step timestamp, validated against actual MV transition.
- `StepTestScreen` returns the identified FOPDT model to `AutoTuneScreen` only when formal fit thresholds pass.
- The isolate receives identified gain, time constant, and dead time instead of always using demo constants.
- Added two manual step tests. Replaced unsupported `math.expm1` calls with `1 - exp(...)` for Dart compatibility.

Run `flutter pub get` in `flutter_example`, then `flutter run`; run `dart pub get && dart test` in the package root. The Flutter example remains a demo, not a production-ready control engineering tool.

## v0.6: Robust tuning across multiple Step Tests

`lib/robust_tune.dart` adds `PlantObservation`, `ModelEnsemble`, and
`RobustAutoTune`. Build an ensemble from at least two quality-approved
identification results, then search for PB/Ti values that satisfy **all**
model scenarios. The scenarios include every observed FOPDT model, a midpoint,
and all combinations of the observed min/max gain, lag, and delay. This is a
**deterministic stress-test envelope**, not a statistically justified confidence
interval or formal stability guarantee.

```dart
import 'lib/auto_tune.dart';
import 'lib/robust_tune.dart';

void main() {
  final ensemble = ModelEnsemble.build([
    const PlantObservation(Plant(gain: .7, tau: 10, delay: 2),
      label: 'Step 1', rSquared: .97, normalizedRmse: .03),
    const PlantObservation(Plant(gain: .9, tau: 16, delay: 5),
      label: 'Step 2', rSquared: .96, normalizedRmse: .04),
  ]);
  final result = RobustAutoTune(ensemble, const TuneConfig(
    pbMin: 40, pbMax: 250, tiMin: 5, tiMax: 80,
    maxMvRate: 5, maxAbsPvError: 10,
  )).search();
  print('Scenarios: ${result.scenarioCount}; feasible: ${result.feasibleCount}');
  for (final c in result.best) {
    print('PB=${c.pb}, Ti=${c.ti}, worst travel=${c.worstTravel}');
  }
}
```

Run tests with `dart pub get && dart test`. Flutter UI wiring and database
persistence of multiple tests remain future work. Model quality gates only
use R² and NRMSE, not an independent validation dataset. Gain-sign changes
cause rejection. Cross-correlated uncertainty, nonlinear valves, interaction
between parallel LNG lines, plant constraints, and formal stability margins
are not modelled. Always validate in an approved engineering workflow before
applying settings to a live DCS.

## v0.7 Stability Analysis

`lib/stability_analysis.dart` adds continuous-time ideal PI + FOPDT frequency analysis:
- frequency response and Bode points, gain crossover, phase crossover;
- phase margin (degrees), gain margin (dB, `null` means infinite for L=0);
- screening against configurable minimum margins (default 45° / 6 dB);
- checks across every model in the v0.6 uncertainty ensemble;
- `filterByStability` to screen time-domain robust candidates.

**Critical limitations:** These calculations assume ideal PI, matching normalized PV/MV spans, correct controller action, linear FOPDT, no actuator saturation, and no sampling/filter dynamics. This is not an exact Yokogawa CENTUM VP block emulation, nor a formal robust-stability proof. A candidate passing both time-domain and frequency screens still requires engineering review and authorized plant testing. The nominal demo values are not plant measurements.

Run `dart pub get && dart test` when Dart SDK is installed. The tests have not been executed in this environment.

## v0.8 Stability Studio (prototype)

`lib/stability_studio.dart` evaluates robust time-domain candidates against
frequency-domain gain/phase margins on every enumerated FOPDT model.
`flutter_example/lib/stability_screen.dart` provides a UI for two demonstration
plant models, configurable PM/GM limits, candidate status, scenario table,
Bode magnitude/phase plots and JSON output. Open it from the chart icon on the
Auto Tune screen. Heavy calculations run in an isolate.

**Important:** the demonstration screen assigns example fit-quality values
(R²=0.99, NRMSE=0.02) to manually entered K/T/L. These are NOT measured
quality scores. It must not be used to certify a real plant model. For a
production workflow, feed actual validated `PlantObservation` instances from
Step Test and preserve their operating conditions.

The search ranks by valve travel using time-domain feasibility first, then
filters by frequency margins. A candidate rejected by PM/GM stays visible with
violations. This is shortlist screening, not globally constrained optimization
or a proof of robust stability. The Bode plot uses unwrapped phase and a
log-frequency axis. Model is ideal continuous PI + FOPDT; controller-specific
CENTUM VP dynamics, sampling, valve nonlinearities and plant coupling are not
modeled. Do not apply results directly to a running plant.

Run locally with Dart/Flutter SDK installed:

```sh
cd pid_tuner_pro
 dart pub get
 dart test
 cd flutter_example
 flutter pub get
 flutter run
```

## v0.9 Engineering Workflow

`lib/engineering_workflow.dart` connects identified step tests to the model
ensemble, time-domain optimizer and frequency-domain assessment. Each test
carries an ID, source, date and operating-point label. Poor-quality tests are
excluded; fewer than two accepted tests is a hard failure. Mixing operating
points requires explicit approval and must not be interpreted as a validated
interpolation model. Results can be serialized with `WorkflowReport.toJson()`.

This version does **not** prove closed-loop stability or reproduce Yokogawa's
proprietary PID implementation. Run `dart test` in a Dart SDK environment;
these tests have not been executed in this environment.

## v1.5 Combined Robust Optimization

`lib/combined_robust_optimization.dart` implements a **joint** PB/Ti search.
Each coarse-grid and local-refinement candidate is evaluated against **all**
ensemble scenarios in the time domain (PV error, MV rate, valve travel, IAE,
recovery) and in the frequency domain (PM/GM). Local refinement seeds are
selected only from candidates satisfying **both** sets of constraints.
The valve-travel objective breaks ties using worst-case IAE.

`flutter_example/lib/multi_model_tune.dart` now invokes this combined engine
instead of the time-domain top-20 shortlist. JSON reports include the full
number of evaluated candidates, both rejection counts, and feasible count.
This remains a finite-grid scenario analysis, **not** a formal robust-stability
certificate or a verified emulation of Yokogawa CENTUM VP algorithms.
The Flutter/Dart toolchains are not installed in this build environment;
source tests have not been executed here.

## v1.7: Closed-loop simulation core

`lib/closed_loop_studio.dart` provides `ClosedLoopStudio.simulate` and
`compareStructures` for PID, PI-D, I-PD. FOPDT plant uses exact discrete
first-order lag and interpolated actuator dead time. Simulated disturbances
are additive at measured PV. Traces contain SP/PV/MV, mode, saturation and
rate limiting; metrics contain IAE, ISE, peak error, total MV travel, maximum
observed rate and terminal error. MAN/AUTO switching is supported.

This is a **core-library implementation**, not yet a Flutter plotting screen.
It is an engineering approximation and has not been validated against Yokogawa
CENTUM VP firmware. Dart/Flutter SDK is not available in the build environment,
so automated tests are included but have not been executed.

## v1.8 Preview — Closed-Loop Simulation Flutter screen

`flutter_example/lib/simulation_screen.dart` adds a **Simulation** action on
saved loop cards with an identified K/T/L model. The screen accepts normalized
FOPDT and controller parameters, runs the three PID structures on a Flutter
background isolate, displays PV/SP and MV charts, and compares IAE, peak error,
MV travel and terminal error. Parameters and results are **not** persisted yet.
The simulated disturbance is an additive step on PV; this is **not** a physical
two-valve LNG manifold model. Numerical controller is an engineering approximation,
not validated Yokogawa CENTUM VP firmware behavior. Never apply tuning directly
to a live DCS without authorized tests and engineering review.

New core tests: `test/closed_loop_v18_test.dart`. No Flutter/Dart SDK is installed
in the authoring environment; tests and device builds remain unverified.

## v1.9 Preview — Dual-Valve LNG simulation core

`lib/dual_valve_lng.dart` simulates two parallel FOPDT branches into a common
flow header. Branch A has an externally imposed sinusoidal actuator fault while
branch B uses PI control. Three strategies are selectable: PI, filtered-PV PI,
and PI plus measured-branch-flow feedforward. Trace includes A/B branch flows,
total flow, both valve positions, filtered PV and FF correction; metrics include
IAE, maximum absolute error and B-valve travel/rate. `test/dual_valve_lng_test.dart`
contains six tests.

**Engineering limits:** normalized units; branch models are hypothetical,
not identified from real LNG data. Feedforward is added after the controller
and actuator constraints, but internal PI anti-windup does not track the final
post-feedforward output; the strategy is therefore exploratory, not production
ready. Filtering introduces delay and may worsen control. No DCS connectivity.
The Flutter UI for this specific two-valve simulator is not yet implemented.
Dart/Flutter SDK unavailable in this environment; tests were not executed.

## v2.0 Preview — Dual-Valve LNG Simulation UI

The Flutter project screen now has **Dual-Valve LNG**, opening
`flutter_example/lib/dual_valve_screen.dart`. It runs the three existing
`DualValveLngSimulator` strategies in a Dart background isolate, displays
comparative IAE/error/valve travel/rate metrics, and plots combined flow,
branch flows, valve commands and feedforward correction. Branch FOPDT
parameters, PI parameters and fault settings are editable.

**Engineering provenance:** a model identified from total header flow is NOT
necessarily the model of branch A or B. The UI therefore intentionally does
not copy a loop's saved total-flow K/T/L into either branch. The initial branch
models are explicit synthetic examples and must be replaced with separately
identified branch models before interpreting results for a real plant.

**Limitations:** normalized units, sinusoidal mechanical fault, simple
independent FOPDT branches, feedforward applied downstream of PI without
full anti-windup tracking. No live DCS connection or verified CENTUM VP
firmware behavior. Do not deploy proposed control changes to LNG equipment
without engineering review, safeguards, and plant-specific validation.

This environment has no Flutter/Dart SDK: compilation and automated test
execution have not been verified.
