`include "tinker.sv"

module test_cdb_arbiter_rr;
    reg clk, rst;
    reg alu0_valid, fpu0_valid, lsu0_valid;
    reg [6:0] alu0_tag, fpu0_tag, lsu0_tag;
    reg [63:0] alu0_value, fpu0_value, lsu0_value;
    reg [4:0] alu0_rob, fpu0_rob, lsu0_rob;
    reg [2:0] alu0_epoch, fpu0_epoch, lsu0_epoch;
    reg alu1_valid, fpu1_valid, lsu1_valid;
    reg [6:0] alu1_tag, fpu1_tag, lsu1_tag;
    reg [63:0] alu1_value, fpu1_value, lsu1_value;
    reg [4:0] alu1_rob, fpu1_rob, lsu1_rob;
    reg [2:0] alu1_epoch, fpu1_epoch;

    wire cdb0_valid, cdb1_valid;
    wire [6:0] cdb0_tag, cdb1_tag;
    wire [63:0] cdb0_value, cdb1_value;
    wire [4:0] cdb0_rob, cdb1_rob;
    wire [2:0] cdb0_epoch, cdb1_epoch;
    wire alu0_stall, fpu0_stall, lsu0_stall;
    wire alu1_stall, fpu1_stall, lsu1_stall;

    integer cyc;
    integer saw_alu0;
    integer saw_lsu0;

    cdb_arbiter dut(
        .clk(clk),
        .rst(rst),
        .alu0_valid(alu0_valid),
        .alu0_tag(alu0_tag),
        .alu0_value(alu0_value),
        .alu0_rob(alu0_rob),
        .alu0_epoch(alu0_epoch),
        .fpu0_valid(fpu0_valid),
        .fpu0_tag(fpu0_tag),
        .fpu0_value(fpu0_value),
        .fpu0_rob(fpu0_rob),
        .fpu0_epoch(fpu0_epoch),
        .lsu0_valid(lsu0_valid),
        .lsu0_tag(lsu0_tag),
        .lsu0_value(lsu0_value),
        .lsu0_rob(lsu0_rob),
        .lsu0_epoch(lsu0_epoch),
        .alu1_valid(alu1_valid),
        .alu1_tag(alu1_tag),
        .alu1_value(alu1_value),
        .alu1_rob(alu1_rob),
        .alu1_epoch(alu1_epoch),
        .fpu1_valid(fpu1_valid),
        .fpu1_tag(fpu1_tag),
        .fpu1_value(fpu1_value),
        .fpu1_rob(fpu1_rob),
        .fpu1_epoch(fpu1_epoch),
        .lsu1_valid(lsu1_valid),
        .lsu1_tag(lsu1_tag),
        .lsu1_value(lsu1_value),
        .lsu1_rob(lsu1_rob),
        .cdb0_valid(cdb0_valid),
        .cdb0_tag(cdb0_tag),
        .cdb0_value(cdb0_value),
        .cdb0_rob(cdb0_rob),
        .cdb0_epoch(cdb0_epoch),
        .cdb1_valid(cdb1_valid),
        .cdb1_tag(cdb1_tag),
        .cdb1_value(cdb1_value),
        .cdb1_rob(cdb1_rob),
        .cdb1_epoch(cdb1_epoch),
        .alu0_stall(alu0_stall),
        .fpu0_stall(fpu0_stall),
        .lsu0_stall(lsu0_stall),
        .alu1_stall(alu1_stall),
        .fpu1_stall(fpu1_stall),
        .lsu1_stall(lsu1_stall)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        alu0_valid = 0; fpu0_valid = 0; lsu0_valid = 0;
        alu1_valid = 0; fpu1_valid = 0; lsu1_valid = 0;
        alu0_tag = 7'd1; fpu0_tag = 7'd2; lsu0_tag = 7'd3;
        alu0_value = 64'hA0; fpu0_value = 64'hB0; lsu0_value = 64'hC0;
        alu0_rob = 5'd3; fpu0_rob = 5'd4; lsu0_rob = 5'd5;
        alu0_epoch = 3'd0; fpu0_epoch = 3'd0; lsu0_epoch = 3'd0;
        alu1_tag = 7'd0; fpu1_tag = 7'd0; lsu1_tag = 7'd0;
        alu1_value = 64'd0; fpu1_value = 64'd0; lsu1_value = 64'd0;
        alu1_rob = 5'd0; fpu1_rob = 5'd0; lsu1_rob = 5'd0;
        alu1_epoch = 3'd0; fpu1_epoch = 3'd0;
        saw_alu0 = 0;
        saw_lsu0 = 0;

        @(posedge clk);
        rst = 0;

        // Constant contention on bus0: both ALU0 and LSU0 valid every cycle.
        alu0_valid = 1;
        lsu0_valid = 1;

        for (cyc = 0; cyc < 8; cyc = cyc + 1) begin
            @(posedge clk);
            if (cdb0_valid && cdb0_rob == alu0_rob) saw_alu0 = 1;
            if (cdb0_valid && cdb0_rob == lsu0_rob) saw_lsu0 = 1;
        end

        if (!saw_alu0 || !saw_lsu0) begin
            $display("FAIL rr bus0 starvation: saw_alu0=%0d saw_lsu0=%0d", saw_alu0, saw_lsu0);
            $finish(1);
        end

        $display("PASS rr bus0 fairness");
        $finish;
    end
endmodule
