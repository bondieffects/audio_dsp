library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- MIDI Parser
-- ============================================================================
-- Accepts MIDI bytes from midi_uart_rx and extracts Control Change values used
-- to drive the audio processing parameters.
--
-- Supported mapping:
--   Control Change #20 -> Bit depth (maps 0..127 to 1..16)
--   Control Change #21 -> Decimation factor (maps 0..127 to 1..64)
-- ============================================================================
entity midi_parser is
    port (
        clk                : in  std_logic;
        reset_n            : in  std_logic;
        data_byte          : in  std_logic_vector(7 downto 0);
        data_valid         : in  std_logic;
        bit_depth_value    : out unsigned(4 downto 0);
        decimation_value   : out unsigned(6 downto 0)
    );
end entity midi_parser;

architecture rtl of midi_parser is
    type parser_state_t is (WAIT_STATUS, WAIT_DATA1, WAIT_DATA2);
    signal state           : parser_state_t := WAIT_STATUS;
    signal status_byte     : std_logic_vector(7 downto 0) := (others => '0');
    signal controller_byte : std_logic_vector(7 downto 0) := (others => '0');

    signal bit_depth_reg   : unsigned(4 downto 0) := to_unsigned(3, 5);  -- default 3 bits
    signal decimation_reg  : unsigned(6 downto 0) := to_unsigned(2, 7);  -- default factor 2

    constant STATUS_CC_MASK  : std_logic_vector(3 downto 0) := "1011";  -- 0xB for Control Change
    constant CC_BIT_DEPTH    : integer := 20;
    constant CC_DECIMATION   : integer := 21;

    function clamp(val : integer; lo : integer; hi : integer) return integer is
        variable result : integer := val;
    begin
        if result < lo then
            result := lo;
        elsif result > hi then
            result := hi;
        end if;
        return result;
    end function;

    function scale_to_range(val : integer; max_val : integer) return integer is
        -- Map 0..127 to 1..max_val inclusively.
        variable scaled : integer;
    begin
        scaled := ((val * (max_val - 1)) / 127) + 1;
        return clamp(scaled, 1, max_val);
    end function;

begin
    process(clk, reset_n)
        variable data_is_status : boolean;
        variable data_value     : integer;
        variable controller     : integer;
        variable scaled_value   : integer;
    begin
        if reset_n = '0' then
            state           <= WAIT_STATUS;
            status_byte     <= (others => '0');
            controller_byte <= (others => '0');
            bit_depth_reg   <= to_unsigned(3, 5);
            decimation_reg  <= to_unsigned(2, 7);
        elsif rising_edge(clk) then
            if data_valid = '1' then
                data_is_status := (data_byte(7) = '1');

                if data_is_status then
                    if unsigned(data_byte) >= 248 then
                        -- MIDI real-time messages (0xF8-0xFF) are single-byte and
                        -- should not disturb running status. Ignore them.
                        null;
                    else
                        status_byte <= data_byte;
                        state       <= WAIT_DATA1;
                    end if;
                else
                    data_value := to_integer(unsigned(data_byte(6 downto 0)));

                    case state is
                        when WAIT_STATUS =>
                            -- Running status: reuse last status byte if it was Control Change
                            if status_byte(7 downto 4) = STATUS_CC_MASK then
                                controller_byte <= data_byte;
                                state           <= WAIT_DATA2;
                            end if;

                        when WAIT_DATA1 =>
                            controller_byte <= data_byte;
                            state           <= WAIT_DATA2;

                        when WAIT_DATA2 =>
                            controller := to_integer(unsigned(controller_byte(6 downto 0)));

                            if status_byte(7 downto 4) = STATUS_CC_MASK then
                                if controller = CC_BIT_DEPTH then
                                    scaled_value := scale_to_range(data_value, 16);
                                    bit_depth_reg <= to_unsigned(scaled_value, bit_depth_reg'length);
                                elsif controller = CC_DECIMATION then
                                    scaled_value := scale_to_range(data_value, 64);
                                    decimation_reg <= to_unsigned(scaled_value, decimation_reg'length);
                                end if;
                            end if;

                            state <= WAIT_DATA1;  -- Expect next data byte or new status
                    end case;
                end if;
            end if;
        end if;
    end process;

    bit_depth_value  <= bit_depth_reg;
    decimation_value <= decimation_reg;

end architecture rtl;
