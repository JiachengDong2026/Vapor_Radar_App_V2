# WMS numerical definition and golden model

Let signed Q1.31 values represent integer/2^31. Valid range is [-1,1-2^-31]. Saw and sine phase are unsigned U32 fractions of one turn. The saw integer is signed(phase XOR 0x80000000), equivalent to the frozen modulo subtraction definition.

For system clock F, request R and frequency f in millihertz:

```
P = ceil(F / R)
ACT = floor(F / P)
phase_inc = floor((f * P * 2^32 + F*500) / (F*1000))
```

DDS calculation uses the exact P/F sample interval, not the truncated ACT readback. The long-term generated frequency is phase_inc*F/(P*2^32). Maximum rounding error is F/(2*P*2^32) Hz. Requested rate is never exceeded. Zero sine increment is a valid DC reference; zero saw increment is rejected because scans would never recur.

The 4096-entry ROM uses phase[31:20]; lower 20 bits are truncated. Entries are round-to-nearest sine*2^31, clamped to signed range. Quadrant values are 0, 0x7FFFFFFF, 0, 0x80000000. Phase quantization is below one LUT bin (2*pi/4096 rad); worst sine amplitude error from phase truncation is bounded by that angle plus half a Q31 LSB. This is a finite-resolution LUT, not an interpolated high-SFDR claim.

Each multiply is signed 32x32 into 64 bits. Round back with `(product + 2^30) >>> 31`; ties go toward positive infinity for either sign. Both rounded terms and offset are sign-extended to 66 bits before adding. Sum clips to [-2147483648,2147483647]; each clipped output increments SAT_COUNT once. Neither products nor sum are allowed to wrap into a false in-range result.

`scripts/generate_vectors.py` is a separate Python arbitrary-precision model. It generates 192 saw-only/sine-only/mixed/positive-negative-saturation samples over exact quadrants and wraps, plus 700 samples with fractional DDS increments, nonzero phase, signed amplitudes and noncardinal lookup positions. It also produces 505 independently addressed LUT checks and 133 DAC mapping vectors. The RTL test compares exact integer values, reference phases, cycle IDs and sample cadence. Python's mathematical sine constructs the explicitly defined lookup table; no RTL internal phase/sum state is used by the checker.
