library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- ============================================================================
-- 7 Segment controller
-- ============================================================================

entity seven_seg is
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
        seg      : out std_logic_vector(7 downto 0);    -- Segments
        seg_sel  : out std_logic_vector(3 downto 0)     -- Digit select
    );
end entity seven_seg;

architecture comp of seven_seg is
    -- signals
    signal display_counter : unsigned(15 downto 0) := (others => '0');
    signal seg_clk         : unsigned(1 downto 0)  := (others => '0');
    signal sel_reg         : unsigned(1 downto 0) := (others => '0');
    signal current_char    : character := ' ';
    signal current_dp      : std_logic := '0';

    function encode_char(c : character) return std_logic_vector is
        variable pattern : std_logic_vector(7 downto 0) := (others => '1');
    begin
        case c is
            when '0' => pattern := "11000000";  -- a b c d e f
            when '1' => pattern := "11111001";  -- 1: e f
            when '2' => pattern := "10100100";  -- 2: a b d e g
            when '3' => pattern := "10110000";  -- 3: a b c d g
            when '4' => pattern := "10011001";  -- 4: b c f g
            when '5' => pattern := "10010010";  -- 5: a c d f g
            when '6' => pattern := "10000010";  -- 6: a c d e f g
            when '7' => pattern := "11111000";  -- 7: a b c e f
            when '8' => pattern := "10000000";  -- 8: a b c d e f g
            when '9' => pattern := "10010000";  -- 9: a b c d f g
            when 'A' | 'a' => pattern := "10001000";
            when 'B' | 'b' => pattern := "10000011";
            when 'C' | 'c' => pattern := "11000110";
            when 'D' | 'd' => pattern := "10100001";
            when 'E' | 'e' => pattern := "10000110";
            when 'F' | 'f' => pattern := "10001110";
            when 'G' | 'g' => pattern := "10000010";
            when 'H' | 'h' => pattern := "10001001";
            when 'I' | 'i' => pattern := "11111001";
            when 'J' | 'j' => pattern := "11100001";
            when 'K' | 'k' => pattern := "10001010";
            when 'L' | 'l' => pattern := "11000111";
            when 'M' | 'm' => pattern := "10101010";
            when 'N' | 'n' => pattern := "10101011";
            when 'O' | 'o' => pattern := "11000000";
            when 'P' | 'p' => pattern := "10001100";
            when 'Q' | 'q' => pattern := "10011000";
            when 'R' | 'r' => pattern := "10101111";
            when 'S' | 's' => pattern := "10010010";
            when 'T' | 't' => pattern := "10000111";
            when 'U' | 'u' => pattern := "11000001";
            when 'V' | 'v' => pattern := "11000001";
            when 'W' | 'w' => pattern := "11101001";
            when 'X' | 'x' => pattern := "10001001";
            when 'Y' | 'y' => pattern := "10010001";
            when 'Z' | 'z' => pattern := "10100100";
            when '-'        => pattern := "10111111";
            when '_'        => pattern := "11110111";
            when '='        => pattern := "10110111";
            when ' '        => pattern := "11111111";
            when '.'        => pattern := "01111111";
            when others     => pattern := "11111111";   -- blank
        end case;
        return pattern;
    end function;

    function encode_with_dp(c : character; dp : std_logic) return std_logic_vector is
        variable result : std_logic_vector(7 downto 0);
    begin
        result := encode_char(c);
        if dp = '1' then
            result(7) := '0';
        else
            result(7) := '1';
        end if;
        return result;
    end function;

begin

    -- Clock divider
    process(seg_mclk, reset_n)
    begin
        if reset_n = '0' then
            display_counter <= (others => '0');
            seg_clk         <= (others => '0');
        elsif rising_edge(seg_mclk) then
            if display_counter = 49999 then
                seg_clk         <= seg_clk + 1;
                display_counter <= (others => '0');
            else
                display_counter <= display_counter + 1;
            end if;
        end if;
    end process;

    -- Digit select logic
    process(seg_clk, reset_n)
    begin
        if reset_n = '0' then
            sel_reg      <= (others => '0');
            current_char <= ' ';
            current_dp   <= '0';
        elsif rising_edge(seg_clk(0)) then
            if sel_reg = "11" then
                sel_reg <= (others => '0');
            else
                sel_reg <= sel_reg + 1;
            end if;

            case sel_reg is
                when "00" =>
                    current_char <= data2;
                    current_dp   <= dot2;
                when "01" =>
                    current_char <= data1;
                    current_dp   <= dot1;
                when "10" =>
                    current_char <= data0;
                    current_dp   <= dot0;
                when "11" =>
                    current_char <= data3;
                    current_dp   <= dot3;
                when others => null;
            end case;
        end if;
    end process;

    -- Drive seg_sel (active-low one-hot)
    seg_sel <= "1110" when sel_reg = "00" else
               "1101" when sel_reg = "01" else
               "1011" when sel_reg = "10" else
               "0111";

    seg <= encode_with_dp(current_char, current_dp);

end architecture comp;