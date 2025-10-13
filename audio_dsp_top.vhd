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
		  
		  -- Seven Segments
		  segment      : out std_logic_vector(7 downto 0);    -- PIN_{128,121,125,129,132,126,124,127}
        seg_select   : out std_logic_vector(3 downto 0);    -- PIN_{133,135,136,137}

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
            data0    : in  character;
            dot0     : in  std_logic;
            data1    : in  character;
            dot1     : in  std_logic;
            data2    : in  character;
            dot2     : in  std_logic;
            data3    : in  character;
            dot3     : in  std_logic;

            seg      : out std_logic_vector(7 downto 0);   -- Segments
            seg_sel  : out std_logic_vector(3 downto 0)    -- Digit select
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
    signal tx_left        : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_right       : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_ready       : std_logic := '0';
    signal crushed_left   : std_logic_vector(15 downto 0) := (others => '0');
    signal crushed_right  : std_logic_vector(15 downto 0) := (others => '0');
    signal decimated_left : std_logic_vector(15 downto 0) := (others => '0');
    signal decimated_right: std_logic_vector(15 downto 0) := (others => '0');

    -- Bitcrusher control
    constant BIT_DEPTH_TARGET : integer range 1 to 16 := 2; -- adjust to taste
    constant DECIMATION_FACTOR : integer range 1 to 64 := 4; -- pick 1 for bypass

    -- Seven-segment display control
    constant DISPLAY_TOGGLE_COUNT : unsigned(25 downto 0) := to_unsigned(50000000 - 1, 26);
    signal display_counter : unsigned(25 downto 0) := (others => '0');
    signal display_page    : std_logic := '0';
    signal display_char0   : character := ' ';
    signal display_char1   : character := ' ';
    signal display_char2   : character := ' ';
    signal display_char3   : character := ' ';
    signal display_dot0    : std_logic := '0';
    signal display_dot1    : std_logic := '0';
    signal display_dot2    : std_logic := '0';
    signal display_dot3    : std_logic := '0';
    
    -- Status
    signal heartbeat    : unsigned(23 downto 0) := (others => '0');

    -- ====================================================================
    -- HELPER FUNCTIONS
    -- ====================================================================
    function digit_char(value : integer) return character is
        variable safe_value : integer := value;
    begin
        if safe_value < 0 then
            safe_value := 0;
        elsif safe_value > 9 then
            safe_value := 9;
        end if;
        return character'val(character'pos('0') + safe_value);
    end function;


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
    -- AUDIO BITCRUSHER LOGIC
    -- ========================================================================
    -- Quantize both channels before transmission
    bitcrusher_left : entity work.bitcrusher_core
        generic map (
            IN_WIDTH    => 16,
            TARGET_BITS => BIT_DEPTH_TARGET
        )
        port map (
            sample_in  => rx_left,
            sample_out => crushed_left
        );

    bitcrusher_right : entity work.bitcrusher_core
        generic map (
            IN_WIDTH    => 16,
            TARGET_BITS => BIT_DEPTH_TARGET
        )
        port map (
            sample_in  => rx_right,
            sample_out => crushed_right
        );

    decimator_left : entity work.sample_rate_decimator
        generic map (
            IN_WIDTH          => 16,
            DECIMATION_FACTOR => DECIMATION_FACTOR
        )
        port map (
            clk          => bclk_int,
            reset_n      => system_reset,
            sample_in    => crushed_left,
            sample_valid => rx_ready,
            sample_out   => decimated_left
        );

    decimator_right : entity work.sample_rate_decimator
        generic map (
            IN_WIDTH          => 16,
            DECIMATION_FACTOR => DECIMATION_FACTOR
        )
        port map (
            clk          => bclk_int,
            reset_n      => system_reset,
            sample_in    => crushed_right,
            sample_valid => rx_ready,
            sample_out   => decimated_right
        );

    -- Capture RX samples and keep them stable for the transmitter
    process(bclk_int, system_reset)
    begin
        if system_reset = '0' then
            tx_left  <= (others => '0');
            tx_right <= (others => '0');
        elsif rising_edge(bclk_int) then
            if rx_ready = '1' then
                tx_left  <= decimated_left;
                tx_right <= decimated_right;
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
    -- SEVEN SEGMENT
    -- ========================================================================		  
    -- Toggle the display page every ~1 second (50 MHz clock)
    process(clk_50mhz, system_reset)
    begin
        if system_reset = '0' then
            display_counter <= (others => '0');
            display_page    <= '0';
        elsif rising_edge(clk_50mhz) then
            if display_counter = DISPLAY_TOGGLE_COUNT then
                display_counter <= (others => '0');
                display_page    <= not display_page;
            else
                display_counter <= display_counter + 1;
            end if;
        end if;
    end process;

    -- Prepare the four-digit payload for the seven-seg driver
    process(display_page)
        variable tens_value : integer;
        variable ones_value : integer;
    begin
        -- defaults
        display_char0 <= ' ';
        display_char1 <= ' ';
        display_char2 <= ' ';
        display_char3 <= ' ';
        display_dot0  <= '0';
        display_dot1  <= '0';
        display_dot2  <= '0';
        display_dot3  <= '0';

        if display_page = '0' then
            tens_value := BIT_DEPTH_TARGET / 10;
            ones_value := BIT_DEPTH_TARGET mod 10;

            display_char0 <= 'B';
            display_char1 <= 'd';
            display_dot1  <= '1';
            if BIT_DEPTH_TARGET >= 10 then
                display_char2 <= digit_char(tens_value);
            else
                display_char2 <= ' ';
            end if;
            display_char3 <= digit_char(ones_value);
        else
            tens_value := DECIMATION_FACTOR / 10;
            ones_value := DECIMATION_FACTOR mod 10;

            display_char0 <= 'S';
            display_char1 <= 'd';
            display_dot1  <= '1';
            if DECIMATION_FACTOR >= 10 then
                display_char2 <= digit_char(tens_value);
            else
                display_char2 <= ' ';
            end if;
            display_char3 <= digit_char(ones_value);
        end if;
    end process;

    u_seven_seg : seven_seg
        port map (
            seg_mclk => clk_50mhz,
          reset_n  => system_reset,
            data0    => display_char0,
            dot0     => display_dot0,
            data1    => display_char1,
            dot1     => display_dot1,
            data2    => display_char2,
            dot2     => display_dot2,
            data3    => display_char3,
            dot3     => display_dot3,
          seg      => segment,
          seg_sel  => seg_select
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
