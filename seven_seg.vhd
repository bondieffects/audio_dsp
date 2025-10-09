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
        data0    : in  std_logic_vector(3 downto 0);
        data1    : in  std_logic_vector(3 downto 0);
        data2    : in  std_logic_vector(3 downto 0);
        data3    : in  std_logic_vector(3 downto 0);
		  
        seg      : out std_logic_vector(7 downto 0);   -- Segments
        seg_sel  : out std_logic_vector(3 downto 0)    -- Digit select
    );
end entity seven_seg;

architecture comp of seven_seg is
    -- signals
    signal display_counter : unsigned(15 downto 0) := (others => '0');
	 signal seg_clk         : unsigned(1 downto 0)  := (others => '0');
    signal digit_0_data    : std_logic_vector(3 downto 0);
    signal digit_1_data    : std_logic_vector(3 downto 0); 
    signal digit_2_data    : std_logic_vector(3 downto 0);
    signal digit_3_data    : std_logic_vector(3 downto 0);
    signal digit_active    : std_logic_vector(3 downto 0);
    signal sel_reg         : unsigned(1 downto 0) := (others => '0'); -- internal selector
begin

    -- Clock divider
	process(seg_mclk, reset_n)
	begin
		 if reset_n = '0' then
			  display_counter <= (others => '0');
			  seg_clk         <= (others => '0');
		 elsif rising_edge(seg_mclk) then
			  if display_counter = 49999 then  -- adjust for your desired refresh
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
            sel_reg <= (others => '0');
        elsif rising_edge(seg_clk(0)) then  -- use LSB of seg_clk as clock
            if sel_reg = "11" then
                sel_reg <= (others => '0');
            else
                sel_reg <= sel_reg + 1;
            end if;

            case sel_reg is
--				    when "10" => digit_active <= "1110"; -- hard code testing
--                when "01" => digit_active <= "1101";
--                when "00" => digit_active <= "1010";
--                when "11" => digit_active <= "1011";
                when "00" => digit_active <= digit_0_data;
                when "01" => digit_active <= digit_1_data;
                when "10" => digit_active <= digit_2_data;
                when "11" => digit_active <= digit_3_data;
                when others => null;
            end case;
        end if;
    end process;

    -- Drive seg_sel (active-low one-hot)
    seg_sel <= "1110" when sel_reg = "00" else
               "1101" when sel_reg = "01" else
               "1011" when sel_reg = "10" else
               "0111";

    -- Placeholder for segments
    with digit_active select
        seg <= 
			  "11000000" when "0000",  -- 0: a b c d e f
			  "11001111" when "0001",  -- 1: e f
			  "10100100" when "0010",  -- 2: a b d e g
			  "10110000" when "0011",  -- 3: a b c d g
			  "10011001" when "0100",  -- 4: b c f g
			  "10010010" when "0101",  -- 5: a c d f g
			  "10000010" when "0110",  -- 6: a c d e f g
			  "11111000" when "0111",  -- 7: a b c e f
			  "10000000" when "1000",  -- 8: a b c d e f g
			  "10010000" when "1001",  -- 9: a b c d f g
			  "10101011" when "1010",  -- n
			  "11100011" when "1011",  -- u
			  "11000111" when "1100",  -- l
			  "10100111" when "1101",  -- c
			  "10001100" when "1110",  -- p
			  "11111111" when others;  -- blank

end architecture comp;