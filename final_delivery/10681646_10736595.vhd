library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity project_reti_logiche is
 port (
 i_clk : in std_logic;
 i_rst : in std_logic;
 i_start : in std_logic;
 i_add : in std_logic_vector(15 downto 0);
 i_k : in std_logic_vector(9 downto 0);
 o_done : out std_logic;
 o_mem_addr : out std_logic_vector(15 downto 0);
 i_mem_data : in std_logic_vector(7 downto 0);
 o_mem_data : out std_logic_vector(7 downto 0);
 o_mem_we : out std_logic;
 o_mem_en : out std_logic
 );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is
    type state is 
            (
                S_IDLE,              -- resets values and waits for start signal
                S_SETUP,             -- sets up values for a new execution 
                S_READMEM_WAIT,      -- waits for memory to be ready to be read
                S_READMEM,           -- reads from memory content of 'i_mem_data' and stores it in value    
                S_READMEM_CHOICE,    -- chooses next step based on which value is read and if it's the first value read in the sequence                
                S_1,                 -- state reached if value /= 0    
                S_2,                 -- state reached if value = 0 and jump /= 0
                S_3,                 -- state reached if value = 0 and (jump = 0 or state_prev = S_3)
                S_21,                -- state reached after S_2 -> S_WRITEMEM -> S_WRITEMEM_CHOICE because if value == 0 and it's not the 
                                     -- first to be read in the sequence we have to write twice, first the value and then the credibility  
                S_WRITEMEM,          -- waits for memory to be written 
                S_WRITEMEM_CHOICE,   -- chooses the next step after writing memory based on state_prev 
                S_DONE               -- waits for i_start to go to 0 to then return to idle
             );
             
    signal state_curr, state_prev : state;
    signal trust : integer range 0 to 31;                  -- expresses the 'credibility' of the previous value in the sequence 
    signal jump  : integer range 0 to 65535;               -- used as index  
    signal k  : integer range 0 to 1023;                  -- used to contain i_k as integer
    signal start_add : integer range 0 to 65535;           -- used to contain i_add as integer
    signal value, last_value : integer range 0 to 255;     


    
begin
    
    process(i_clk, i_rst)
    
    begin
    
        if (i_rst='1') then
            state_curr <= S_IDLE;
        elsif rising_edge(i_clk) then
        
            case state_curr is
            
                when S_IDLE =>
                
                    -- reset values and waits for start signal
                    trust <= 0;
                    jump <= 0;
                    start_add <= 0;
                    value <= 0;
                    last_value <= 0;
                    state_prev <= S_IDLE;
                    k <= 0;
                    o_done <= '0';
                    o_mem_addr <= (others => '0');
                    o_mem_data <= (others => '0');
                    o_mem_en <= '0';
                    o_mem_we <= '0';
                    jump <= 0;
                    if (i_start = '1') then
                        k <= to_integer(unsigned(i_k));
                        state_curr <= S_SETUP;
                    end if;
                    
                    
                when S_SETUP =>
                
                    -- sets up values for a new execution
                    start_add <= to_integer(unsigned(i_add));
                    o_mem_addr <= i_add;
                    o_mem_en <= '1';
                    
                    if (k > 0) then
                        state_curr <= S_READMEM_WAIT;
                    else
                        o_done <= '1';
                        state_curr <= S_DONE;
                    end if;
                    
                
                when S_READMEM_WAIT =>
                    
                    -- waits for memory to be ready to be read
                    state_curr <= S_READMEM;
                
                    
                    
                when S_READMEM =>
                    
                    -- reads from memory content of 'i_mem_data' and stores it in value
                    value <= to_integer(unsigned(i_mem_data));
                    state_curr <= S_READMEM_CHOICE;

                    
                when S_READMEM_CHOICE =>
                
                    -- chooses next step based on which value is read and if it's the first value read in the sequence
                    if (value = 0 and (jump = 0 or state_prev = S_3) ) then
                        jump <= jump + 2;
                        state_curr <= S_3;

                    elsif (value = 0 and jump /= 0 ) then
                        state_curr <= S_2;

                    elsif (value /= 0) then                        
                        jump <= jump + 1;   -- used to point to the next byte to write trust score 
                        trust <= 31;        -- input is /= 0 so trust is restored to 31
                        state_curr <= S_1;
                        
                    end if;    
      
                    
                when S_1 =>

                    -- here if value /=0
                    last_value <= value;                                                                    -- stores the current value in case the next value read is a zero
                    state_prev <= S_1;                                                                      -- remembers what state it was, useful in WRITEMEM state
                    o_mem_addr <= std_logic_vector(to_unsigned(jump + start_add, o_mem_addr'length));       -- next address is now output address
                    o_mem_data <= std_logic_vector(to_unsigned( trust, o_mem_data'length));                 -- trust (= 31) to be written in that address
                    o_mem_we <= '1';                                                                        -- enables memory write
                    state_curr <= S_WRITEMEM;
                    
                    
                when S_2 =>
                
                    -- input is = 0 but is not the first value read
                    state_prev <= S_2;
                    jump <= jump + 1;
                    
                    if (trust /= 0) then            -- if trust is not already 0
                        trust <= trust -1;          -- credibility gets decreased now to be ready for use in state S_21
                    end if;
                    
                    o_mem_data <= std_logic_vector(to_unsigned(last_value, o_mem_data'length));             --writes last value in place of 0
                    o_mem_we <= '1';                                                                        -- enables memory write
                    state_curr <= S_WRITEMEM;
                    
                    
                when S_3 =>
                
                    -- input is 0 and it's the first value read or state_prev = S_3: in this state it just advances by two adresses to read the 
                    -- next value after checking if there are more words to be read  
                    state_prev <= S_3;
                    
                    if(k > jump/2) then                         -- if k <= jump/2 it means all word have been read and the sequence is over
                        o_mem_addr <= std_logic_vector(to_unsigned(jump + start_add, o_mem_addr'length));
                        state_curr <= S_READMEM_WAIT;
                        
                    else                            
                        o_done <= '1';
                        state_curr <= S_DONE;
                        
                    end if;
                    
                    
                when S_WRITEMEM =>
                
                    -- waits for memory to be written 
                    if (state_prev /= S_2) then
                        jump <= jump + 1;               -- after writing 'last_value' jump is used to index the next address to write 'trust'
                    end if;    
                    
                    state_curr <= S_WRITEMEM_CHOICE;
                    
                                        
                when S_WRITEMEM_CHOICE =>
                    
                    -- chooses the next step after writing memory based on state_prev
                    if (state_prev = S_2) then      -- if state_prev is S_2 it continues to S_21 to write the credibility score in the next byte
                    
                        state_curr <= S_21;
                        
                    else                            -- otherwise if state_prev is S_1 or S_21 it reads the next word

                        if (k > jump/2) then
                        
                            o_mem_addr <= std_logic_vector(to_unsigned(jump + start_add, o_mem_addr'length));
                            state_curr <= S_READMEM_WAIT;
                            
                        else 
                        
                            o_done <= '1';
                            state_curr <= S_DONE;
                            
                        end if;
                        
                        o_mem_we <= '0';
                            
                    end if;        
                    

                when S_21 =>
                
                    --continues the case value = 0 and jump /= 0
                    o_mem_addr <= std_logic_vector(to_unsigned(jump + start_add, o_mem_addr'length));   
                    o_mem_data <= std_logic_vector(to_unsigned(trust, o_mem_data'length));              --writes trust in place of even 0 
                    state_prev <= S_21;
                    state_curr <= S_WRITEMEM;

                
                when S_DONE =>
                
                    -- waits for i_start to go to 0 to then return to idle
                    if (i_start = '0') then
                        state_curr <= S_IDLE;
                    end if; 
                    
                    
            end case;
            
        end if;
        
    end process;                        

end Behavioral;
