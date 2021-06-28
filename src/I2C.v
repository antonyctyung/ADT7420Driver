`timescale 1ns / 1ps

module I2C(
     input              clk,                                                                        // should be 4x desired SCL frequency
     input              run,                                                                        // rising edge to run transmission for a byte
     input              start_cond,                                                                 // prepend start condition
     input              stop_cond,                                                                  //  append  stop condition
     input              read_nWrite,                                                                // Read / Not Write, byte direction
     input              ack_nack_write,                                                             //  Ack / Not Ack  , send to slave after read
     input      [7:0]   wbyte,                                                                      // byte to write to slave
    output  reg [7:0]   rbyte,                                                                      // byte read from slave
    output              done_nRunning,                                                              // Done / Not Running
    output  reg         error,                                                                      // error flag, raised when nack from slave
    output  reg         SCL_hw,                                                                     // hardware SCL pin, assuming external pullup
     inout              SDA_hw,                                                                     // hardware SDA pin, assuming external pullup
    output  reg [5:0]   state_reg
    );

    // buffer
    reg     start_cond_buf = 0;
    reg      stop_cond_buf = 0;
    reg    read_nWrite_buf = 0;
    reg ack_nack_write_buf = 0;
    reg [7:0]    wbyte_buf = 0;
    reg [7:0]    rbyte_buf = 0;

    // init
    initial
    begin
        rbyte  = 0;
        error  = 0;
        SCL_hw = 0;
    end

    // SDA tri-state
    reg    SDA    = 1;                                                                              // initial high-z
    assign SDA_hw = (SDA)? 1'bz : 0 ;                                                               // high-z for read or for writing logic 1
    assign SDA_in = SDA_hw;                                                                         // wire to read from slave

    // four states for each bit: SCL low, SCL posedge, SCL high, SCL negedge
    // write only when state_reg[0] == 1 (SCL high or low)

    // state assignment
    localparam [5:0]
                   idle = 6'b111100,                                                                // the initial state
             start_low  = 6'b111101,
             start_pos  = 6'b111110,
             start_high = 6'b111111,
             start_neg  = 6'b000000,
        eightbit_0_low  = 6'b000001,                                                                // write wbuf[state_reg[4:2]]   to SDA 
        eightbit_0_pos  = 6'b000010,                                                                // SCL posedeg
        eightbit_0_high = 6'b000011,                                                                //  read rbuf[state_reg[4:2]] from SDA
        eightbit_0_neg  = 6'b000100,                                                                // SCL negedge
        eightbit_1_low  = 6'b000101,
        eightbit_1_pos  = 6'b000110,
        eightbit_1_high = 6'b000111,
        eightbit_1_neg  = 6'b001000,
        eightbit_2_low  = 6'b001001,
        eightbit_2_pos  = 6'b001010,
        eightbit_2_high = 6'b001011,
        eightbit_2_neg  = 6'b001100,
        eightbit_3_low  = 6'b001101,
        eightbit_3_pos  = 6'b001110,
        eightbit_3_high = 6'b001111,
        eightbit_3_neg  = 6'b010000,
        eightbit_4_low  = 6'b010001,
        eightbit_4_pos  = 6'b010010,
        eightbit_4_high = 6'b010011,
        eightbit_4_neg  = 6'b010100,
        eightbit_5_low  = 6'b010101,
        eightbit_5_pos  = 6'b010110,
        eightbit_5_high = 6'b010111,
        eightbit_5_neg  = 6'b011000,
        eightbit_6_low  = 6'b011001,
        eightbit_6_pos  = 6'b011010,
        eightbit_6_high = 6'b011011,
        eightbit_6_neg  = 6'b011100,
        eightbit_7_low  = 6'b011101,
        eightbit_7_pos  = 6'b011110,
        eightbit_7_high = 6'b011111,
        eightbit_7_neg  = 6'b100000,
          ack_nack_low  = 6'b100001,
          ack_nack_pos  = 6'b100010,
          ack_nack_high = 6'b100011,
          ack_nack_neg  = 6'b100100,
              stop_low  = 6'b100101,
              stop_pos  = 6'b100110,
              stop_high = 6'b100111,
              stop_neg  = 6'b101000;


    // status registers
    reg run_minus = 0;                                                                              // to detect rising edge for run

    // state registers
    initial state_reg  = idle;
    reg [5:0] state_next = idle;

    // state progression
    always @(posedge clk) state_reg <= (error)? idle : state_next;

    // state behavior for SCL
    always @*
    begin
        SCL_hw = state_reg[1];                                                                      // clock according to state_reg bit 1
        if (state_reg[5:1] == 'b11111) SCL_hw = start_cond_buf;                                     // Do not clock if no start condition
        if (state_reg[5:1] == 'b10011) SCL_hw =  stop_cond_buf;                                     // Do not clock if no  stop condition
    end

    // state behavior
    always @*
    begin
        state_next = (state_reg == stop_neg)? idle : state_reg + 1;
        if (state_reg == idle)                                                                      // idle state
        begin
            rbyte = rbyte_buf;                                                                      // output byte read
            if (run == 0)                                                                           
            begin
                run_minus = 0;                                                                      // negedge or cont low
                state_next = idle;
            end
            else if (run_minus == 0)                                                                // run_minus low and run high, rising edge
            begin
                    start_cond_buf = start_cond;                                                    // load value to buffer
                     stop_cond_buf = stop_cond;
                   read_nWrite_buf = read_nWrite;
                ack_nack_write_buf = ack_nack_write;
                         wbyte_buf = wbyte;
            end
            else state_next = idle;                                                                 // both run and run_minus is high, stay idle
        end
        else if (state_reg[0] == 1)                                                                 // only when SCL is high or low, no action for SCL posedge and negedge
        begin
            if (state_reg[5] == 0)                                                                  // any of the eightbit_x_xxxx states
            begin
                if (state_reg[1])                                                                   // eightbit_x_high
                begin
                    if (read_nWrite_buf)                                                            // reading byte from slave
                        rbyte_buf[state_reg[4:2]] = SDA_in;                                         // read from SDA to rbyte_buf
                end
                else                                                                                // eightbit_x_low
                begin
                    if (!read_nWrite_buf)                                                           // writing byte to slave
                        SDA = wbyte_buf[state_reg[4:2]];                                            // write to SDA from wbyte_buf
                    else SDA = 1;                                                                   // leave SDA at high-z if not writing at SCL low to prepare reading at SCL high
                end
            end
            else if (state_reg == start_low)
            begin
                SDA = 1;                                                                            // SDA hi-z before start condition SCL pulse
            end
            else if (state_reg == start_high)
            begin
                SDA = 0;                                                                            // SDA fall during start condition SCL pulse
            end
            else if (state_reg ==  stop_low)
            begin
                SDA = 0;                                                                            // SDA  low before  stop condition SCL pulse
            end            
            else if (state_reg == stop_high)
            begin
                SDA = 1;                                                                            // SDA rise during  stop condition SCL clock pulse
            end
            else if (state_reg == ack_nack_low)
            begin
                if (read_nWrite_buf)                                                                // already read from slave
                    SDA = !ack_nack_write_buf;                                                      // write ack/nack to SDA
                else SDA = 1;                                                                       // leave SDA at high-z if not read at SCL low to prepare slave ack/nack at SCL high            end
            end
            else if (state_reg == ack_nack_high)
            begin
                if (!read_nWrite_buf)                                                               // wrote byte, slave ack/nack
                    begin
                        error = SDA_in;                                                             // slave nack, raise error flag
                    end
            end
/*                case (state_reg[4:2])
                    000:                                                                            // ack/nack
                        if (state_reg[1])                                                           // ack_nack_high
                        begin
                            if (!read_nWrite_buf)                                                   // wrote byte, slave ack/nack
                            begin
                                error = SDA_in;                                                     // slave nack, raise error flag
                            end
                        end
                        else                                                                        // eightbit_x_low
                        begin
                            if (read_nWrite_buf)                                                    // already read from slave
                                SDA = !ack_nack_write;                                              // write ack/nack to SDA
                            else SDA = 1;                                                           // leave SDA at high-z if not read at SCL low to prepare slave ack/nack at SCL high
                        end
                    001: SDA =  state_reg[1];                                                       //  stop condition, SDA rise during clock
                    111: SDA = !state_reg[1];                                                       // start condition, SDA fall during clock
                    //default: error = 1;                                                             // undefined states, raise error flag
                endcase
*/      end
    end

    // output
    assign done_nRunning = (state_reg == idle);                                                     // transmission not running when idle

endmodule