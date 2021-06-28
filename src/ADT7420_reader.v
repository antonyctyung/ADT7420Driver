`timescale 1ns / 1ps

module ADT7420_reader(
        input CLK100MHZ,
        output reg [15:0] temp_Celsius,
        output error,
        output TMP_SCL,
        inout TMP_SDA,
        output [5:0] i2c_state,
        output reg [2:0] state_reg
    );

    // generate 250kHz SCL (clk/4) as ADT7420 take SCL at max 400kHz
    reg [5:0] counter1mhz = 0;
    assign clk1mhz = counter1mhz[5];
    always @(posedge CLK100MHZ) counter1mhz = (counter1mhz>49)? 0: counter1mhz + 1;                 // cap at 50

    // data registers
    reg             run = 0;                                                                        // rising edge to run transmission for a byte
    reg             start_cond;                                                                     // prepend start condition
    reg             stop_cond;                                                                      //  append  stop condition
    reg             read_nWrite;                                                                    // Read / Not Write, byte direction
    reg             ack_nack_write;                                                                 //  Ack / Not Ack  , send to slave after read
    reg     [7:0]   wbyte;                                                                          // byte to write to slave
    reg     [15:0]  temp_Celsius_buf = 0;                                                           // temperature output buffer
    wire    [7:0]   rbyte;                                                                          // byte to read from slave
    reg             done_nRunning_minus = 0;                                                        // for detecting rising/falling edge

    // wire I2C
    I2C iic(clk1mhz,run,start_cond,stop_cond,read_nWrite,ack_nack_write,wbyte,
            rbyte,done_nRunning,error,TMP_SCL,TMP_SDA,i2c_state);

    // state assignment
    localparam [2:0]
        write_address_1 = 3'b000,
        write_register  = 3'b001,
        write_address_2 = 3'b010,
         read_temp_MSB  = 3'b011,
         read_temp_LSB  = 3'b100,
         wait_and_run   = 3'b101
    ;

    // state register
    initial state_reg   = write_address_1;
    reg [2:0]   state_next  = write_address_1;

    // state progression
    always @(posedge CLK100MHZ) state_reg <= state_next;

    // state behaviour
    always @*
    begin
        state_next = state_reg;
        case (state_reg)
            write_address_1:
                begin
                    temp_Celsius_buf = {temp_Celsius_buf[7:0], rbyte};                              // receive read byte
                    start_cond = 1;                                                                 // load parameter
                    stop_cond = 0;
                    read_nWrite = 0;
                    ack_nack_write = 0;
                    wbyte = 'h4b<<1;
                    done_nRunning_minus = 0;                                                        // prepare for rising edge
                    run = 0;                                                                        // reset run pulse
                    state_next = wait_and_run;                                                      // proceed
                end
            write_register:
                begin
                    temp_Celsius = {temp_Celsius_buf[7:0], rbyte};                                  // receive read byte
                    start_cond = 0;
                    stop_cond = 0;
                    read_nWrite = 0;
                    ack_nack_write = 0;
                    wbyte = 'h00;
                    done_nRunning_minus = 0;                                                        // prepare for rising edge
                    run = 0;                                                                        // reset run pulse
                    state_next = wait_and_run;
                end             
            write_address_2:
                begin
                    start_cond = 1;
                    stop_cond = 0;
                    read_nWrite = 0;
                    ack_nack_write = 0;
                    wbyte = ('h4b<<1) + 'h01;
                    done_nRunning_minus = 0;                                                        // prepare for rising edge
                    run = 0;                                                                        // reset run pulse
                    state_next = wait_and_run;
                end             
            read_temp_MSB:
                begin
                    start_cond = 0;
                    stop_cond = 0;
                    read_nWrite = 1;
                    ack_nack_write = 1;                                                             //  ack to keep reading
                    done_nRunning_minus = 0;                                                        // prepare for rising edge
                    run = 0;                                                                        // reset run pulse
                    state_next = wait_and_run;
                end 
            read_temp_LSB:
                begin
                    start_cond = 0;
                    stop_cond = 1;
                    read_nWrite = 1;
                    ack_nack_write = 0;                                                             // nack to stop reading
                    done_nRunning_minus = 0;                                                        // prepare for rising edge
                    run = 0;                                                                        // reset run pulse
                    state_next = wait_and_run;
                end 
            wait_and_run:
                begin
                    state_next = state_reg;                                                         // if no change in done_nRunning
                    
                    if (done_nRunning && !done_nRunning_minus)                                      // rising edge i.e. transmission done
                    begin
                        done_nRunning_minus = done_nRunning;                                        // log change
                        run = 1;                                                                    // instruct to run
                    end

                    if (!done_nRunning && done_nRunning_minus)                                      // falling edge i.e. transmission started
                    begin
                        done_nRunning_minus = done_nRunning;                                        // log change
                        run = 0;                                                                    // reset run pulse
                        if (stop_cond) state_next = write_address_1;                                // last transmission was            reading LSB
                        else if (read_nWrite) state_next = read_temp_LSB;                           // last transmission was            reading MSB
                        else if (!start_cond) state_next = write_address_2;                         // last transmission was            writing register address
                        else if (wbyte[0]) state_next = read_temp_MSB;                              // last transmission was the second writing of device address
                        else state_next = write_register;                                           // last transmission was the  first writing of device address
                    end
                end                 
            default: state_next = write_address_1;
        endcase
    end

endmodule

