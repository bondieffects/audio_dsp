In my i2s_tx_TB, I was sampling on the falling edge, but “Subsequent bits appear on following falling edges”. I²S receivers must latch on the rising edge.

The TB for the RX acts like the TX and the TB for the TX acts like the RX.

In my i2s_tx implementation I had the following issues:
1. Missing One BCLK Delay: In the I2S protocol, the first bit of data should appear one BCLK cycle after the WS transition. Your current implementation doesn't properly handle this delay. When transitioning to LEFT_CHANNEL or RIGHT_CHANNEL, you immediately output the MSB of the shift register.

2. Data Alignment: The testbench expects to sample the first bit one BCLK cycle after the WS change, but your implementation might be outputting the first bit too early or too late.

3. Bit Counter Logic: The bit counter needs to properly account for the one-cycle delay before starting data transmission.

4. Data Latching: Your current implementation continually latches data on every clock edge rather than at specific sample request moments, which could lead to data timing issues.

What Was Wrong with the I2S Implementation
Core Issues Identified
The audio passthrough was failing due to several critical issues in the I2S implementation. Here's a detailed breakdown of what was wrong:

1. Flawed RX State Machine Logic
Missing Edge Detection: The original code relied on level checking (if i2s_ws = '0' or if i2s_ws = '1') rather than edge detection for state transitions.
Unnecessary Sync Logic: The sync_ready flag created an extra waiting state that was never properly satisfied, blocking the reception chain.
Premature State Transitions: The state machine would change states before completing sample reception, causing data loss.
2. Ineffective Clock Generation
WS Generation Method: The original implementation generated WS directly from MCLK (bypassing BCLK edges), creating potential timing issues.
No Synchronization: The clock signals lacked proper synchronization between BCLK edges and WS transitions.
Counter Reset Issues: The counter logic didn't properly align with I2S protocol specifications.
3. Missing Protocol Requirements
Edge Transition Logic: I2S protocol requires detecting specific edges (falling edge for left channel, rising edge for right channel).
Frame Completion Detection: The code wasn't properly detecting the completion of a full stereo frame.
Sample Validity Timing: The rx_ready signal wasn't being asserted at the correct time in the audio frame.
4. Signal Flow Problems
Channel Desynchronization: Left and right channels could get out of sync due to improper state transitions.
No Robust State Recovery: If synchronization was lost, the system had no mechanism to reliably resync.
The Reference Implementation's Advantages
The reference implementation that worked correctly had these key features:

Proper Edge Detection:
ws_falling_edge <= ws_prev and not i2s_ws;
ws_rising_edge <= not ws_prev and i2s_ws;

BCLK-based WS Generation:
if bclk_edge = '1' then  -- Count on BCLK rising edges
   ws_counter <= ws_counter + 1;
end if;

Edge-Triggered State Transitions:
if ws_falling_edge = '1' then
   -- WS goes low: start receiving left channel
elsif ws_rising_edge = '1' then
   -- WS goes high: start receiving right channel
end if;

Proper Frame Completion Logic:
if bit_counter = "01111" then
   right_sample <= rx_shift_register(14 downto 0) & i2s_sdata;
   valid_output <= '1';  -- Both channels received, data is ready
end if;

The Changes Made
The modifications implemented to fix these issues included:

Added explicit edge detection for WS in the receiver
Refactored the state machine to use edge detection for transitions
Improved the clock generation with proper BCLK edge counting
Established reliable frame completion detection
Ensured proper synchronization between clock domains
These changes ensure that the I2S receiver properly captures audio data according to the I2S specification, correctly identifying the start of each channel, capturing the full 16 bits per channel, and asserting the ready signal when a complete stereo frame has been received.