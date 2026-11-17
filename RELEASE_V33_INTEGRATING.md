# PID Tuner Pro v3.3 — Tuning Rules for an Integrating Process

## New Settings → PI tuning method

**Tuning Rules for an Integrating Process (SIMC PI)** is available
under Settings → Selected PI calculation method, using a physically
different **IPDT** model from self-regulating FOPDT:

    G(s) = Ki * exp(-L*s) / s

Ki is the change in PV slope per MV step, in normalized
(% PV span/second)/(% MV span), i.e. 1/second.
L is effective apparent dead time in **seconds**.

The original **Skogestad SIMC PI** tuning rules are:

    Kc = 1 / (abs(Ki) * (lambda + L))
    Ti = 4 * (lambda + L)
    Td = 0

The user can select lambda (desired closed-loop response time in
seconds) in Settings. When empty, the initial conservative assumption
is lambda = 3 * L. If L = 0, enter a positive lambda explicitly.
A longer lambda is less aggressive, but must still satisfy plant
disturbance rejection and safe PV deviation requirements.

**References:**
- Sigurd Skogestad & Chriss Grimholt, "The SIMC Method for Smooth PID
  Controller Tuning" (2012), Table 5.1, row "Integrating":
  https://skoge.folk.ntnu.no/publications/2012/skogestad-improved-simc-pid/PIDbook-chapter5.pdf
- ISA InTech "Loop tuning basics: Integrating processes" (2016):
  https://www.isa.org/intech-home/2016/march-april/departments/loop-tuning-basics-integrating-processes

## Step Test methodology

Select one of two integrating acquisition methods:

- **Manual integrating slope:** record MV before and after the single
  safe step, PV at two times *after the delay*, elapsed times, dead
  time L, engineering spans, and *baseline PV drift before the step*.
  Slope change is post-step slope minus baseline slope. No steady PV1
  or t63% is required. Manual estimates have **no regression quality
  scores**.
- **Integrating CSV:** supply uniformly sampled time/mv/pv trend,
  one isolated sustained MV step and enough pre/post samples. A
  fitted delayed ramp on top of the measured initial PV slope yields
  Ki, L, model trend, R² and NRMSE. Apparent first-order plateau
  responses are explicitly rejected by a slope-collapse check.
  When quality criteria fail, data can be stored for review but PI
  estimates are blocked.

Selecting a different tuning method returns to the existing
self-regulating FOPDT Step Test methodology. The integrating method
is a distinct calculation; FOPDT models cannot be fed to SIMC-IPDT
and IPDT models cannot be fed to classic FOPDT PI correlations.

For level, this new rule is suggested **conditionally**. The user
must confirm that the actual process is integrating, based on
measured response, before the web app provides PI parameters. A
self-regulating level process can use the existing FOPDT methods
after independent confirmation.

## Browser database

The existing Safari IndexedDB keeps its schema version and stores
both types of records in the existing append-only identifications
store. Existing FOPDT records remain readable, and new IPDT records
are labelled "type: IPDT", with "KiPerSecond" and "L" rather than
mislabelled steady-state K/T. Records retain a snapshot of Settings,
method, measurements/evidence, computed PI settings and any input CSV.
All data remain local to Safari, and can be lost if site data are
cleared; there is still no cloud sync or permanent backup.

## Safety and verification

These calculations are for **ideal PI (Td = 0)**, not full PID with
derivative. Per-vendor parameter displays (Yokogawa PB or normalized
ABB/Siemens/Honeywell/Emerson gain equivalents) must be checked
against the actual controller block algorithm, scaling, integral
time units, control action and limits. The web app cannot control
a DCS and must never directly write candidate parameters to the
plant. Integrating process Step Tests can continue to move toward
unsafe PV limits; only use an approved plant-specific procedure,
with a safe exit plan, operator approval and sufficient level margin.

## Safari site

Once successful CI builds and deploys this branch, the site remains:
https://som13x.github.io/pid-tuner-pro/
