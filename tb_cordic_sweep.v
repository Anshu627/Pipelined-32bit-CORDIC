`timescale 1ns/1ps
// =============================================================================
// tb_cordic_sweep.v
//
// Sweeps the cordic_unified core across all 4 modes and dumps every
// (input, hardware output) pair to cordic_results.csv. A companion Python
// script (cordic_verify.py) recomputes the same points with math.*, compares
// them to this CSV, and produces overlaid plots + an error report.
// =============================================================================
module tb_cordic_sweep;

    reg clk = 0, rst = 1, valid_in = 0, coord_mode = 0, op_mode = 0;
    reg  signed [31:0] x_in, y_in, z_in;
    wire valid_out;
    wire signed [31:0] x_out, y_out, z_out;

    cordic_unified dut (
        .clk(clk), .rst(rst), .valid_in(valid_in),
        .coord_mode(coord_mode), .op_mode(op_mode),
        .x_in(x_in), .y_in(y_in), .z_in(z_in),
        .valid_out(valid_out), .x_out(x_out), .y_out(y_out), .z_out(z_out)
    );

    always #5 clk = ~clk;

    localparam real SCALE = 134217728.0; // 2^27, Q4.27
    integer fd;

    // Drive one input vector into the pipeline and, after enough cycles for
    // it to drain through all 34 stages, log the hardware result.
    task run_case(input real xr, input real yr, input real zr,
                  input cm, input om, input [31:0] tag);
        reg signed [31:0] xi, yi, zi;
        begin
            xi = $rtoi(xr * SCALE);
            yi = $rtoi(yr * SCALE);
            zi = $rtoi(zr * SCALE);

            @(negedge clk);
            x_in = xi; y_in = yi; z_in = zi;
            coord_mode = cm; op_mode = om; valid_in = 1;
            @(negedge clk);
            valid_in = 0;
            repeat (40) @(negedge clk); // drain the 34-stage pipeline

            $fdisplay(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                tag, cm, om, xi, yi, zi, x_out, y_out, z_out);
        end
    endtask

    integer k;
    real theta, v;

    initial begin
        fd = $fopen("cordic_results.csv", "w");
        $fdisplay(fd, "tag,coord_mode,op_mode,x_in,y_in,z_in,x_out,y_out,z_out");

        rst = 1; valid_in = 0; x_in = 0; y_in = 0; z_in = 0;
        coord_mode = 0; op_mode = 0;
        repeat (3) @(negedge clk);
        rst = 0;

        // ---- 1. Circular ROTATION: cos(theta), sin(theta) ----
        // theta swept from -170 to +170 deg to exercise the quadrant folder
        for (k = -170; k <= 170; k = k + 5) begin
            theta = k * 3.14159265358979 / 180.0;
            run_case(1.0, 0.0, theta, 1'b0, 1'b0, 1);
        end

        // ---- 2. Circular VECTORING: recover magnitude & angle (atan2) ----
        for (k = -170; k <= 170; k = k + 5) begin
            theta = k * 3.14159265358979 / 180.0;
            run_case($cos(theta), $sin(theta), 0.0, 1'b0, 1'b1, 2);
        end

        // ---- 3. Hyperbolic ROTATION: cosh(z), sinh(z) ----
        // hyperbolic CORDIC only converges for |z| < ~1.118 rad
        for (k = -100; k <= 100; k = k + 5) begin
            v = k / 100.0; // -1.0 .. 1.0
            run_case(1.0, 0.0, v, 1'b1, 1'b0, 3);
        end

        // ---- 4. Hyperbolic VECTORING: atanh(v) ----
        // Kept within the hyperbolic convergence domain (|atanh(v)| < ~1.118
        // rad => |v| < ~0.807). Values outside this range are a fundamental
        // limitation of hyperbolic CORDIC, not a hardware bug (see header
        // comment in cordic_unified.v).
        for (k = -80; k <= 80; k = k + 5) begin
            v = k / 100.0; // -0.8 .. 0.8
            run_case(1.0, v, 0.0, 1'b1, 1'b1, 4);
        end

        $fclose(fd);
        $display("Wrote cordic_results.csv");
        $finish;
    end
endmodule