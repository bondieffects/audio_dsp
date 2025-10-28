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
        test_point_2 : out std_logic; -- PIN_51

        -- MIDI input
        midi_in     : in  std_logic       -- External MIDI RX input


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
    
    -- Audio signals
    signal rx_left      : std_logic_vector(15 downto 0);
    signal rx_right     : std_logic_vector(15 downto 0);
    signal rx_ready     : std_logic;
    signal tx_left        : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_right       : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_ready       : std_logic := '0';

    -- Bitcrusher
    signal crushed_left      : std_logic_vector(15 downto 0) := (others => '0');
    signal crushed_right     : std_logic_vector(15 downto 0) := (others => '0');
    signal decimated_left    : std_logic_vector(15 downto 0) := (others => '0');
    signal decimated_right   : std_logic_vector(15 downto 0) := (others => '0');
    constant BIT_DEPTH_DEFAULT  : integer := 3;
    constant DECIMATION_DEFAULT : integer := 2;
    signal bit_depth_setting    : unsigned(4 downto 0) := to_unsigned(BIT_DEPTH_DEFAULT, 5);
    signal decimation_setting   : unsigned(6 downto 0) := to_unsigned(DECIMATION_DEFAULT, 7);
    signal bit_depth_raw        : unsigned(4 downto 0) := to_unsigned(BIT_DEPTH_DEFAULT, 5);
    signal decimation_raw       : unsigned(6 downto 0) := to_unsigned(DECIMATION_DEFAULT, 7);
    signal bit_depth_bclk       : unsigned(4 downto 0) := to_unsigned(BIT_DEPTH_DEFAULT, 5);
    signal decimation_bclk      : unsigned(6 downto 0) := to_unsigned(DECIMATION_DEFAULT, 7);
    signal midi_activity        : std_logic := '0';

    -- MIDI interface signals
    signal midi_byte   : std_logic_vector(7 downto 0) := (others => '0');
    signal midi_valid  : std_logic := '0';
    signal cc_event_strobe : std_logic := '0';
    signal cc_number_raw   : unsigned(6 downto 0) := (others => '0');
    signal cc_value_raw    : unsigned(6 downto 0) := (others => '0');
    signal pc_event_strobe : std_logic := '0';
    signal pc_number_raw   : unsigned(6 downto 0) := (others => '0');

    signal cc_number_latched : integer range 0 to 127 := 0;
    signal cc_value_latched  : integer range 0 to 127 := 0;
    signal pc_number_latched : integer range 0 to 127 := 0;
    signal cc_number_next    : integer range 0 to 127 := 0;
    signal cc_value_next     : integer range 0 to 127 := 0;
    signal pc_number_next    : integer range 0 to 127 := 0;

    -- Seven-segment display control
    type display_state_t is (
        DISPLAY_BIT_DEPTH,
        DISPLAY_DECIMATION,
        DISPLAY_CC_HEADER,
        DISPLAY_CC_NUMBER,
        DISPLAY_CC_VALUE,
        DISPLAY_PC_HEADER,
        DISPLAY_PC_NUMBER
    );

    constant NORMAL_HOLD_COUNT : unsigned(25 downto 0) := to_unsigned(50000000 - 1, 26);
    constant EVENT_HOLD_COUNT  : unsigned(25 downto 0) := to_unsigned(20000000 - 1, 26);

    signal display_timer   : unsigned(25 downto 0) := NORMAL_HOLD_COUNT;
    signal display_state   : display_state_t := DISPLAY_BIT_DEPTH;
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

    procedure split_digits(value_in : in integer; tens : out integer; ones : out integer) is
        variable clamped_value : integer := value_in;
        variable tens_local    : integer := 0;
    begin
        if clamped_value < 0 then
            clamped_value := 0;
        elsif clamped_value > 99 then
            clamped_value := 99;
        end if;

        for idx in 0 to 9 loop
            exit when clamped_value < 10;
            clamped_value := clamped_value - 10;
            tens_local    := tens_local + 1;
        end loop;

        tens := tens_local;
        ones := clamped_value;
    end procedure;

    procedure format_number(value_in : in integer; hundreds : out character; tens : out character; ones : out character) is
        variable clamped_value  : integer := value_in;
        variable hundreds_value : integer := 0;
        variable tens_value     : integer := 0;
    begin
        if clamped_value < 0 then
            clamped_value := 0;
        elsif clamped_value > 127 then
            clamped_value := 127;
        end if;

        if clamped_value >= 100 then
            hundreds_value := 1;
            clamped_value  := clamped_value - 100;
        end if;

        for idx in 0 to 9 loop
            exit when clamped_value < 10;
            clamped_value := clamped_value - 10;
            tens_value    := tens_value + 1;
        end loop;

        if hundreds_value = 0 then
            hundreds := ' ';
        else
            hundreds := digit_char(hundreds_value);
        end if;

        if (hundreds_value = 0) and (tens_value = 0) then
            tens := ' ';
        else
            tens := digit_char(tens_value);
        end if;

        ones := digit_char(clamped_value);
    end procedure;


begin

    -- ========================================================================
    -- RESET
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
    -- MIDI CONTROL INTERFACE
    -- ========================================================================
    u_midi_rx : entity work.midi_uart_rx
        port map (
            clk        => clk_50mhz,
            reset_n    => system_reset,
            midi_in    => midi_in,
            data_byte  => midi_byte,
            data_valid => midi_valid
        );

    u_midi_parser : entity work.midi_parser
        port map (
            clk              => clk_50mhz,
            reset_n          => system_reset,
            data_byte        => midi_byte,
            data_valid       => midi_valid,
            bit_depth_value  => bit_depth_raw,
            decimation_value => decimation_raw,
            cc_event         => cc_event_strobe,
            cc_number        => cc_number_raw,
            cc_value_raw     => cc_value_raw
        );

    -- Register the MIDI-controlled parameters locally to keep this domain latch-free
    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if system_reset = '0' then
                bit_depth_setting  <= to_unsigned(BIT_DEPTH_DEFAULT, bit_depth_setting'length);
                decimation_setting <= to_unsigned(DECIMATION_DEFAULT, decimation_setting'length);
            else
                bit_depth_setting  <= bit_depth_raw;
                decimation_setting <= decimation_raw;
            end if;
        end if;
    end process;

    -- Cross the MIDI-controlled parameters into the I2S bit clock domain
    process(bclk_int)
    begin
        if rising_edge(bclk_int) then
            if system_reset = '0' then
                bit_depth_bclk  <= to_unsigned(BIT_DEPTH_DEFAULT, bit_depth_bclk'length);
                decimation_bclk <= to_unsigned(DECIMATION_DEFAULT, decimation_bclk'length);
            else
                bit_depth_bclk  <= bit_depth_setting;
                decimation_bclk <= decimation_setting;
            end if;
        end if;
    end process;

    -- Track MIDI traffic so the activity LED does not sit at a constant level
    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if system_reset = '0' then
                midi_activity <= '0';
            elsif midi_valid = '1' then
                midi_activity <= not midi_activity;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- AUDIO BITCRUSHER LOGIC
    -- ========================================================================
    -- Quantize both channels before transmission
    bitcrusher_left : entity work.bitcrusher_dynamic
        generic map (
            IN_WIDTH => 16
        )
        port map (
            sample_in  => rx_left,
            bit_depth  => bit_depth_bclk,
            sample_out => crushed_left
        );

    bitcrusher_right : entity work.bitcrusher_dynamic
        generic map (
            IN_WIDTH => 16
        )
        port map (
            sample_in  => rx_right,
            bit_depth  => bit_depth_bclk,
            sample_out => crushed_right
        );

    decimator_left : entity work.sample_rate_decimator_dynamic
        generic map (
            IN_WIDTH      => 16,
            COUNTER_WIDTH => 6
        )
        port map (
            clk          => bclk_int,
            reset_n      => system_reset,
            sample_in    => crushed_left,
            sample_valid => rx_ready,
            decimation_factor => decimation_bclk,
            sample_out   => decimated_left
        );

    decimator_right : entity work.sample_rate_decimator_dynamic
        generic map (
            IN_WIDTH      => 16,
            COUNTER_WIDTH => 6
        )
        port map (
            clk          => bclk_int,
            reset_n      => system_reset,
            sample_in    => crushed_right,
            sample_valid => rx_ready,
            decimation_factor => decimation_bclk,
            sample_out   => decimated_right
        );

    -- Buffer processed samples for transmission
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
            sample_request => open
        );
		  
    -- ========================================================================
    -- SEVEN SEGMENT
    -- ========================================================================		  
    -- Manage automated page sequencing and event-driven animations
    process(clk_50mhz)
        variable next_state : display_state_t;
        variable next_timer : unsigned(display_timer'range);
    begin
        if rising_edge(clk_50mhz) then
            if system_reset = '0' then
                display_state <= DISPLAY_BIT_DEPTH;
                display_timer <= NORMAL_HOLD_COUNT;
            else
                next_state := display_state;
                next_timer := display_timer;

                if cc_event_strobe = '1' then
                    next_state := DISPLAY_CC_HEADER;
                    next_timer := EVENT_HOLD_COUNT;
                elsif pc_event_strobe = '1' then
                    next_state := DISPLAY_PC_HEADER;
                    next_timer := EVENT_HOLD_COUNT;
                elsif next_timer = 0 then
                    case next_state is
                        when DISPLAY_BIT_DEPTH =>
                            next_state := DISPLAY_DECIMATION;
                            next_timer := NORMAL_HOLD_COUNT;
                        when DISPLAY_DECIMATION =>
                            next_state := DISPLAY_BIT_DEPTH;
                            next_timer := NORMAL_HOLD_COUNT;
                        when DISPLAY_CC_HEADER =>
                            next_state := DISPLAY_CC_NUMBER;
                            next_timer := EVENT_HOLD_COUNT;
                        when DISPLAY_CC_NUMBER =>
                            next_state := DISPLAY_CC_VALUE;
                            next_timer := EVENT_HOLD_COUNT;
                        when DISPLAY_CC_VALUE =>
                            next_state := DISPLAY_BIT_DEPTH;
                            next_timer := NORMAL_HOLD_COUNT;
                        when DISPLAY_PC_HEADER =>
                            next_state := DISPLAY_PC_NUMBER;
                            next_timer := EVENT_HOLD_COUNT;
                        when DISPLAY_PC_NUMBER =>
                            next_state := DISPLAY_BIT_DEPTH;
                            next_timer := NORMAL_HOLD_COUNT;
                    end case;
                else
                    next_timer := next_timer - 1;
                end if;

                display_state <= next_state;
                display_timer <= next_timer;
            end if;
        end if;
    end process;

    -- Next-value preparation for the CC and PC display latches
    cc_number_next <= to_integer(cc_number_raw) when cc_event_strobe = '1' else cc_number_latched;
    cc_value_next  <= to_integer(cc_value_raw)  when cc_event_strobe = '1' else cc_value_latched;
    pc_number_next <= to_integer(pc_number_raw) when pc_event_strobe = '1' else pc_number_latched;

    -- Latch the most recent CC number/value and PC number for display pages
    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if system_reset = '0' then
                cc_number_latched <= 0;
            else
                cc_number_latched <= cc_number_next;
            end if;
        end if;
    end process;

    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if system_reset = '0' then
                cc_value_latched <= 0;
            else
                cc_value_latched <= cc_value_next;
            end if;
        end if;
    end process;

    process(clk_50mhz)
    begin
        if rising_edge(clk_50mhz) then
            if system_reset = '0' then
                pc_number_latched <= 0;
            else
                pc_number_latched <= pc_number_next;
            end if;
        end if;
    end process;

    -- Prepare the four-digit payload for the seven-seg driver
    process(display_state, bit_depth_setting, decimation_setting,
            cc_number_latched, cc_value_latched, pc_number_latched)
        variable value          : integer;
        variable tens_value     : integer;
        variable ones_value     : integer;
        variable hundreds_char  : character;
        variable tens_char      : character;
        variable ones_char      : character;
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

        case display_state is
            when DISPLAY_BIT_DEPTH =>
                value := to_integer(bit_depth_setting);
                split_digits(value, tens_value, ones_value);

                display_char0 <= 'B';
                display_char1 <= 'd';
                display_dot1  <= '1';
                if tens_value > 0 then
                    display_char2 <= digit_char(tens_value);
                else
                    display_char2 <= ' ';
                end if;
                display_char3 <= digit_char(ones_value);

            when DISPLAY_DECIMATION =>
                value := to_integer(decimation_setting);
                split_digits(value, tens_value, ones_value);

                display_char0 <= 'd';
                display_char1 <= 'F';
                display_dot1  <= '1';
                if tens_value > 0 then
                    display_char2 <= digit_char(tens_value);
                else
                    display_char2 <= ' ';
                end if;
                display_char3 <= digit_char(ones_value);

            when DISPLAY_CC_HEADER =>
                display_char0 <= 'C';
                display_char1 <= 'C';

            when DISPLAY_CC_NUMBER =>
                value := cc_number_latched;
                format_number(value, hundreds_char, tens_char, ones_char);

                display_char0 <= 'N';
                display_char1 <= hundreds_char;
                display_char2 <= tens_char;
                display_char3 <= ones_char;

            when DISPLAY_CC_VALUE =>
                value := cc_value_latched;
                format_number(value, hundreds_char, tens_char, ones_char);

                display_char0 <= 'V';
                display_char1 <= hundreds_char;
                display_char2 <= tens_char;
                display_char3 <= ones_char;

            when DISPLAY_PC_HEADER =>
                display_char0 <= 'P';
                display_char1 <= 'C';

            when DISPLAY_PC_NUMBER =>
                value := pc_number_latched;
                format_number(value, hundreds_char, tens_char, ones_char);

                display_char0 <= 'N';
                display_char1 <= hundreds_char;
                display_char2 <= tens_char;
                display_char3 <= ones_char;
        end case;
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
    led(2) <= not rx_ready;             -- Pulses when RX samples arrive
    led(3) <= not midi_activity;        -- Toggles whenever MIDI data is parsed
    
    -- Test points for debugging
    test_point_1 <= ws_int;             -- Show word select signal
    test_point_2 <= rx_ready;           -- Show RX sample availability pulses

end architecture rtl;
