# Passive antenna frontend wiring

## U4 orientation and pins

With `U4` upright/readable on the published baseboard drawing, pin 1 is upper
left, pin 2 upper right, odd pins run down the left and even pins down the right.

| Signal | U4 pin | FPGA ball |
|---|---:|---|
| RF_P | 8 | J20 |
| RF_N | 12 | J21 |
| 3.3 V | 38 | -- |
| GND | 37, 39, or 40 | -- |

Verify the 3.3 V and GND pins with a meter before connecting the network.

## Circuit

```text
3.3V (U4-38) -- 1.8k --+-- 1.0k -- GND
                        |
                     VBIAS ~= 1.18V
                        |
                  100nF || 1uF
                        |
                       GND

antenna/coax centre -- 1nF C0G -- 100R --+-- RF_P (U4-8)
                                           |
                                           1k
                                           |
                                         VBIAS

RF_N (U4-12) ----------------------------- VBIAS
coax shield / other dipole arm ----------- GND (U4-37/39/40)
```

Use 1% resistors. Put the 1 nF, 100 ohm, and 1 kohm parts within 1--2 cm of
U4-8. Put both VBIAS capacitors close to U4-12. Keep RF_P/RF_N stubs short.
Do **not** fit a 100 ohm resistor between RF_P and RF_N: external differential
termination is for a real LVDS driver, not this analog-comparator connection.

## Antenna

For the connected telescopic antenna, extend it to roughly 70--80 cm and connect
its feed to the 1 nF input capacitor. Add a 70--80 cm wire from board GND in the
opposite direction as a counterpoise. Keep the board away from the PC chassis and
move/rotate the whip for best reception.
A half-wave dipole (two 72--78 cm arms) is a useful later improvement: coax centre
feeds the R/C input and the shield goes to board GND. Either arrangement is a
simple unbalanced feed, not an optimized balun.

Never use an outdoor/roof/long-wire antenna with this circuit. It has no surge
arrester or clamp diode. Disconnect the antenna during thunderstorms and before
handling the board.

## Pre-power checks

1. Power off: 3.3 V to GND is not shorted; RF_P to RF_N is not shorted.
2. Power on without antenna: VBIAS is about 1.18 V.
3. RF_P and RF_N DC voltage are both about 1.18 V.
4. If any node is below 0.9 V or above 1.4 V, power off and correct wiring.

This frontend is intentionally R/C-only. It cannot provide RF gain, a selective
FM band-pass, lightning protection, or commercial-tuner blocker performance.

The first prototype used 51 ohms from RF_P to VBIAS. Live recordings at 100.1
and 96.8 MHz were statistically indistinguishable threshold noise, and touching
the whip had no useful effect. The 1 kohm revision reduces passive loading while
retaining a defined DC bias; the counterpoise reduces dependence on noisy
board/cable ground as the antenna return.
