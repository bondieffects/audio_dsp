-- Simple I2S Pass-Through System (No PLL for Testing)
-- Top-level entity for Cyclone IV FPGA
-- Author: Group 10: Jon Ashley, Alix Guo, Finn Harvey
-- Device: EP4CE6E22C8

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity audio_dsp_top_no_pll is
    port (
        -- System clock (50MHz)
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;

        -- I2S Interface to WM8731 CODEC
        i2s_mclk  : out std_logic;
        i2s_bclk  : out std_logic;
        i2s_ws    : out std_logic;
        i2s_din   : in  std_logic;
        i2s_dout  : out std_logic;

        -- Debug/Status LEDs
        led       : out std_logic_vector(3 downto 0);

        -- Test points for debugging
        test_point_1 : out std_logic;
        test_point_2 : out std_logic
    );
end entity audio_dsp_top_no_pll;

architecture rtl of audio_dsp_top_no_pll is

    component i2s is
        port (
            i2s_mclk : in std_logic;
            reset_n : in std_logic;
            i2s_bclk : out std_logic;
            i2s_ws : out std_logic;
            i2s_dac : out std_logic;
            i2s_adc : in std_logic;
            audio_out_left : in std_logic_vector(15 downto 0);
            audio_out_right : in std_logic_vector(15 downto 0);
            audio_out_valid : in std_logic;
            sample_request : out std_logic;
            audio_in_left : out std_logic_vector(15 downto 0);
            audio_in_right : out std_logic_vector(15 downto 0);
            audio_in_valid : out std_logic
        );
    end component;

    -- Clock signals (no PLL - direct 50MHz)
    signal clk_audio     : std_logic;

    -- Internal I2S clock signals
    signal i2s_bclk_int  : std_logic;
    signal i2s_ws_int    : std_logic;

    -- RX signals (outputs from I2S RX)
    signal rx_audio_left   : std_logic_vector(15 downto 0);
    signal rx_audio_right  : std_logic_vector(15 downto 0);
    signal rx_audio_valid  : std_logic;
    signal sample_request  : std_logic;

    -- Passthrough signals (RX output -> TX input)
    signal passthrough_left  : std_logic_vector(15 downto 0);
    signal passthrough_right : std_logic_vector(15 downto 0);
    signal passthrough_valid : std_logic;

begin

    -- No PLL - use 50MHz directly (not ideal but for testing)
    clk_audio <= clk_50mhz;

    -- PASSTHROUGH LOGIC (RX -> TX) with BOOTSTRAP
    -- Provide initial test data to bootstrap the loopback system
    process(clk_audio, reset_n)
        variable startup_counter : unsigned(15 downto 0) := (others => '0');
        constant BOOTSTRAP_CYCLES : unsigned(15 downto 0) := x"0100"; -- 256 cycles
    begin
        if reset_n = '0' then
            passthrough_left  <= (others => '0');
            passthrough_right <= (others => '0');
            passthrough_valid <= '0';
            startup_counter := (others => '0');
        elsif rising_edge(clk_audio) then
            startup_counter := startup_counter + 1;
            
            if startup_counter < BOOTSTRAP_CYCLES then
                -- Bootstrap phase: provide test data
                passthrough_left  <= x"AA55"; -- Test pattern like working testbench
                passthrough_right <= x"55AA"; -- Test pattern like working testbench  
                passthrough_valid <= '1';
            else
                -- Normal passthrough: RX -> TX
                passthrough_left  <= rx_audio_left;
                passthrough_right <= rx_audio_right;
                passthrough_valid <= rx_audio_valid;
            end if;
        end if;
    end process;

    -- I2S INTERFACE INSTANTIATION
    u_i2s : i2s
        port map (
            i2s_mclk        => clk_audio,
            reset_n         => reset_n,
            i2s_bclk        => i2s_bclk_int,
            i2s_ws          => i2s_ws_int,
            i2s_dac         => i2s_dout,
            i2s_adc         => i2s_din,
            -- TX inputs (data TO codec) - PASSTHROUGH from RX
            audio_out_left  => passthrough_left,   -- RX left -> TX left
            audio_out_right => passthrough_right,  -- RX right -> TX right  
            audio_out_valid => passthrough_valid,  -- RX valid -> TX valid
            sample_request  => sample_request,
            -- RX outputs (data FROM codec)
            audio_in_left   => rx_audio_left,      -- RX left output
            audio_in_right  => rx_audio_right,     -- RX right output
            audio_in_valid  => rx_audio_valid      -- RX valid output
        );

    -- OUTPUT ASSIGNMENTS
    -- I2S clock outputs
    i2s_mclk  <= clk_audio;
    i2s_bclk  <= i2s_bclk_int;
    i2s_ws    <= i2s_ws_int;
    
    -- Status LEDs (inverted for active-low LEDs)
    led(0) <= '0';                       -- Always on (no PLL)
    led(1) <= not rx_audio_valid;        -- RX data activity (inverted)
    led(2) <= not passthrough_valid;     -- TX data activity (inverted)
    led(3) <= not sample_request;        -- Sample request activity (inverted)
    
    -- Test points for debugging
    test_point_1 <= rx_audio_valid;      -- Show RX data valid
    test_point_2 <= passthrough_valid;   -- Show TX data valid

end architecture rtl;