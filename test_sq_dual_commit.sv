`include "tinker.sv"

module test_sq_dual_commit;
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

    integer i;
    integer cycle_count;
    integer pc;
    initial begin
        clk = 0;
        reset = 1; #2;

        // Constant store payload + base pointer.
        dut.reg_file.registers[1] = 64'h1122_3344_5566_7788;
        dut.reg_file.registers[2] = 64'h3000;
        dut.reg_file.registers[8] = 64'd0;

        // Repeated {ADDI, STORE} dual-issue pairs.
        // STORE is frequently the second commit in a cycle; if SQ only observes
        // commit slot 1, SQ entries leak and eventually deadlock.
        pc = 'h2000;
        for (i = 0; i < 40; i = i + 1) begin
            // ALU op in slot 1, independent store in slot 2.
            // This pattern should allow dual-commit with store in commit slot 2.
            store_instr(pc + 0, mk_instr(5'h19, 5'd8, 5'd0, 5'd0, 12'd1)); // r8 += 1
            store_instr(pc + 4, mk_instr(5'h13, 5'd2, 5'd1, 5'd0, 12'd0)); // [r2] = r1
            pc = pc + 8;
        end
        store_instr(pc, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // HALT

        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 600) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        if (!hlt) begin
            $display("FAIL timeout cycles=%0d sq_full=%b rob_count=%0d", cycle_count, dut.sq_full, dut.rob_inst.count);
            $finish(1);
        end

        if (dut.sq_full) begin
            $display("FAIL SQ remained full at halt");
            $finish(1);
        end

        $display("PASS cycles=%0d", cycle_count);
        $finish;
    end
endmodule
