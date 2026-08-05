`timescale 1ns / 1ps

module cordic_unified (
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire coord_mode,  // 0: Circular, 1: Hyperbolic
    input wire op_mode,     // 0: Rotation, 1: Vectoring
    input wire signed [31:0] x_in,
    input wire signed [31:0] y_in,
    input wire signed [31:0] z_in,
    output wire valid_out,
    output wire signed [31:0] x_out,
    output wire signed [31:0] y_out,
    output wire signed [31:0] z_out
);

    // -------------------------------------------------------------------------
    // Flawless Q4.27 Shifts and Angles (1.0 Radians = 134217728 = 0x08000000)
    // -------------------------------------------------------------------------
    function [4:0] get_circ_shift(input integer i);
        get_circ_shift = (i > 31) ? 31 : i;
    endfunction

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
            27:get_circ_angle = 32'h00000001;  default: get_circ_angle = 32'h00000000;
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
    // 35 Pipeline Registers (Stage 0 to 34)
    // -------------------------------------------------------------------------
    reg signed [31:0] x [0:34];
    reg signed [31:0] y [0:34];
    reg signed [31:0] z [0:34];
    reg valid [0:34];
    reg c_mode [0:34];
    reg o_mode [0:34];

    always @(posedge clk) begin
        if (rst) begin
            valid[0] <= 0; c_mode[0] <= 0; o_mode[0] <= 0;
            x[0] <= 0; y[0] <= 0; z[0] <= 0;
        end else begin
            valid[0] <= valid_in; c_mode[0] <= coord_mode; o_mode[0] <= op_mode;
            x[0] <= x_in; y[0] <= y_in; z[0] <= z_in;
        end
    end

    genvar i;
    generate
        for (i = 0; i < 34; i = i + 1) begin : CORDIC_STAGES
            wire [4:0] c_s = get_circ_shift(i);
            wire [4:0] h_s = get_hyp_shift(i);
            wire [31:0] c_a = get_circ_angle(i);
            wire [31:0] h_a = get_hyp_angle(i);
            
            wire signed [31:0] xi = x[i];
            wire signed [31:0] yi = y[i];
            wire signed [31:0] zi = z[i];
            
            wire [4:0] shift_val = (c_mode[i] == 0) ? c_s : h_s;
            wire [31:0] angle_val = (c_mode[i] == 0) ? c_a : h_a;
            
            wire signed [31:0] x_shift = xi >>> shift_val;
            wire signed [31:0] y_shift = yi >>> shift_val;

            wire z_sign = zi[31];
            wire y_sign = yi[31];
            wire d_dir = (o_mode[i] == 0) ? (~z_sign) : (y_sign);

            always @(posedge clk) begin
                if (rst) begin
                    valid[i+1] <= 0; c_mode[i+1] <= 0; o_mode[i+1] <= 0;
                    x[i+1] <= 0; y[i+1] <= 0; z[i+1] <= 0;
                end else begin
                    valid[i+1] <= valid[i];
                    c_mode[i+1] <= c_mode[i];
                    o_mode[i+1] <= o_mode[i];
                    
                    if (c_mode[i] == 0) begin // Circular
                        if (d_dir) begin
                            x[i+1] <= xi - y_shift; y[i+1] <= yi + x_shift; z[i+1] <= zi - angle_val;
                        end else begin
                            x[i+1] <= xi + y_shift; y[i+1] <= yi - x_shift; z[i+1] <= zi + angle_val;
                        end
                    end else begin // Hyperbolic
                        if (d_dir) begin
                            x[i+1] <= xi + y_shift; y[i+1] <= yi + x_shift; z[i+1] <= zi - angle_val;
                        end else begin 
                            x[i+1] <= xi - y_shift; y[i+1] <= yi - x_shift; z[i+1] <= zi + angle_val;
                        end
                    end
                end
            end
        end
    endgenerate

    assign valid_out = valid[34];
    assign x_out     = x[34];
    assign y_out     = y[34];
    assign z_out     = z[34];

endmodule