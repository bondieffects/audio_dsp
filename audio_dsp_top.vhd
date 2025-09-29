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
    -- RESET LOGIC
    -- ========================================================================
    pll_areset   <= not reset_n;
    system_reset <= reset_n and pll_locked;  -- System ready when PLL locked

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
    -- SIMPLE PASSTHROUGH LOGIC
    -- ========================================================================
    -- Direct passthrough: RX data -> TX data
    process(mclk_12288, system_reset)
    begin
        if system_reset = '0' then
            tx_left  <= (others => '0');
            tx_right <= (others => '0');
            tx_ready <= '0';
        elsif rising_edge(mclk_12288) then
            -- When RX has new data, pass it to TX
            if rx_ready = '1' then
                tx_left  <= rx_left;
                tx_right <= rx_right;
                tx_ready <= '1';
            -- Keep tx_ready high when sample is requested
            elsif sample_request = '1' then
                tx_ready <= '1';
            end if;
        end if;
    end process;

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
    
    -- Status LEDs (active low)
    led(0) <= not heartbeat(23);        -- Heartbeat blink
    led(1) <= not pll_locked;           -- PLL status
    led(2) <= not system_reset;         -- System ready
    led(3) <= not rx_ready;             -- RX data available
    
    -- Test points for debugging
    test_point_1 <= ws_int;             -- Show word select signal
    test_point_2 <= sample_request;     -- Show sample request signal

end architecture rtl;