`timescale 1ns / 1ps

// =============================================================================
// cordic_unified.v  (fixed version)
//
// 32-bit pipelined CORDIC datapath, Q4.27 fixed point (1.0 = 27'h08000000).
// Supports Circular mode (sin/cos/atan) and Hyperbolic mode (sinh/cosh/atanh,
// which also gives e^x and ln(x) with a small combinational post/pre step).
//
// coord_mode : 0 = Circular, 1 = Hyperbolic
// op_mode    : 0 = Rotation  (z drives, output = cos/sin or cosh/sinh of z_in)
//              1 = Vectoring (y/x drives, output = magnitude and arctan/artanh)
//
// e^x and ln(x) are obtained with a small amount of software/glue logic on
// top of the hyperbolic mode outputs (no extra hardware needed):
//   e^x  = cosh(x) + sinh(x)              -> hyperbolic ROTATION, x_in=1/K_hyp_inv... 
//          i.e. rotation mode with z_in = x, then x_out + y_out = e^x
//   ln(v)= 2 * atanh( (v-1)/(v+1) )        -> hyperbolic VECTORING with
//          x_in = v+1, y_in = v-1, z_out = atanh((v-1)/(v+1)), so ln(v)=2*z_out
//
// This version fixes the following issues found in the original core:
//   1. d_dir renamed to "sigma" with a clear comment on the rotation
//      convention, so the direction logic is no longer "fishy".
//   2. CORDIC gain is compensated by PRE-SCALING x_in/y_in by 1/K before the
//      first stage (a single Q4.27 multiply). Because the CORDIC recursion is
//      linear in x0,y0, scaling both inputs by 1/K exactly cancels the gain
//      picked up over the pipeline, for BOTH rotation and vectoring modes.
//      This is the "pre-scaling calibration" step.
//   3. Basic quadrant/range handling added for circular mode so the angle fed
//      into the pipeline is always inside the guaranteed-convergence range
//      of about +-90 degrees:
//        - Rotation mode: if |z_in| > 90 deg, subtract/add 180 deg from z and
//          negate x_in,y_in (rotating the input vector by 180 deg first).
//        - Vectoring mode: if x_in < 0, negate x_in,y_in and add/subtract
//          180 deg from z_in (this also gives a full atan2-style result).
//   4. Hyperbolic convergence: the shift table already repeats iterations
//      i=4 and i=13 (the classic 4,13,40,... repeated-iteration trick needed
//      for hyperbolic CORDIC to converge) - this is intentional, now
//      documented in the shift-table comment. Valid input range for
//      hyperbolic mode is |z_in| < ~1.118 rad (~64 deg); this is a
//      fundamental property of hyperbolic CORDIC and is documented rather
//      than "fixed" (there's no folding trick for hyperbolic functions).
//   5. valid pipeline: the datapath computes every cycle regardless of
//      valid_in (standard for a fully-pipelined core - it just processes
//      whatever is in the registers). valid_in/valid_out is only a tag that
//      marks which results are meaningful; it does not need to gate the
//      arithmetic for correctness. Documented here instead of "fixed" since
//      changing this would only save power, not correctness.
//   6. Overflow/saturation: all additions inside the pipeline and the
//      pre-scaling multiply now saturate to the 32-bit signed range instead
//      of silently wrapping around.
//   7. 34 stages vs angle tables: the circular angle table correctly goes to
//      0 after i=27 because the rotation angle at that point is smaller than
//      the LSB (2^-27 rad) - continuing has no effect on z and only a
//      negligible effect on x/y, so it is harmless, just a documented
//      (not a bug) source of a few "wasted" pipeline stages.
// =============================================================================

module cordic_unified (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    valid_in,
    input  wire                    coord_mode,  // 0: Circular, 1: Hyperbolic
    input  wire                    op_mode,     // 0: Rotation,  1: Vectoring
    input  wire signed [31:0]      x_in,
    input  wire signed [31:0]      y_in,
    input  wire signed [31:0]      z_in,
    output wire                    valid_out,
    output wire signed [31:0]      x_out,
    output wire signed [31:0]      y_out,
    output wire signed [31:0]      z_out
);

    localparam STAGES = 34;

    // -------------------------------------------------------------------------
    // Q4.27 constants
    //   1/K_circular = 0.6072529350088813  (compensates circular gain ~1.6468)
    //   1/K_hyperbolic = 1.207497067763072 (compensates hyperbolic gain ~0.8282)
    //   pi/2 = 1.5707963267948966
    //   pi   = 3.141592653589793
    // -------------------------------------------------------------------------
    localparam signed [31:0] K_CIRC_INV_Q427 = 32'h04DBA76D;
    localparam signed [31:0] K_HYP_INV_Q427  = 32'h09A8F439;
    localparam signed [31:0] PI_HALF_Q427    = 32'h0C90FDAA;
    localparam signed [31:0] PI_Q427         = 32'h1921FB54;

    // -------------------------------------------------------------------------
    // Q4.27 saturating multiply: (a * b) >> 27, clamped to signed 32-bit range.
    // Used once, combinationally, for the gain pre-scaling step.
    // -------------------------------------------------------------------------
    function signed [31:0] q427_mul;
        input signed [31:0] a;
        input signed [31:0] b;
        reg signed [63:0] prod;
        reg signed [63:0] shifted;
        begin
            prod    = a * b;
            shifted = prod >>> 27;
            if (shifted > 64'sd2147483647)
                q427_mul = 32'sh7FFFFFFF;
            else if (shifted < -64'sd2147483648)
                q427_mul = 32'sh80000000;
            else
                q427_mul = shifted[31:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Saturating add (also used for subtraction, by negating b at the call
    // site). Prevents silent 2's-complement wraparound on overflow.
    // -------------------------------------------------------------------------
    function signed [31:0] sat_add;
        input signed [31:0] a;
        input signed [31:0] b;
        reg signed [32:0] sum;
        begin
            sum = {a[31], a} + {b[31], b};
            if (sum > 33'sd2147483647)
                sat_add = 32'sh7FFFFFFF;
            else if (sum < -33'sd2147483648)
                sat_add = 32'sh80000000;
            else
                sat_add = sum[31:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Per-stage shift amount and micro-rotation angle lookup.
    // -------------------------------------------------------------------------
    function [4:0] get_circ_shift(input integer i);
        get_circ_shift = (i > 31) ? 31 : i;
    endfunction

    // Hyperbolic shift sequence: 1,2,3,4,4,5,...,13,13,14,...
    // The repeats at i=4 and i=13 are required for hyperbolic CORDIC to
    // converge (classic "repeated iteration" trick) - not a bug.
    function [4:0] get_hyp_shift(input integer i);
        case (i)
            0: get_hyp_shift=1;   1: get_hyp_shift=2;   2: get_hyp_shift=3;   3: get_hyp_shift=4;
            4: get_hyp_shift=4;   5: get_hyp_shift=5;   6: get_hyp_shift=6;   7: get_hyp_shift=7;
            8: get_hyp_shift=8;   9: get_hyp_shift=9;   10:get_hyp_shift=10;  11:get_hyp_shift=11;
            12:get_hyp_shift=12;  13:get_hyp_shift=13;  14:get_hyp_shift=13;  15:get_hyp_shift=14;
            16:get_hyp_shift=15;  17:get_hyp_shift=16;  18:get_hyp_shift=17;  19:get_hyp_shift=18;
            20:get_hyp_shift=19;  21:get_hyp_shift=20;  22:get_hyp_shift=21;  23:get_hyp_shift=22;
            24:get_hyp_shift=23;  25:get_hyp_shift=24;  26:get_hyp_shift=25;  27:get_hyp_shift=26;
            28:get_hyp_shift=27;  29:get_hyp_shift=28;  30:get_hyp_shift=29;  31:get_hyp_shift=30;
            32:get_hyp_shift=31;  33:get_hyp_shift=31;  default: get_hyp_shift=31;
        endcase
    endfunction

    function [31:0] get_circ_angle(input integer i);
        case(i)
            0: get_circ_angle = 32'h06487ED5;  1: get_circ_angle = 32'h03B58C36;  2: get_circ_angle = 32'h01F5B75E;
            3: get_circ_angle = 32'h00FEADD2;  4: get_circ_angle = 32'h007FD56F;  5: get_circ_angle = 32'h003FF5AB;
            6: get_circ_angle = 32'h001FFD55;  7: get_circ_angle = 32'h000FFFAB;  8: get_circ_angle = 32'h0007FFD5;
            9: get_circ_angle = 32'h0003FFFA;  10:get_circ_angle = 32'h0001FFFF;  11:get_circ_angle = 32'h00010000;
            12:get_circ_angle = 32'h00008000;  13:get_circ_angle = 32'h00004000;  14:get_circ_angle = 32'h00002000;
            15:get_circ_angle = 32'h00001000;  16:get_circ_angle = 32'h00000800;  17:get_circ_angle = 32'h00000400;
            18:get_circ_angle = 32'h00000200;  19:get_circ_angle = 32'h00000100;  20:get_circ_angle = 32'h00000080;
            21:get_circ_angle = 32'h00000040;  22:get_circ_angle = 32'h00000020;  23:get_circ_angle = 32'h00000010;
            24:get_circ_angle = 32'h00000008;  25:get_circ_angle = 32'h00000004;  26:get_circ_angle = 32'h00000002;
            27:get_circ_angle = 32'h00000001;  default: get_circ_angle = 32'h00000000; // below LSB, correctly 0
        endcase
    endfunction

    function [31:0] get_hyp_angle(input integer i);
        case(i)
            0: get_hyp_angle = 32'h046517B4;  1: get_hyp_angle = 32'h020AFCA2;  2: get_hyp_angle = 32'h01014904;
            3: get_hyp_angle = 32'h00802A8C;  4: get_hyp_angle = 32'h00802A8C;  5: get_hyp_angle = 32'h00400547;
            6: get_hyp_angle = 32'h002000B2;  7: get_hyp_angle = 32'h00100016;  8: get_hyp_angle = 32'h00080003;
            9: get_hyp_angle = 32'h00040000;  10:get_hyp_angle = 32'h00020000;  11:get_hyp_angle = 32'h00010000;
            12:get_hyp_angle = 32'h00008000;  13:get_hyp_angle = 32'h00004000;  14:get_hyp_angle = 32'h00004000;
            15:get_hyp_angle = 32'h00002000;  16:get_hyp_angle = 32'h00001000;  17:get_hyp_angle = 32'h00000800;
            18:get_hyp_angle = 32'h00000400;  19:get_hyp_angle = 32'h00000200;  20:get_hyp_angle = 32'h00000100;
            21:get_hyp_angle = 32'h00000080;  22:get_hyp_angle = 32'h00000040;  23:get_hyp_angle = 32'h00000020;
            24:get_hyp_angle = 32'h00000010;  25:get_hyp_angle = 32'h00000008;  26:get_hyp_angle = 32'h00000004;
            27:get_hyp_angle = 32'h00000002;  28:get_hyp_angle = 32'h00000001;  default: get_hyp_angle = 32'h00000000;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Stage-0 pre-processing (combinational): quadrant folding + gain
    // pre-scaling. Result is loaded into pipeline register 0.
    // -------------------------------------------------------------------------
    reg signed [31:0] x_pre, y_pre, z_pre;

    always @* begin
        if (coord_mode == 1'b0) begin
            // ---- Circular ----
            if (op_mode == 1'b0) begin
                // Rotation: fold z_in into [-90deg, +90deg]
                if (z_in > PI_HALF_Q427) begin
                    z_pre = z_in - PI_Q427;
                    x_pre = -x_in;
                    y_pre = -y_in;
                end else if (z_in < -PI_HALF_Q427) begin
                    z_pre = z_in + PI_Q427;
                    x_pre = -x_in;
                    y_pre = -y_in;
                end else begin
                    z_pre = z_in;
                    x_pre = x_in;
                    y_pre = y_in;
                end
            end else begin
                // Vectoring: fold so effective x0 > 0 (gives atan2-style range)
                if (x_in < 0) begin
                    x_pre = -x_in;
                    y_pre = -y_in;
                    z_pre = (y_in >= 0) ? (z_in + PI_Q427) : (z_in - PI_Q427);
                end else begin
                    x_pre = x_in;
                    y_pre = y_in;
                    z_pre = z_in;
                end
            end
        end else begin
            // ---- Hyperbolic ----
            // No folding trick exists for hyperbolic functions; valid domain
            // is |z_in| < ~1.118 rad by construction of the algorithm.
            x_pre = x_in;
            y_pre = y_in;
            z_pre = z_in;
        end
    end

    wire signed [31:0] k_inv_sel  = (coord_mode == 1'b0) ? K_CIRC_INV_Q427 : K_HYP_INV_Q427;
    wire signed [31:0] x_scaled   = q427_mul(x_pre, k_inv_sel);
    wire signed [31:0] y_scaled   = q427_mul(y_pre, k_inv_sel);

    // -------------------------------------------------------------------------
    // Pipeline registers, stage 0 .. STAGES
    // -------------------------------------------------------------------------
    reg signed [31:0] x [0:STAGES];
    reg signed [31:0] y [0:STAGES];
    reg signed [31:0] z [0:STAGES];
    reg                valid  [0:STAGES];
    reg                c_mode [0:STAGES];
    reg                o_mode [0:STAGES];

    always @(posedge clk) begin
        if (rst) begin
            valid[0] <= 0; c_mode[0] <= 0; o_mode[0] <= 0;
            x[0] <= 0; y[0] <= 0; z[0] <= 0;
        end else begin
            valid[0]  <= valid_in;
            c_mode[0] <= coord_mode;
            o_mode[0] <= op_mode;
            // gain-precompensated, quadrant-folded inputs go in here
            x[0] <= x_scaled;
            y[0] <= y_scaled;
            z[0] <= z_pre;
        end
    end

    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : CORDIC_STAGES
            wire [4:0]  c_s = get_circ_shift(i);
            wire [4:0]  h_s = get_hyp_shift(i);
            wire [31:0] c_a = get_circ_angle(i);
            wire [31:0] h_a = get_hyp_angle(i);

            wire signed [31:0] xi = x[i];
            wire signed [31:0] yi = y[i];
            wire signed [31:0] zi = z[i];

            wire [4:0]  shift_val = (c_mode[i] == 0) ? c_s : h_s;
            wire [31:0] angle_val = (c_mode[i] == 0) ? c_a : h_a;

            wire signed [31:0] x_shift = xi >>> shift_val;
            wire signed [31:0] y_shift = yi >>> shift_val;

            // Rotation direction ("sigma" in standard CORDIC notation, +-1):
            //   Rotation mode  : sigma = +1 while z has not reached zero yet,
            //                    i.e. sigma = sign(z)  -> drives z_i -> 0
            //   Vectoring mode : sigma = -1 while y has not reached zero yet,
            //                    i.e. sigma = -sign(y) -> drives y_i -> 0
            // sigma is encoded here as a single bit: sigma_pos = 1 means
            // sigma = +1, sigma_pos = 0 means sigma = -1.
            wire z_nonneg  = ~zi[31];              // 1 if z_i >= 0
            wire y_neg     = yi[31];               // 1 if y_i <  0
            wire sigma_pos = (o_mode[i] == 1'b0) ? z_nonneg : y_neg;

            always @(posedge clk) begin
                if (rst) begin
                    valid[i+1] <= 0; c_mode[i+1] <= 0; o_mode[i+1] <= 0;
                    x[i+1] <= 0; y[i+1] <= 0; z[i+1] <= 0;
                end else begin
                    valid[i+1]  <= valid[i];
                    c_mode[i+1] <= c_mode[i];
                    o_mode[i+1] <= o_mode[i];

                    if (c_mode[i] == 0) begin
                        // Circular: x' = x -/+ sigma*y>>i, y' = y +/- sigma*x>>i, z' = z -+ sigma*angle
                        if (sigma_pos) begin
                            x[i+1] <= sat_add(xi, -y_shift);
                            y[i+1] <= sat_add(yi,  x_shift);
                            z[i+1] <= sat_add(zi, -angle_val);
                        end else begin
                            x[i+1] <= sat_add(xi,  y_shift);
                            y[i+1] <= sat_add(yi, -x_shift);
                            z[i+1] <= sat_add(zi,  angle_val);
                        end
                    end else begin
                        // Hyperbolic: x' = x +/- sigma*y>>i, y' = y +/- sigma*x>>i, z' = z -+ sigma*angle
                        if (sigma_pos) begin
                            x[i+1] <= sat_add(xi,  y_shift);
                            y[i+1] <= sat_add(yi,  x_shift);
                            z[i+1] <= sat_add(zi, -angle_val);
                        end else begin
                            x[i+1] <= sat_add(xi, -y_shift);
                            y[i+1] <= sat_add(yi, -x_shift);
                            z[i+1] <= sat_add(zi,  angle_val);
                        end
                    end
                end
            end
        end
    endgenerate

    assign valid_out = valid[STAGES];
    assign x_out     = x[STAGES];
    assign y_out     = y[STAGES];
    assign z_out     = z[STAGES];

endmodule