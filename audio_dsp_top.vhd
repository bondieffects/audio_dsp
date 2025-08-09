-- Real-time Audio DSP with Dedicated Bit Crusher
-- Top-level entity for Cyclone IV FPGA
-- Author: Group 10
-- Device: EP4CE6E22C8N

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity audio_dsp_top is
    port (
        -- System clock (50MHz)
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;
        
        -- I2S Interface to WM8731 CODEC
        i2s_bclk  : out std_logic;  -- Bit clock (3.072MHz)
        i2s_lrclk : out std_logic;  -- Left/Right clock (48kHz)
        i2s_din   : in  std_logic;  -- Data from CODEC ADC
        i2s_dout  : out std_logic;  -- Data to CODEC DAC
        
        -- MIDI Interface from Arduino
        midi_rx   : in  std_logic;  -- MIDI data at 31250 baud
        
        -- Debug/Status LEDs
        led       : out std_logic_vector(3 downto 0);
        
        -- Test points for debugging
        test_point_1 : out std_logic;
        test_point_2 : out std_logic
    );
end entity audio_dsp_top;

architecture rtl of audio_dsp_top is
    
    -- Clock signals
    signal clk_audio     : std_logic;  -- Audio clock domain (12.288MHz)
    signal i2s_bclk_int  : std_logic;  -- Internal BCLK
    signal i2s_lrclk_int : std_logic;  -- Internal LRCLK
    signal pll_locked    : std_logic;  -- PLL lock indicator
    
    -- Audio data signals
    signal audio_left_in   : std_logic_vector(15 downto 0);
    signal audio_right_in  : std_logic_vector(15 downto 0);
    signal audio_valid_in  : std_logic;
    
    -- Bit crusher signals
    signal crushed_left_out  : std_logic_vector(15 downto 0);
    signal crushed_right_out : std_logic_vector(15 downto 0);
    signal crushed_valid_out : std_logic;
    
    -- Volume controlled output
    signal audio_left_out  : std_logic_vector(15 downto 0);
    signal audio_right_out : std_logic_vector(15 downto 0);
    
    -- MIDI interface signals
    signal midi_data       : std_logic_vector(7 downto 0);
    signal midi_valid      : std_logic;
    signal midi_error      : std_logic;
    
    -- DSP control signals from MIDI
    signal bitcrush_depth  : std_logic_vector(3 downto 0);
    signal sample_decimate : std_logic_vector(3 downto 0);
    signal master_volume   : std_logic_vector(7 downto 0);
    signal param_updated   : std_logic;
    signal midi_channel    : std_logic_vector(3 downto 0);
    
    -- Bit crusher control mapping
    signal crusher_bit_depth : std_logic_vector(3 downto 0);
    signal crusher_decimation : std_logic_vector(3 downto 0);
    signal crusher_mix_level  : std_logic_vector(7 downto 0);
    
    -- Component declarations
    component i2s_clock_gen is
        port (
            clk_50mhz    : in  std_logic;
            reset_n      : in  std_logic;
            clk_audio    : out std_logic;
            i2s_bclk     : out std_logic;
            i2s_lrclk    : out std_logic;
            pll_locked   : out std_logic
        );
    end component;
    
    component i2s_interface is
        port (
            clk_audio      : in  std_logic;
            reset_n        : in  std_logic;
            i2s_bclk       : in  std_logic;
            i2s_lrclk      : in  std_logic;
            i2s_din        : in  std_logic;
            i2s_dout       : out std_logic;
            audio_left_in  : out std_logic_vector(15 downto 0);
            audio_right_in : out std_logic_vector(15 downto 0);
            audio_left_out : in  std_logic_vector(15 downto 0);
            audio_right_out: in  std_logic_vector(15 downto 0);
            audio_valid    : out std_logic
        );
    end component;
    
    component midi_uart_rx is
        port (
            clk         : in  std_logic;
            reset_n     : in  std_logic;
            midi_rx     : in  std_logic;
            data_out    : out std_logic_vector(7 downto 0);
            data_valid  : out std_logic;
            error       : out std_logic
        );
    end component;
    
    component midi_parser is
        port (
            clk              : in  std_logic;
            reset_n          : in  std_logic;
            midi_data        : in  std_logic_vector(7 downto 0);
            midi_valid       : in  std_logic;
            bitcrush_depth   : out std_logic_vector(3 downto 0);
            sample_decimate  : out std_logic_vector(3 downto 0);
            master_volume    : out std_logic_vector(7 downto 0);
            param_updated    : out std_logic;
            midi_channel     : out std_logic_vector(3 downto 0)
        );
    end component;
    
    component bit_crusher is
        port (
            clk             : in  std_logic;
            reset_n         : in  std_logic;
            audio_in_left   : in  std_logic_vector(15 downto 0);
            audio_in_right  : in  std_logic_vector(15 downto 0);
            audio_valid_in  : in  std_logic;
            bit_depth       : in  std_logic_vector(3 downto 0);
            decimation      : in  std_logic_vector(3 downto 0);
            mix_level       : in  std_logic_vector(7 downto 0);
            audio_out_left  : out std_logic_vector(15 downto 0);
            audio_out_right : out std_logic_vector(15 downto 0);
            audio_valid_out : out std_logic
        );
    end component;
    
begin
    
    -- Instantiate I2S clock generator
    u_i2s_clocks : i2s_clock_gen
        port map (
            clk_50mhz  => clk_50mhz,
            reset_n    => reset_n,
            clk_audio  => clk_audio,
            i2s_bclk   => i2s_bclk_int,
            i2s_lrclk  => i2s_lrclk_int,
            pll_locked => pll_locked
        );
    
    -- Instantiate I2S interface
    u_i2s_interface : i2s_interface
        port map (
            clk_audio       => clk_audio,
            reset_n         => reset_n,
            i2s_bclk        => i2s_bclk_int,
            i2s_lrclk       => i2s_lrclk_int,
            i2s_din         => i2s_din,
            i2s_dout        => i2s_dout,
            audio_left_in   => audio_left_in,
            audio_right_in  => audio_right_in,
            audio_left_out  => audio_left_out,
            audio_right_out => audio_right_out,
            audio_valid     => audio_valid_in
        );
    
    -- Instantiate MIDI UART receiver
    u_midi_uart : midi_uart_rx
        port map (
            clk        => clk_50mhz,
            reset_n    => reset_n,
            midi_rx    => midi_rx,
            data_out   => midi_data,
            data_valid => midi_valid,
            error      => midi_error
        );
    
    -- Instantiate MIDI parser
    u_midi_parser : midi_parser
        port map (
            clk             => clk_50mhz,
            reset_n         => reset_n,
            midi_data       => midi_data,
            midi_valid      => midi_valid,
            bitcrush_depth  => bitcrush_depth,
            sample_decimate => sample_decimate,
            master_volume   => master_volume,
            param_updated   => param_updated,
            midi_channel    => midi_channel
        );
    
    -- Map MIDI parameters to bit crusher controls
    parameter_mapping : process(clk_audio, reset_n)
    begin
        if reset_n = '0' then
            crusher_bit_depth <= x"F";    -- No crushing (16-bit)
            crusher_decimation <= x"0";   -- No decimation
            crusher_mix_level <= x"FF";   -- Full wet (100% effect)
            
        elsif rising_edge(clk_audio) then
            -- Bit depth: MIDI range 0-15 maps directly to crusher range 0-15
            -- where 0 = 1-bit crushing, 15 = 16-bit (no crushing)
            crusher_bit_depth <= bitcrush_depth;
            
            -- Decimation: MIDI range 0-15 maps directly to crusher range 0-15
            crusher_decimation <= sample_decimate;
            
            -- Mix level: Always 100% wet for bit crusher
            -- Volume control is applied after bit crushing
            crusher_mix_level <= x"FF";
        end if;
    end process;
    
    -- Instantiate bit crusher
    u_bit_crusher : bit_crusher
        port map (
            clk             => clk_audio,
            reset_n         => reset_n,
            audio_in_left   => audio_left_in,
            audio_in_right  => audio_right_in,
            audio_valid_in  => audio_valid_in,
            bit_depth       => crusher_bit_depth,
            decimation      => crusher_decimation,
            mix_level       => crusher_mix_level,
            audio_out_left  => crushed_left_out,
            audio_out_right => crushed_right_out,
            audio_valid_out => crushed_valid_out
        );
    
    -- Master volume control (applied after bit crushing)
    volume_control : process(clk_audio, reset_n)
        variable left_temp  : signed(31 downto 0);
        variable right_temp : signed(31 downto 0);
        variable volume_mult : unsigned(7 downto 0);
    begin
        if reset_n = '0' then
            audio_left_out <= (others => '0');
            audio_right_out <= (others => '0');
            
        elsif rising_edge(clk_audio) then
            if crushed_valid_out = '1' then
                volume_mult := unsigned(master_volume);
                
                -- Apply volume scaling
                left_temp := signed(crushed_left_out) * signed('0' & volume_mult);
                right_temp := signed(crushed_right_out) * signed('0' & volume_mult);
                
                -- Scale back down (divide by 128 to maintain roughly same amplitude)
                left_temp := shift_right(left_temp, 7);
                right_temp := shift_right(right_temp, 7);
                
                -- Clamp to 16-bit range with saturation
                if left_temp > 32767 then
                    audio_left_out <= std_logic_vector(to_signed(32767, 16));
                elsif left_temp < -32768 then
                    audio_left_out <= std_logic_vector(to_signed(-32768, 16));
                else
                    audio_left_out <= std_logic_vector(resize(left_temp, 16));
                end if;
                
                if right_temp > 32767 then
                    audio_right_out <= std_logic_vector(to_signed(32767, 16));
                elsif right_temp < -32768 then
                    audio_right_out <= std_logic_vector(to_signed(-32768, 16));
                else
                    audio_right_out <= std_logic_vector(resize(right_temp, 16));
                end if;
            end if;
        end if;
    end process;
    
    -- Connect I2S clocks to outputs
    i2s_bclk  <= i2s_bclk_int;
    i2s_lrclk <= i2s_lrclk_int;
    
    -- Status LEDs
    led(0) <= pll_locked;           -- PLL lock status
    led(1) <= audio_valid_in;       -- Audio input valid
    led(2) <= param_updated;        -- MIDI parameter update
    led(3) <= midi_error;           -- MIDI error indicator
    
    -- Test points for debugging
    test_point_1 <= i2s_bclk_int;
    test_point_2 <= crushed_valid_out;  -- Bit crusher output valid
    
end architecture rtl;