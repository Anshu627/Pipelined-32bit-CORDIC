`timescale 1ns / 1ps

module tb_cordic_unified;

    reg clk, rst, valid_in, coord_mode, op_mode;
    reg signed [31:0] x_in, y_in, z_in;
    
    wire valid_out;
    wire signed [31:0] x_out, y_out, z_out;
    
    cordic_unified dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .coord_mode(coord_mode), .op_mode(op_mode),
        .x_in(x_in), .y_in(y_in), .z_in(z_in),
        .valid_out(valid_out), .x_out(x_out), .y_out(y_out), .z_out(z_out)
    );
    
    always #5 clk = ~clk;
    
    initial begin
        $dumpfile("unified_waves.vcd");
        $dumpvars(0, tb_cordic_unified);
        
        clk = 0; rst = 1; valid_in = 0; 
        coord_mode = 0; op_mode = 0;
        x_in = 0; y_in = 0; z_in = 0;
        
        #25; rst = 0; 
        
        // -----------------------------------------------------------------
        // TEST 1: Circular Rotation -> Sin/Cos of 30 degrees
        // Target: Z = 30 deg in Radians (0.5236 * 2^27 = 0x04305EE7)
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=0; op_mode=0; 
        x_in=32'h04DBA76A; y_in=32'd0; z_in=32'h04305EE7; 
        
        // -----------------------------------------------------------------
        // TEST 2: Circular Vectoring -> Arctan(1 / sqrt(3))
        // Target: Y=1.0, X=1.732 (0x0DD5C8E8)
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=0; op_mode=1;
        x_in=32'h0DD5C8E8; y_in=32'h08000000; z_in=32'd0;
        
        // -----------------------------------------------------------------
        // TEST 3: Hyperbolic Rotation -> Sinh/Cosh of 0.5
        // Target: Z = 0.5 (0x04000000)
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=1; op_mode=0;
        x_in=32'h09A9D1D2; y_in=32'd0; z_in=32'h04000000;

        // -----------------------------------------------------------------
        // TEST 4: Hyperbolic Rotation -> e^X of 1.0
        // Target: e^1.0. Start with X = 1/Kh, Y = 1/Kh
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=1; op_mode=0;
        x_in=32'h09A9D1D2; y_in=32'h09A9D1D2; z_in=32'h08000000;

        // -----------------------------------------------------------------
        // TEST 5: Hyperbolic Vectoring -> Arctanh(0.5)
        // Target: Y = 0.5, X = 1.0
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=1; op_mode=1;
        x_in=32'h08000000; y_in=32'h04000000; z_in=32'd0;

        // -----------------------------------------------------------------
        // TEST 6: Hyperbolic Vectoring -> Natural Log (ln) of 2.0
        // Target: X = W+1 = 3.0, Y = W-1 = 1.0
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=1; op_mode=1;
        x_in=32'h18000000; y_in=32'h08000000; z_in=32'd0;

        // -----------------------------------------------------------------
        // TEST 7: Hyperbolic Vectoring -> Square Root of 4.0
        // Target: X = W+0.25 = 4.25, Y = W-0.25 = 3.75
        // -----------------------------------------------------------------
        @(posedge clk); #1; valid_in=1; coord_mode=1; op_mode=1;
        x_in=32'h22000000; y_in=32'h1E000000; z_in=32'd0;
        
        @(posedge clk); #1; valid_in = 0;
        #1000; $finish; 
    end

    // ---------------------------------------------------------
    // Advanced Math Conversions and Terminal Display
    // ---------------------------------------------------------
    integer test_cnt = 0;
    real real_x, real_y, real_z;

    always @(posedge clk) begin
        if (valid_out == 1'b1) begin
            test_cnt = test_cnt + 1;
            
            // Divide by 2^27 (134217728.0) to get real-world floats
            real_x = $itor(x_out) / 134217728.0;
            real_y = $itor(y_out) / 134217728.0;
            real_z = $itor(z_out) / 134217728.0;

            $display("\n============================================================");
            $display(" TIME: %0t ns | TEST CASE %0d", $time, test_cnt);
            
            if (test_cnt == 1) begin
                $display(" TARGET     | Sin(30) & Cos(30)");
                $display(" RESULT     | COSINE = %f", real_x);
                $display(" RESULT     | SINE   = %f", real_y);
            end else if (test_cnt == 2) begin
                $display(" TARGET     | Arctan(1 / sqrt(3))");
                // Convert Radians to Degrees for easier reading
                $display(" RESULT     | ARCTAN = %f degrees", (real_z * 180.0) / 3.14159265);
            end else if (test_cnt == 3) begin
                $display(" TARGET     | Sinh(0.5) & Cosh(0.5)");
                $display(" RESULT     | COSH   = %f", real_x);
                $display(" RESULT     | SINH   = %f", real_y);
            end else if (test_cnt == 4) begin
                $display(" TARGET     | e^x of 1.0");
                $display(" RESULT     | e^1.0  = %f", real_x);
            end else if (test_cnt == 5) begin
                $display(" TARGET     | Arctanh(0.5)");
                $display(" RESULT     | ARCTANH= %f", real_z);
            end else if (test_cnt == 6) begin
                $display(" TARGET     | Natural Log (ln) of 2.0");
                // CORDIC outputs 0.5 * ln(w). Multiply by 2!
                $display(" RESULT     | ln(2)  = %f", real_z * 2.0);
            end else if (test_cnt == 7) begin
                $display(" TARGET     | Square Root of 4.0");
                // Multiply magnitude by 1/Kh (1.207497) to remove gain
                $display(" RESULT     | SQRT(4)= %f", real_x * 1.207497);
            end
            $display("============================================================");
        end
    end
endmodule