-- Real-time Audio Digital Signal Processor with MIDI Control
-- Top-level entity for Cyclone IV FPGA
-- Author: Group 10: Jon Ashley, Alix Guo, Finn Harvey
-- Device: EP4CE6E22C8

-- Libraries
-- "IEEE defines the base set of functionality for VHDL in the standard package." p. 143 LaMeres
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- "The entity is where the inputs and outputs of the system are declared." p.164 LaMeres
entity audio_dsp_top is
    -- "A port is an input or output to a system that is declared in the entity" p.164 LaMeres
    port (

    );
end entity audio_dsp_top;

-- "The architecture is where the behavior of the system is described." p. 164 LaMeres
-- "The architecture is where the majority of the design work is conducted" p. 147 LaMeres
-- Syntax:
--      architecture <architecture_name> of <entity associated with> is
--
architecture rtl of audio_dsp_top is

    -- 1. user-defined enumerated type declarations (optional)
    --      none

    -- 2. signal declarations
    --      "A signal is an internal connection within the system that is declared
    --      in the architecture. A signal is not visible outside of the system." p. 164 LaMeres

    -- 3. Constant Declarations (optional)
    --      "Useful for representing a quantity that will be used multiple times in the architecture" p. 148 LaMeres
    --      Syntax: constant constant_name : <type> := <value>;

    -- 4. Component Declarations (optional)
    --      "A [component is a] VHDL subsystem that is instantiated within a higher level system" p. 149 LaMeres
    --      Similar to an object in software programming
    

begin
    -- Behavioral description of the system goes here

    -- Instantiate the components
    -- Syntax:
    --      instance_name : <component name>
    --      port map (<port connections>);



    -- Processes
    -- "To model sequential logic, an HDL needs to be able to trigger signal assignments based
    --  on a triggering event. This is accomplished in VHDL using a process." p. 298 LaMeres
    -- A process is most similar to an ISR in traditional embedded programming.
    -- Unlike ISRs, multiple processes can run concurrently in VHDL.
    -- Syntax:
    --      process (<sensitivity list>)
    --      begin
    --          <sequential statements>
    --      end process;

end architecture rtl;