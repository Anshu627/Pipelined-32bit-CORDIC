`timescale 1ns / 1ps

module tb_cordic_sweep;

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
    integer file, step;
    real val;

    // --- PIPELINE TRACKING ---
    integer current_test_id;
    real current_input_val;
    integer delay_test_id [0:34];
    real delay_input_val [0:34];
    integer i;

    always @(posedge clk) begin
        delay_test_id[0] <= current_test_id;
        delay_input_val[0] <= current_input_val;
        for (i = 0; i < 34; i = i + 1) begin
            delay_test_id[i+1] <= delay_test_id[i];
            delay_input_val[i+1] <= delay_input_val[i];
        end
    end

    // --- TASK TO FEED CORDIC ---
    task feed_cordic(
        input integer t_id, input real in_val, 
        input integer cmode, input integer omode,
        input signed [31:0] xin, input signed [31:0] yin, input signed [31:0] zin
    );
        begin
            @(posedge clk); #1;
            valid_in = 1; coord_mode = cmode; op_mode = omode;
            x_in = xin; y_in = yin; z_in = zin;
            current_test_id = t_id; current_input_val = in_val;
        end
    endtask

    initial begin
        file = $fopen("cordic_results.csv", "w");
        $fwrite(file, "test_id,input_val,out_x,out_y,out_z\n");
        
        clk = 0; rst = 1; valid_in = 0; 
        current_test_id = 0; current_input_val = 0;
        #25; rst = 0; 

        // 1. SIN & COS 
        // 1/Kc = 0.607252935 -> 0x04DBA7A5 (Perfected Q4.27)
        for (step = -90; step <= 90; step = step + 2) begin
            val = step;
            feed_cordic(1, val, 0, 0, 32'h04DBA7A5, 32'd0, $rtoi((val * 3.14159265 / 180.0) * 134217728.0));
        end

        // 2. ARCTAN (Inputs: X=1.0, Y=Sweep)
        for (step = -20; step <= 20; step = step + 1) begin
            val = step / 10.0;
            feed_cordic(2, val, 0, 1, 32'h08000000, $rtoi(val * 134217728.0), 32'd0);
        end

        // 3. SINH & COSH 
        // 1/Kh = 1.207497067 -> 0x09A9D41C (This was the bug!)
        for (step = -11; step <= 11; step = step + 1) begin
            val = step / 10.0;
            feed_cordic(3, val, 1, 0, 32'h09A9D41C, 32'd0, $rtoi(val * 134217728.0));
        end

        // 4. e^x
        // 1/Kh = 1.207497067 -> 0x09A9D41C
        for (step = -11; step <= 11; step = step + 1) begin
            val = step / 10.0;
            feed_cordic(4, val, 1, 0, 32'h09A9D41C, 32'h09A9D41C, $rtoi(val * 134217728.0));
        end

        // 5. ARCTANH
        for (step = -8; step <= 8; step = step + 1) begin
            val = step / 10.0;
            feed_cordic(5, val, 1, 1, 32'h08000000, $rtoi(val * 134217728.0), 32'd0);
        end

        // 6. Natural Log (ln)
        for (step = 2; step <= 30; step = step + 1) begin
            val = step / 10.0;
            feed_cordic(6, val, 1, 1, $rtoi((val + 1.0) * 134217728.0), $rtoi((val - 1.0) * 134217728.0), 32'd0);
        end

        // 7. Square Root
        for (step = 2; step <= 30; step = step + 1) begin
            val = step / 10.0;
            feed_cordic(7, val, 1, 1, $rtoi((val + 0.25) * 134217728.0), $rtoi((val - 0.25) * 134217728.0), 32'd0);
        end

        @(posedge clk); #1; valid_in = 0; current_test_id = 0;
        
        #1000;
        $fclose(file);
        $display("Data generation complete! Run the Python script to generate the plots.");
        $finish;
    end

    // --- MONITOR BLOCK ---
    always @(posedge clk) begin
        if (valid_out == 1'b1 && delay_test_id[34] != 0) begin
            $fwrite(file, "%0d,%f,%f,%f,%f\n", 
                delay_test_id[34], 
                delay_input_val[34], 
                $itor(x_out) / 134217728.0, 
                $itor(y_out) / 134217728.0, 
                $itor(z_out) / 134217728.0
            );
        end
    end
endmodule