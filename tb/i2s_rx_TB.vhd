-- i2s_rx_TB.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity i2s_rx_TB is end i2s_rx_TB;

architecture sim of i2s_rx_TB is
  -- ====== I2S params ======
  constant WORD_BITS        : natural := 16;                -- 16 bits per audio word
  constant BCLK_PERIOD      : time    := 640 ns;            -- 1.5625MHz
  constant HALF_BCLK        : time    := BCLK_PERIOD/2;

  -- Test words
  constant LEFT_WORD  : std_logic_vector(15 downto 0) := x"DEAD";
  constant RIGHT_WORD : std_logic_vector(15 downto 0) := x"BEEF";

  -- Delays
  constant RESET_DELAY : time := 200 ns;

  -- Signal declarations for I2S interface
  signal i2s_bclk   : std_logic := '0';
  signal i2s_ws     : std_logic := '0';
  signal reset_n    : std_logic := '0';
  signal i2s_sdata  : std_logic := '0';
  signal audio_left : std_logic_vector(15 downto 0);
  signal audio_right: std_logic_vector(15 downto 0);
  signal rx_ready: std_logic;

begin
  -- DUT
  uut: entity work.i2s_rx
    port map (
      i2s_bclk   => i2s_bclk,
      i2s_ws     => i2s_ws,
      reset_n    => reset_n,
      i2s_sdata  => i2s_sdata,
      audio_left => audio_left,
      audio_right=> audio_right,
      rx_ready=> rx_ready
    );

    -- Free-running 1.5625 MHz bit clock
    i2s_bclk_proc : process
    begin
        loop
            i2s_bclk <= '0';
            wait for HALF_BCLK;
            i2s_bclk <= '1';
            wait for HALF_BCLK;
        end loop;
    end process;

    -- Reset stimulus process
    reset_proc : process
    begin
        reset_n <= '0';
        wait for RESET_DELAY;
        reset_n <= '1';
        wait;                     -- hold forever
    end process;

    -- Philips I2S Protocol:
    --      WS (Word Select): 0 = Left channel, 1 = Right channel
    --      BCLK (Bit Clock): Data changes on falling edge, sampled on rising edge
    --      Timing: Data transmission starts one BCLK period after WS change (I2S protocol requirement)
    --      Data Format: MSB first, 16 bits per channel
    i2s_stimulus : process
    begin
        -- Initialize
        i2s_ws <= '0';      -- Initialise to left channel
        i2s_sdata <= '0';

        -- Wait for reset
        wait until reset_n = '1';
        wait for RESET_DELAY;

        -- -- UM11732 §6.1 “Data format”:
        -- “Data is valid on the rising edge of SCK; the transmitter changes the data on the falling edge.”
        wait until falling_edge(i2s_bclk);

        loop
          -- UM11732 §5.3 “Word select line WS”:
          -- “WS is low during a left-channel word and high during a right-channel word.”

            -- LEFT CHANNEL
            i2s_ws <= '0';

            -- UM11732 §6.1 “Data format”:
            -- “WS changes one clock period before the MSB is transmitted.”
            wait until falling_edge(i2s_bclk);     -- One BCLK delay

            -- UM11732 §6.1 “Data format”:
            -- “The MSB of the left word is transmitted one clock period after WS goes low.”
            for i in 15 downto 0 loop               -- Send 16 bits MSB first
                i2s_sdata <= LEFT_WORD(i);
                wait until falling_edge(i2s_bclk);
            end loop;

            -- RIGHT CHANNEL
            i2s_ws <= '1';
            wait until falling_edge(i2s_bclk);     -- One BCLK delay

            for i in 15 downto 0 loop               -- Send 16 bits MSB first
                i2s_sdata <= RIGHT_WORD(i);
                wait until falling_edge(i2s_bclk);
            end loop;
        end loop;
    end process;

  -- Check for valid data
  -- rx_ready pulses high when RX completes both left and right channels
  -- Verify that the captured parallel words match the stimulus.
  -- from vhdl_testbenches.pdf, p. 14
  checker : process
    variable sample_count : integer := 0;
  begin
    loop
      wait until rising_edge(rx_ready); -- your RX pulses this after RIGHT completes
      sample_count := sample_count + 1;

      assert audio_left  = LEFT_WORD
        report "Sample " & integer'image(sample_count) & " LEFT mismatch: got " & 
               integer'image(to_integer(unsigned(audio_left))) & " (expected 57005=0xDEAD)"
        severity error;
      assert audio_right = RIGHT_WORD
        report "Sample " & integer'image(sample_count) & " RIGHT mismatch: got " &
               integer'image(to_integer(unsigned(audio_right))) & " (expected 48879=0xBEEF)"
        severity error;

      if sample_count >= 5 then
        report "Successfully verified " & integer'image(sample_count) & " samples" severity note;
        exit; -- Stop checking after 5 samples
      end if;
    end loop;
    wait; -- Process ends cleanly
  end process;

  -- End-of-sim timeout, does not stop continuous processes (clocks) but does stop sequential processes
  stopper : process
  begin
    wait for 200 * BCLK_PERIOD;
    report "TB finished" severity failure;  -- not actually a failure, but immediately stops sim
                                            -- from vhdl_testbenches.pdf, p. 14
  end process;
end architecture;
