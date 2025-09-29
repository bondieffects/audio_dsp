In my i2s_tx_TB, I was sampling on the falling edge, but “Subsequent bits appear on following falling edges”. I²S receivers must latch on the rising edge.

The TB for the RX acts like the TX and the TB for the TX acts like the RX.

In my i2s_tx implementation I had the following issues:
1. Missing One BCLK Delay: In the I2S protocol, the first bit of data should appear one BCLK cycle after the WS transition. Your current implementation doesn't properly handle this delay. When transitioning to LEFT_CHANNEL or RIGHT_CHANNEL, you immediately output the MSB of the shift register.

2. Data Alignment: The testbench expects to sample the first bit one BCLK cycle after the WS change, but your implementation might be outputting the first bit too early or too late.

3. Bit Counter Logic: The bit counter needs to properly account for the one-cycle delay before starting data transmission.

4. Data Latching: Your current implementation continually latches data on every clock edge rather than at specific sample request moments, which could lead to data timing issues.