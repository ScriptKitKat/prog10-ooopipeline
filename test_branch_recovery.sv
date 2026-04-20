`include "tinker.sv"

module test_branch_recovery;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    function [31:0] mk_instr(input [4:0] op, input [4:0] rd,
                             input [4:0] rs, input [4:0] rt, input [11:0] L);
        mk_instr = {op, rd, rs, rt, L};
    endfunction

    task store_instr(input [63:0] addr, input [31:0] word);
        begin
            dut.memory.bytes[addr + 0] = word[7:0];
            dut.memory.bytes[addr + 1] = word[15:8];
            dut.memory.bytes[addr + 2] = word[23:16];
            dut.memory.bytes[addr + 3] = word[31:24];
        end
    endtask

    initial begin
        clk = 0;
        reset = 1; #2;

        dut.reg_file.registers[1] = 64'h2008;
        dut.reg_file.registers[2] = 64'h2010;

        // With an older unresolved branch in the ROB, younger non-branch work should still be
        // allowed to flow, but younger control-flow must stay parked until the older branch
        // resolves.
        store_instr(64'h2000, mk_instr(5'h19, 5'd5, 5'd0, 5'd0, 12'd1));    // addi r5, 1
        store_instr(64'h2004, mk_instr(5'h08, 5'd2, 5'd0, 5'd0, 12'd0));    // br r2
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        // First cycle after reset fills the fetch buffer.
        @(posedge clk);

        // Inject an older unresolved branch into the ROB so the fetched branch is blocked.
        dut.rob_inst.head = 5'd0;
        dut.rob_inst.tail = 5'd1;
        dut.rob_inst.count = 6'd1;
        dut.rob_inst.valid[0] = 1'b1;
        dut.rob_inst.itype[0] = 3'd4;
        dut.rob_inst.branch_resolved_flag[0] = 1'b0;
        dut.rob_inst.complete[0] = 1'b0;

        #1;
        if (!dut.rob_has_unresolved_branch) begin
            $display("FAIL branch_recovery setup rob_has_unresolved_branch=%b",
                     dut.rob_has_unresolved_branch);
            $finish;
        end

        if (dut.decode_stall !== 1'b0 || dut.dispatch_valid1 !== 1'b1 || dut.dispatch_valid2 !== 1'b0) begin
            $display("FAIL branch_recovery nonbranch_should_flow decode_stall=%b dispatch_valid1=%b dispatch_valid2=%b",
                     dut.decode_stall, dut.dispatch_valid1, dut.dispatch_valid2);
            $finish;
        end

        @(posedge clk);
        #1;

        if (dut.fu_inst.fb_head !== 4'd1) begin
            $display("FAIL branch_recovery nonbranch_did_not_advance fb_head=%0d",
                     dut.fu_inst.fb_head);
            $finish;
        end

        #1;
        if (dut.dispatch_valid1 !== 1'b0) begin
            $display("FAIL branch_recovery younger_branch_not_blocked dispatch_valid1=%b",
                     dut.dispatch_valid1);
            $finish;
        end

        @(posedge clk);
        #1;

        if (dut.fu_inst.fb_head !== 4'd1) begin
            $display("FAIL branch_recovery younger_branch_dropped fb_head=%0d",
                     dut.fu_inst.fb_head);
        end else begin
            $display("PASS branch_recovery selective_frontend_blocking");
        end

        $finish;
    end
endmodule
