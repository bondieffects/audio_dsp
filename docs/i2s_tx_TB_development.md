---
# I2S TX Testbench Development Notes

## Testbench Edge Sampling Issue

In my `i2s_tx_TB`, I was sampling on the falling edge, but **subsequent bits appear on following falling edges**. I²S receivers must latch on the rising edge.

> The TB for the RX acts like the TX and the TB for the TX acts like the RX.

## Issues in `i2s_tx` Implementation

1. **Missing One BCLK Delay**: In the I2S protocol, the first bit of data should appear one BCLK cycle after the WS transition. The current implementation doesn't properly handle this delay. When transitioning to `LEFT_CHANNEL` or `RIGHT_CHANNEL`, the MSB of the shift register is output immediately.
2. **Data Alignment**: The testbench expects to sample the first bit one BCLK cycle after the WS change, but the implementation might be outputting the first bit too early or too late.
3. **Bit Counter Logic**: The bit counter needs to properly account for the one-cycle delay before starting data transmission.
4. **Data Latching**: The current implementation continually latches data on every clock edge rather than at specific sample request moments, which could lead to data timing issues.

---

## What Was Wrong with the I2S Implementation

### Core Issues Identified

The audio passthrough was failing due to several critical issues in the I2S implementation:

#### 1. Flawed RX State Machine Logic
- **Missing Edge Detection**: The original code relied on level checking (`if i2s_ws = '0'` or `if i2s_ws = '1'`) rather than edge detection for state transitions.
- **Unnecessary Sync Logic**: The `sync_ready` flag created an extra waiting state that was never properly satisfied, blocking the reception chain.
- **Premature State Transitions**: The state machine would change states before completing sample reception, causing data loss.

#### 2. Ineffective Clock Generation
- **WS Generation Method**: The original implementation generated WS directly from MCLK (bypassing BCLK edges), creating potential timing issues.
- **No Synchronization**: The clock signals lacked proper synchronization between BCLK edges and WS transitions.
- **Counter Reset Issues**: The counter logic didn't properly align with I2S protocol specifications.

#### 3. Missing Protocol Requirements
- **Edge Transition Logic**: I2S protocol requires detecting specific edges (falling edge for left channel, rising edge for right channel).
- **Frame Completion Detection**: The code wasn't properly detecting the completion of a full stereo frame.
- **Sample Validity Timing**: The `rx_ready` signal wasn't being asserted at the correct time in the audio frame.

#### 4. Signal Flow Problems
- **Channel Desynchronization**: Left and right channels could get out of sync due to improper state transitions.
- **No Robust State Recovery**: If synchronization was lost, the system had no mechanism to reliably resync.

---

## Reference Implementation Advantages

The reference implementation that worked correctly had these key features:

### Proper Edge Detection
```vhdl
ws_falling_edge <= ws_prev and not i2s_ws;
ws_rising_edge  <= not ws_prev and i2s_ws;
```

### BCLK-based WS Generation
```vhdl
if bclk_edge = '1' then  -- Count on BCLK rising edges
   ws_counter <= ws_counter + 1;
end if;
```

### Edge-Triggered State Transitions
```vhdl
if ws_falling_edge = '1' then
   -- WS goes low: start receiving left channel
elsif ws_rising_edge = '1' then
   -- WS goes high: start receiving right channel
end if;
```

### Proper Frame Completion Logic
```vhdl
if bit_counter = "01111" then
   right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
   valid_output <= '1';  -- Both channels received, data is ready
end if;
```

---

## Changes Made

The modifications implemented to fix these issues included:

- Added explicit edge detection for WS in the receiver
- Refactored the state machine to use edge detection for transitions
- Improved the clock generation with proper BCLK edge counting
- Established reliable frame completion detection
- Ensured proper synchronization between clock domains

These changes ensure that the I2S receiver properly captures audio data according to the I2S specification, correctly identifying the start of each channel, capturing the full 16 bits per channel, and asserting the ready signal when a complete stereo frame has been received.

---

## Follow-up Refinements

- `audio_dsp_top.vhd` now holds reset low until `pll_locked` is asserted and re-synchronises it separately into the MCLK and BCLK domains to eliminate start-up glitches.
- `i2s_clocks.vhd` uses a single counter-based divider so BCLK/WS edges are phase-consistent without the extra edge-detection process.
- `i2s_tx.vhd` issues a level-sensitive sample request that remains asserted until the upstream returns `tx_ready='1'`, guaranteeing that fresh audio words are captured even when the producer stalls. The serialiser logic also enforces the mandatory one-BCLK quiet period after each WS change.
- `i2s_rx.vhd` replaces the explicit FSM with a counter-driven shifter; this keeps the left/right tracking straightforward while still presenting a one-cycle aligned `rx_ready` pulse.
- `audio_dsp_top.vhd` now instantiates the shared `i2s` wrapper so clocking, TX, and RX are centralised. The Quartus constraints in `audio_dsp.sdc` were tightened to use realistic I/O delays instead of blanket false paths, letting the timing analyser check the I2S interface properly.

---

## Key Findings (Historical Snapshot)

- **Reset/bring-up is fragile**: `system_reset` in `audio_dsp_top.vhd:112-188` simply mirrors `reset_n`, so the RX/TX cores can start shifting before the PLL locks or before resets are synchronised into the BCLK domain. Gate release with `pll_locked` and register the reset inside each clock domain to remove spurious frames and ease timing closure.
- **Clock generator can be simplified**: `i2s_clocks.vhd:32-102` uses three processes, edge-detectors, and an 8-bit counter even though a single modulo-256 counter can emit both BCLK (bit 2) and WS (bit 8) while guaranteeing WS transitions on a defined BCLK edge. Refactoring removes `bclk_edge`, halves the logic, and makes the one-BCLK WS lead time explicit.
- **TX handshake logic never retries**: In `i2s_tx.vhd:31-107` the request is a one-cycle pulse while the new sample load is dropped when `tx_ready='0'`. Add a registered “pending” flag (or turn `tx_ready` into a ready/valid handshake) so the core keeps requesting until fresh audio is acknowledged. You can also delete the unused `bit_count`, `transmitting`, and `current_data` signals after the rewrite.
- **RX state machine is heavier than needed**: The tri-state FSM in `i2s_rx.vhd:31-153` can be replaced by a 5-bit counter that resets on WS edges and always shifts, which eliminates the IDLE path and redundant register clears. Doing so also gives you a clean slot counter that you can reuse for re-sync detection or sample-valid timing.
- **Timing constraints mask real problems**: `audio_dsp.sdc:24-66` treats PLL, BCLK, and WS clocks as asynchronous and then sets false-paths to every I/O, so Quartus never checks the interface timing. Keep the generated-clock relationship, constrain the I2S outputs with realistic `set_output_delay`, and only mark the truly asynchronous paths (e.g. the push-button reset).
- **Top-level duplication**: `i2s.vhd:39-119` and `audio_dsp_top.vhd` both assemble the same pieces. Consolidating to one wrapper (with generics for passthrough vs. custom processing) makes the hierarchy clearer and reduces the maintenance surface. If software needs `sample_request`, remember it toggles in the BCLK domain—add a synchroniser when you expose it to the 50 MHz fabric.

---

## Next Steps

1. Refactor the clock divider and regenerate constraints to confirm timing stays clean.
2. Rework the TX/RX handshakes around ready/valid semantics and rerun the existing testbenches.
3. Decide on a single top-level wrapper and strip the unused components/signals once the new flow passes simulation.
