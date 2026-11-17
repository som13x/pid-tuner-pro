# PID Tuner Pro v3.6 — OptiControls T1/T2 in minutes

## Source and requested change

Jacques Smuts, Level Controller Tuning, OptiControls, December 2011:
https://blog.opticontrols.com/level-control-loop-tuning/

Original procedure defines T1 and T2 as elapsed durations between
two PV measurements on Slope 1 and Slope 2, NOT as absolute timestamps.
The user requested all manual Step Test time entries in minutes.

Settings -> OptiControls -> Integrating manual Step Test displays:

- Slope 1 before MV step: PV1, PV2, T1 (minutes), the elapsed
  interval between the two PV observations.
- Slope 2 after dead time: PV3, PV4, T2 (minutes), the elapsed
  interval between the two PV observations.
- Effective dead time td (minutes), from MV step to the
  extrapolated lines' intersection.
- MV0 and MV1 and engineering ranges for MV and PV.

The four absolute timestamp fields t1..t4 are removed.
The inputs are positive durations T1 and T2, with td >= 0.

## Calculation

    slope1 = (PV2-PV1)/T1             [PV unit/min]
    slope2 = (PV4-PV3)/T2             [PV unit/min]
    DS = slope2-slope1                [PV unit/min]
    DS% = 100*DS/(PV high-PV low)      [%PV/min]
    deltaMV% = 100*(MV1-MV0)/(MV high-MV low)
    ri = DS% / deltaMV%               [1/min]

OptiControls PI/PID rules (SM >= 2):

    PI:  Kc = 0.9/(SM*abs(ri)*td)
         Ti = 3.33*SM*td               [min]
         Td = 0
    PID: Kc = 1.2/(SM*abs(ri)*td)
         Ti = 2*SM*td                  [min]
         Td = td/2                     [min]

Existing IPDT internals store gainPerSecond and delaySeconds. Conversion
occurs only at the boundary from manual minutes input:

    gainPerSecond = ri/60
    delaySeconds = tdMinutes*60

Therefore gain Kc remains identical. PI/PID results are stored with
time in seconds, and OptiControls Step Test displays Ti/Td in minutes.
Always check the actual DCS controller's algorithm, time units and
parameter scaling before transferring candidate values.

## Data compatibility

- IndexedDB saves each new manual result with all PV1..PV4 and
  T1Minutes, T2Minutes, deadTimeMinutes, as well as converted values,
  identified gain/dead time and a complete Settings snapshot.
- New records do not invent or store absolute point timestamps.
- Previous absolute timestamp-based four-point records remain untouched.
- Existing CSV integrating identification continues to use its normal
  time-in-seconds input. This change concerns manual four-point Step Test.

All operations are offline. Approval and a site-specific safe test
procedure remain necessary for real plant trials.

Preview URL after green CI/deployment:
https://som13x.github.io/pid-tuner-pro/
