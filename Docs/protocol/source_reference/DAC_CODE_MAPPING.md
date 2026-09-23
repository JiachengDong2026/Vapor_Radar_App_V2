# Q1.31 to AD5791 code mapping

For signed input integer x, unsigned gain g in UQ2.30, signed offset o in DAC codes:

```
u = x + 2^31
base = floor((u*1048575 + 2^31) / 2^32)
scaled = floor((base*g + 2^29) / 2^30) + o
code = min(MAX_CODE, max(MIN_CODE, scaled))
```

Multiplication and rounding retain wide intermediates. `base` is nonnegative. Scale is applied to offset-binary code, so gain changes are about code zero, not midscale; software can pair gain with OFFSET_CODE to scale about any desired center. For gain=1, offset=0 and full window:

|Normalized input|Q1.31|DAC code decimal|20-bit hex|Ideal VDAC for -10/+10 V references|
|---|---|---|---|---|
|-1|80000000|0|00000|-10 V|
|-0.5|C0000000|262144|40000|-4.99999523 V|
|0|00000000|524288|80000|+0.00000954 V|
|+0.5|40000000|786431|BFFFF|+4.99999523 V|
|maximum positive|7FFFFFFF|1048575|FFFFF|+10 V|

These endpoint-rounding choices match the defined 20-bit offset-binary map. Zero normalized input becomes upper midscale, not a promise of exact 0 V. Ideal DAC voltage from AD5791 Rev F transfer relation is `VREFN + (VREFP-VREFN)*code/(2^20-1)`. This applies at the DAC output with the specified buffer configuration. Board Bessel filter, selected jumpers, gain, 50-ohm termination and calibration determine SMA voltage; no calibrated connector transfer is claimed.

Default CLEAR_CODE is 0x80000. Default min/max is full range; software must choose a narrower acceptable output window for its application. Commit requires clearcode inside the same window. Saturation before SPI increments CLAMP_COUNT. LAST_CODE and WRITE_COUNT change on completed sample SYNC rise; initialization sets LAST_CODE but is excluded from WRITE_COUNT. Hardware CLR sets LAST_CODE to active clearcode without incrementing sample writes.
