`include "tinker.sv"

module test_branches;
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

    integer cycle_count, pass_count, fail_count;

    task run_and_wait;
        begin
            reset = 0;
            cycle_count = 0;
            while (!hlt && cycle_count < 300) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        pass_count = 0;
        fail_count = 0;

        // === BR rd (unconditional branch to address in rd) ===
        // BR target is in rd register
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'h2008;  // target address
        // br r1 (opcode 0x08)
        store_instr(64'h2000, mk_instr(5'h08, 5'd1, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd99));  // skipped
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));  // halt
        #8; run_and_wait;
        if (cycle_count < 300 && dut.reg_file.registers[2] === 64'd0) begin
            $display("PASS br cycles=%0d", cycle_count); pass_count = pass_count+1;
        end else begin
            $display("FAIL br cycles=%0d r2=%0d", cycle_count, dut.reg_file.registers[2]);
            fail_count = fail_count+1;
        end

        // === BRR L (branch to PC + imm) ===
        reset = 1; #2;
        store_instr(64'h2000, mk_instr(5'h0a, 5'd0, 5'd0, 5'd0, 12'd8));  // brr_L +8
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd99));  // skipped
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));  // halt
        #8; run_and_wait;
        if (cycle_count < 300 && dut.reg_file.registers[2] === 64'd0) begin
            $display("PASS brr_L cycles=%0d", cycle_count); pass_count = pass_count+1;
        end else begin
            $display("FAIL brr_L cycles=%0d r2=%0d", cycle_count, dut.reg_file.registers[2]);
            fail_count = fail_count+1;
        end

        // === BRR reg (branch to PC + rd) ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd8;  // offset
        store_instr(64'h2000, mk_instr(5'h09, 5'd1, 5'd0, 5'd0, 12'd0));  // brr r1
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd99));  // skipped
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));  // halt
        #8; run_and_wait;
        if (cycle_count < 300 && dut.reg_file.registers[2] === 64'd0) begin
            $display("PASS brr_reg cycles=%0d", cycle_count); pass_count = pass_count+1;
        end else begin
            $display("FAIL brr_reg cycles=%0d r2=%0d timeout=%b", cycle_count, dut.reg_file.registers[2], cycle_count>=300);
            fail_count = fail_count+1;
        end

        // === BRNZ rd, rs (branch if rs != 0 to address in rd) ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'h2008;  // target
        dut.reg_file.registers[2] = 64'd1;     // condition (nonzero)
        // brnz r1, r2 (opcode 0x0b, rd=1, rs=2)
        store_instr(64'h2000, mk_instr(5'h0b, 5'd1, 5'd2, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd99));  // skipped
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));  // halt
        #8; run_and_wait;
        if (cycle_count < 300 && dut.reg_file.registers[3] === 64'd0) begin
            $display("PASS brnz cycles=%0d", cycle_count); pass_count = pass_count+1;
        end else begin
            $display("FAIL brnz cycles=%0d r3=%0d timeout=%b", cycle_count, dut.reg_file.registers[3], cycle_count>=300);
            fail_count = fail_count+1;
        end

        // === BRGT rd, rs, rt (branch if rs > rt, target = rd) ===
        reset = 1; #2;
        dut.reg_file.registers[4] = 64'h2008;  // target
        dut.reg_file.registers[1] = 64'd10;    // rs = 10
        dut.reg_file.registers[2] = 64'd5;     // rt = 5
        store_instr(64'h2000, mk_instr(5'h0e, 5'd4, 5'd1, 5'd2, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd99));  // skipped
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));  // halt
        #8; run_and_wait;
        if (cycle_count < 300 && dut.reg_file.registers[3] === 64'd0) begin
            $display("PASS brgt cycles=%0d", cycle_count); pass_count = pass_count+1;
        end else begin
            $display("FAIL brgt cycles=%0d r3=%0d timeout=%b", cycle_count, dut.reg_file.registers[3], cycle_count>=300);
            fail_count = fail_count+1;
        end

        // BRGT should wait for recently-produced target and compare operands.
        reset = 1; #2;
        dut.reg_file.registers[4] = 64'h200c;
        store_instr(64'h2000, mk_instr(5'h19, 5'd4, 5'd0, 5'd0, 12'd8));   // r4 = 0x2014
        store_instr(64'h2004, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd10));  // r1 = 10
        store_instr(64'h2008, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd5));   // r2 = 5
        store_instr(64'h200c, mk_instr(5'h0e, 5'd4, 5'd1, 5'd2, 12'd0));   // brgt r4,r1,r2
        store_instr(64'h2010, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd99));  // skipped
        store_instr(64'h2014, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        #8; run_and_wait;
        if (cycle_count < 300 && dut.reg_file.registers[3] === 64'd0 && dut.reg_file.registers[4] === 64'h2014) begin
            $display("PASS brgt_deps cycles=%0d", cycle_count); pass_count = pass_count+1;
        end else begin
            $display("FAIL brgt_deps cycles=%0d r3=%0d r4=%0d timeout=%b",
                     cycle_count, dut.reg_file.registers[3], dut.reg_file.registers[4], cycle_count>=300);
            fail_count = fail_count+1;
        end

        $display("\n=== Branches: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end
endmodule
