# audio_dsp_top.vhd Code Review

## Findings

- **Major – Reset released before PLL locks (audio_dsp_top.vhd:73-110):** `system_reset` is driven directly from `reset_n`, and `pll_areset` is hard-wired low. This allows the downstream I²S clocking, receiver, and transmitter logic to leave reset as soon as the push-button is released, even if the PLL has not asserted `locked` yet. Any residual jitter or frequency ramp during PLL acquisition can corrupt state machines clocked by `mclk_12288`/`bclk_int`, potentially requiring a manual re-reset after power-up. Gate the system reset with `pll_locked` (or sequence through `pll_areset`) so logic only runs once clocks are stable.
- **Major – LED status indications are inverted (audio_dsp_top.vhd:269-276):** The top-level comment says the LEDs are active-low and describes `led(1)` as "ON = not locked" and `led(2)` as "ON = not ready". With the current assignments (`led(1) <= not pll_locked;` and `led(2) <= not system_reset;`), the LEDs drive low—and therefore illuminate—when the PLL *is* locked and when the system *is* ready. `led(3)` is permanently low because `pll_areset` is tied to `'0'`, so the indicator is always lit. Either the wiring assumptions or the comments are incorrect; as written, the indicators communicate the opposite of the intended fault conditions.
- **Minor – I²S TX handshake is one-sided (audio_dsp_top.vhd:199-234):** `tx_ready` is tied high, so the transmitter captures whatever happens to be on `tx_left/right` at each LR frame boundary. Because `tx_left/right` update on `rx_ready`, this usually works, but the design ignores `sample_request` and denies the transmitter any back-pressure semantics. If future processing inserts additional latency or requires multi-cycle updates, the TX may transmit stale samples. Consider acknowledging `sample_request` and staging new samples in response to it to keep the handshake symmetric.

## Additional Notes

- `display_dot*` use `'1'` to light the decimal point, matching the active-low encoding inside `seven_seg`; the naming is consistent but easy to misread.
- The bitcrusher and decimator share the I²S bit-clock domain, so no CDC issues were spotted, but if you ever clock the effects from `clk_50mhz` the interfaces will need synchronizers.
