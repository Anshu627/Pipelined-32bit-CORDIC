`timescale 1ns / 1ps

module tb_cordic;

    reg clk;
    reg rst;
    reg valid_in;
    reg mode;
    reg signed [31:0] x_in;
    reg signed [31:0] y_in;
    reg signed [31:0] z_in;
    
    wire valid_out;
    wire signed [31:0] x_out;
    wire signed [31:0] y_out;
    wire signed [31:0] z_out;
    
    cordic_32bit_pipelined dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .mode(mode),
        .x_in(x_in),
        .y_in(y_in),
        .z_in(z_in),
        .valid_out(valid_out),
        .x_out(x_out),
        .y_out(y_out),
        .z_out(z_out)
    );
    
    // 100MHz clock
    always #5 clk = ~clk;
    
    initial begin
        $dumpfile("cordic_waves.vcd");
        $dumpvars(0, tb_cordic);
        
        clk = 0; rst = 1; valid_in = 0; mode = 0;
        x_in = 0; y_in = 0; z_in = 0;
        
        #25; 
        rst = 0; 
        
        // ---------------------------------------------------------
        // TEST CASE 1: ROTATION MODE (Target Angle = 30 degrees)
        // ---------------------------------------------------------
        @(posedge clk);
        #1; 
        valid_in = 1; 
        mode = 0; 
        x_in = 32'h26DD3B36; 
        y_in = 32'd0; 
        z_in = 32'h15555555; // 30 degrees
        
        // ---------------------------------------------------------
        // TEST CASE 2: VECTORING MODE (Target Y/X = 1/sqrt(3))
        // ---------------------------------------------------------
        @(posedge clk);
        #1; 
        valid_in = 1; 
        mode = 1;
        x_in = 32'h1BB67E31; // sqrt(3)
        y_in = 32'h10000000; // 1.0
        z_in = 32'd0;
        
        @(posedge clk);
        #1; 
        valid_in = 0;
        
        #1000;
        $finish; 
    end

    // ---------------------------------------------------------
    // ADVANCED TERMINAL MONITOR
    // ---------------------------------------------------------
    integer test_cnt = 0;
    real real_cos, real_sin, real_atan;

    always @(posedge clk) begin
        if (valid_out == 1'b1) begin
            test_cnt = test_cnt + 1;
            
            // Do the floating point conversions
            // Divide X and Y by 2^30 (1073741824.0)
            real_cos  = $itor(x_out) / 1073741824.0;
            real_sin  = $itor(y_out) / 1073741824.0;
            
            // Multiply Z by 45 and divide by 2^29 (536870912.0)
            real_atan = ($itor(z_out) * 45.0) / 536870912.0;

            $display("\n============================================================");
            $display(" TIME: %0t ns | TEST CASE %0d", $time, test_cnt);
            $display("------------------------------------------------------------");
            $display(" RAW (Hex)  | X_out: %h | Y_out: %h | Z_out: %h", x_out, y_out, z_out);
            
            if (test_cnt == 1) begin
                $display(" MODE       | ROTATION (Calculates Sine & Cosine)");
                $display(" TARGET     | Calculate Sin/Cos for Angle = 30.0 degrees");
                $display(" RESULT     | COSINE = %f", real_cos);
                $display(" RESULT     | SINE   = %f", real_sin);
            end else if (test_cnt == 2) begin
                $display(" MODE       | VECTORING (Calculates Arctangent)");
                $display(" TARGET     | Calculate Arctan of 1.0 / sqrt(3)");
                $display(" EXPECTED   | Angle should equal 30.0 degrees");
                $display(" RESULT     | ARCTAN = %f degrees", real_atan);
            end
            $display("============================================================\n");
        end
    end

endmodule