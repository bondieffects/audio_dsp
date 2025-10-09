-- ============================================================================
-- SIMPLE I2S PASSTHROUGH - MINIMAL IMPLEMENTATION
-- ============================================================================
-- Simplest possible I2S passthrough for audio data
-- Uses audio_pll IP for master clock generation
-- Target: Cyclone IV EP4CE6E22C8

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity audio_dsp_top is
    port (
        -- System clock (50MHz)
        clk_50mhz : in std_logic;
        reset_n   : in std_logic;   -- Active low reset

        -- I2S Interface to WM8731 CODEC
        i2s_mclk  : out std_logic;  -- Master clock (12.288MHz) - PIN_30
        i2s_bclk  : out std_logic;  -- Bit clock (1.536MHz) - PIN_31
        i2s_ws    : out std_logic;  -- Left/Right clock (48kHz) - PIN_32  
        i2s_din   : in  std_logic;  -- Data from CODEC ADC - PIN_33
        i2s_dout  : out std_logic;  -- Data to CODEC DAC - PIN_34

        -- Status LEDs
        led       : out std_logic_vector(3 downto 0);   -- PIN_84 to 87

        -- Test points for debugging (optional - can be removed)
        test_point_1 : out std_logic; -- PIN_50
        test_point_2 : out std_logic  -- PIN_51
    );
end entity audio_dsp_top;

architecture rtl of audio_dsp_top is

    -- ========================================================================
    -- COMPONENT DECLARATIONS
    -- ========================================================================
    component audio_pll is
        port (
            areset  : in  std_logic := '0';
            inclk0  : in  std_logic := '0';
            c0      : out std_logic;
            locked  : out std_logic
        );
    end component;
    
    component i2s_clocks is
        port (
            i2s_mclk : in  std_logic;
            reset_n  : in  std_logic;
            i2s_bclk : out std_logic;
            i2s_ws   : out std_logic
        );
    end component;
    
    component i2s_rx is
        port (
            i2s_bclk    : in  std_logic;
            i2s_ws      : in  std_logic;
            reset_n     : in  std_logic;
            i2s_sdata   : in  std_logic;
            audio_left  : out std_logic_vector(15 downto 0);
            audio_right : out std_logic_vector(15 downto 0);
            rx_ready    : out std_logic
        );
    end component;
    
    component i2s_tx is
        port (
            i2s_bclk        : in  std_logic;
            i2s_ws          : in  std_logic;
            reset_n         : in  std_logic;
            audio_left      : in  std_logic_vector(15 downto 0);
            audio_right     : in  std_logic_vector(15 downto 0);
            tx_ready        : in  std_logic;
            i2s_sdata       : out std_logic;
            sample_request  : out std_logic
        );
    end component;

    component seven_seg is
        port(
            seg_mclk : in  std_logic;
            reset_n  : in  std_logic;
            data0    : in  std_logic_vector(3 downto 0);
            data1    : in  std_logic_vector(3 downto 0);
            data2    : in  std_logic_vector(3 downto 0);
            data3    : in  std_logic_vector(3 downto 0);
            
            seg      : out std_logic_vector(7 downto 0);   -- Segments
            seg_sel  : out std_logic_vector(3 downto 0)    -- Digit select
        );
    end component

    -- ========================================================================
    -- INTERNAL SIGNALS
    -- ========================================================================
    -- PLL signals
    signal mclk_12288   : std_logic;    -- 12.288MHz from PLL
    signal pll_locked   : std_logic;    -- PLL lock indicator
    signal pll_areset   : std_logic;    -- PLL reset (active high)
    signal system_reset : std_logic;    -- System reset (active low)
    
    -- I2S clocks
    signal bclk_int     : std_logic;
    signal ws_int       : std_logic;
    
    -- Audio data signals
    signal rx_left      : std_logic_vector(15 downto 0);
    signal rx_right     : std_logic_vector(15 downto 0);
    signal rx_ready     : std_logic;
    signal sample_request : std_logic;
    
    -- Passthrough data (RX -> TX)
    signal tx_left      : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_right     : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_ready     : std_logic := '0';
    
    -- Status
    signal heartbeat    : unsigned(23 downto 0) := (others => '0');


begin

    -- ========================================================================
    -- SIMPLIFIED RESET - IGNORE PLL DEPENDENCY  
    -- ========================================================================
    pll_areset   <= '0';                -- Don't reset PLL
    system_reset <= reset_n;            -- Simple: just use reset button

    -- ========================================================================
    -- AUDIO PLL INSTANTIATION  
    -- ========================================================================
    u_audio_pll : audio_pll
        port map (
            areset => pll_areset,
            inclk0 => clk_50mhz,
            c0     => mclk_12288,
            locked => pll_locked
        );

    -- ========================================================================
    -- I2S CLOCK GENERATION MODULE
    -- ========================================================================
    u_i2s_clocks : i2s_clocks
        port map (
            i2s_mclk => mclk_12288,
            reset_n  => system_reset,
            i2s_bclk => bclk_int,
            i2s_ws   => ws_int
        );

    -- ========================================================================
    -- I2S RECEIVER MODULE
    -- ========================================================================
    u_i2s_rx : i2s_rx
        port map (
            i2s_bclk   => bclk_int,
            i2s_ws     => ws_int,
            reset_n    => system_reset,
            i2s_sdata  => i2s_din,
            audio_left => rx_left,
            audio_right=> rx_right,
            rx_ready   => rx_ready
        );

    -- ========================================================================
    -- AUDIO PASSTHROUGH LOGIC
    -- ========================================================================
    -- Capture RX samples and keep them stable for the transmitter
    process(bclk_int, system_reset)
    begin
        if system_reset = '0' then
            tx_left  <= (others => '0');
            tx_right <= (others => '0');
        elsif rising_edge(bclk_int) then
            if rx_ready = '1' then
                tx_left  <= rx_left;
                tx_right <= rx_right;
            end if;
        end if;
    end process;

    -- Always indicate that data is ready (latched samples remain valid)
    tx_ready <= '1';

    -- ========================================================================
    -- I2S TRANSMITTER MODULE
    -- ========================================================================
    u_i2s_tx : i2s_tx
        port map (
            i2s_bclk       => bclk_int,
            i2s_ws         => ws_int,
            reset_n        => system_reset,
            audio_left     => tx_left,
            audio_right    => tx_right,
            tx_ready       => tx_ready,
            i2s_sdata      => i2s_dout,
            sample_request => sample_request
        );



    -- ========================================================================
    -- HEARTBEAT AND STATUS
    -- ========================================================================
    process(mclk_12288, system_reset)
    begin
        if system_reset = '0' then
            heartbeat <= (others => '0');
        elsif rising_edge(mclk_12288) then
            heartbeat <= heartbeat + 1;
        end if;
    end process;

    -- ========================================================================
    -- OUTPUT ASSIGNMENTS
    -- ========================================================================
    -- I2S interface
    i2s_mclk <= mclk_12288;
    i2s_bclk <= bclk_int;
    i2s_ws   <= ws_int;
    
    -- Status LEDs (active low) - DEBUG VERSION
    led(0) <= not heartbeat(23);        -- Heartbeat blink (MCLK/50MHz working)
    led(1) <= not pll_locked;           -- PLL status (ON = not locked)
    led(2) <= not system_reset;         -- System ready (ON = not ready)
    led(3) <= pll_areset;               -- Show PLL reset status (ON = PLL being reset)
    
    -- Test points for debugging
    test_point_1 <= ws_int;             -- Show word select signal
    test_point_2 <= rx_ready;           -- Show RX sample availability pulses

end architecture rtl;