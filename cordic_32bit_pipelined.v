`timescale 1ns / 1ps

module cordic_32bit_pipelined (
    input wire clk,
    input wire rst,
    input wire valid_in,
    input wire mode, // 0: Rotation (Sin/Cos), 1: Vectoring (ArcTan/Magnitude)
    input wire signed [31:0] x_in,
    input wire signed [31:0] y_in,
    input wire signed [31:0] z_in,
    output wire valid_out,
    output wire signed [31:0] x_out,
    output wire signed [31:0] y_out,
    output wire signed [31:0] z_out
);

    // CORDIC Angles Table (32-bit, representing degrees where 45 degrees = 2^29)
    // Z is mapped such that 180 degrees = 2^31. Range: [-180, +180)
    wire [31:0] atan_table [0:31];
    assign atan_table[0]  = 32'h20000000; // atan(2^0)  = 45.000 deg
    assign atan_table[1]  = 32'h12E4051E; // atan(2^-1) = 26.565 deg
    assign atan_table[2]  = 32'h09FB385B; // atan(2^-2) = 14.036 deg
    assign atan_table[3]  = 32'h051111D4; // atan(2^-3) = 7.125 deg
    assign atan_table[4]  = 32'h028B0D43; // atan(2^-4) = 3.576 deg
    assign atan_table[5]  = 32'h0145D7E1;
    assign atan_table[6]  = 32'h00A2F61E;
    assign atan_table[7]  = 32'h00517C55;
    assign atan_table[8]  = 32'h0028BE53;
    assign atan_table[9]  = 32'h00145F2E;
    assign atan_table[10] = 32'h000A2F98;
    assign atan_table[11] = 32'h000517CC;
    assign atan_table[12] = 32'h00028BE6;
    assign atan_table[13] = 32'h000145F3;
    assign atan_table[14] = 32'h0000A2FA;
    assign atan_table[15] = 32'h0000517D;
    assign atan_table[16] = 32'h000028BE;
    assign atan_table[17] = 32'h0000145F;
    assign atan_table[18] = 32'h00000A30;
    assign atan_table[19] = 32'h00000517;
    assign atan_table[20] = 32'h0000028B;
    assign atan_table[21] = 32'h00000145;
    assign atan_table[22] = 32'h000000A2;
    assign atan_table[23] = 32'h00000051;
    assign atan_table[24] = 32'h00000028;
    assign atan_table[25] = 32'h00000014;
    assign atan_table[26] = 32'h0000000A;
    assign atan_table[27] = 32'h00000005;
    assign atan_table[28] = 32'h00000002;
    assign atan_table[29] = 32'h00000001;
    assign atan_table[30] = 32'h00000001;
    assign atan_table[31] = 32'h00000000;

    // Pipeline registers for 33 stages (1 input stage + 32 cordic stages)
    reg signed [31:0] x [0:32];
    reg signed [31:0] y [0:32];
    reg signed [31:0] z [0:32];
    reg valid [0:32];
    reg mode_pipe [0:32];

    // Stage 0: Latch inputs
    always @(posedge clk) begin
        if (rst) begin
            valid[0]     <= 1'b0;
            mode_pipe[0] <= 1'b0;
            x[0]         <= 32'd0;
            y[0]         <= 32'd0;
            z[0]         <= 32'd0;
        end else begin
            valid[0]     <= valid_in;
            mode_pipe[0] <= mode;
            x[0]         <= x_in;
            y[0]         <= y_in;
            z[0]         <= z_in;
        end
    end

    // Stages 1 to 32: CORDIC Rotations
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : CORDIC_STAGES
            
            // Determine Rotation Direction 
            // Rotation (mode 0): Drive Z to 0. Vectoring (mode 1): Drive Y to 0.
            wire z_sign = z[i][31];
            wire y_sign = y[i][31];
            
            // d_dir == 1: Rotate CW (- angle), d_dir == 0: Rotate CCW (+ angle)
            wire d_dir = (mode_pipe[i] == 0) ? z_sign : ~y_sign; 
            
            // Arithmetic right shifts
            wire signed [31:0] x_shifted = x[i] >>> i;
            wire signed [31:0] y_shifted = y[i] >>> i;
            
            always @(posedge clk) begin
                if (rst) begin
                    valid[i+1]     <= 1'b0;
                    mode_pipe[i+1] <= 1'b0;
                    x[i+1]         <= 32'd0;
                    y[i+1]         <= 32'd0;
                    z[i+1]         <= 32'd0;
                end else begin
                    valid[i+1]     <= valid[i];
                    mode_pipe[i+1] <= mode_pipe[i];
                    
                    if (d_dir) begin
                        // Rotate CW
                        x[i+1] <= x[i] + y_shifted;
                        y[i+1] <= y[i] - x_shifted;
                        z[i+1] <= z[i] + atan_table[i];
                    end else begin
                        // Rotate CCW
                        x[i+1] <= x[i] - y_shifted;
                        y[i+1] <= y[i] + x_shifted;
                        z[i+1] <= z[i] - atan_table[i];
                    end
                end
            end
        end
    endgenerate

    // Final Outputs 
    // Data exhibits a 33 clock-cycle latency from valid_in to valid_out.
    assign valid_out = valid[32];
    assign x_out     = x[32];
    assign y_out     = y[32];
    assign z_out     = z[32];

endmodule