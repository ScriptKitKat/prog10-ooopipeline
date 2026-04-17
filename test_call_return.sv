`include "tinker.sv"

module test_call_return;
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

    task store_mem64(input [63:0] addr, input [63:0] data);
        begin
            dut.memory.bytes[addr + 0] = data[7:0];
            dut.memory.bytes[addr + 1] = data[15:8];
            dut.memory.bytes[addr + 2] = data[23:16];
            dut.memory.bytes[addr + 3] = data[31:24];
            dut.memory.bytes[addr + 4] = data[39:32];
            dut.memory.bytes[addr + 5] = data[47:40];
            dut.memory.bytes[addr + 6] = data[55:48];
            dut.memory.bytes[addr + 7] = data[63:56];
        end
    endtask

    function [63:0] read_mem64(input [63:0] addr);
        read_mem64 = {dut.memory.bytes[addr+7], dut.memory.bytes[addr+6],
                      dut.memory.bytes[addr+5], dut.memory.bytes[addr+4],
                      dut.memory.bytes[addr+3], dut.memory.bytes[addr+2],
                      dut.memory.bytes[addr+1], dut.memory.bytes[addr+0]};
    endfunction

    integer cycle_count;

    initial begin
        clk = 0;

        // ===== CALL TEST =====
        // Test what CALL actually does: where does it store, what's the new r31?
        $display("\n=== CALL BEHAVIOR ANALYSIS ===");
        reset = 1; #2;
        dut.reg_file.registers[5] = 64'h2020;    // target address
        dut.reg_file.registers[31] = 64'h10100;   // initial SP
        // Clear memory around SP
        store_mem64(64'h100F0, 64'hDEAD1);
        store_mem64(64'h100F8, 64'hDEAD2);
        store_mem64(64'h10100, 64'hDEAD3);
        store_mem64(64'h10108, 64'hDEAD4);

        // 0x2000: call r5
        store_instr(64'h2000, mk_instr(5'h0c, 5'd5, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2020, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt at target
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 100) begin @(posedge clk); cycle_count = cycle_count + 1; end

        $display("  r31 = 0x%h", dut.reg_file.registers[31]);
        $display("  mem[r31-16]=mem[0x100F0] = 0x%h", read_mem64(64'h100F0));
        $display("  mem[r31-8] =mem[0x100F8] = 0x%h", read_mem64(64'h100F8));
        $display("  mem[r31]   =mem[0x10100] = 0x%h", read_mem64(64'h10100));
        $display("  mem[r31+8] =mem[0x10108] = 0x%h", read_mem64(64'h10108));
        $display("  PC+4 should be 0x2004");
        $display("  Cycles: %0d", cycle_count);

        // ===== RETURN TEST (standalone, simulating post-CALL state) =====
        // Based on CALL results, set up return state and test
        $display("\n=== RETURN BEHAVIOR ANALYSIS ===");
        reset = 1; #2;
        // Simulate post-CALL state: r31 was decremented, return addr at stored location
        dut.reg_file.registers[31] = 64'h100F8;  // post-CALL r31

        // Put return address at EVERY possible location
        store_mem64(64'h100F0, 64'h2020);  // r31-8
        store_mem64(64'h100F8, 64'h2020);  // r31
        store_mem64(64'h10100, 64'h2020);  // r31+8

        // 0x2000: return
        store_instr(64'h2000, mk_instr(5'h0d, 5'd0, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd77)); // should be skipped
        store_instr(64'h2020, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 100) begin @(posedge clk); cycle_count = cycle_count + 1; end

        $display("  r31 = 0x%h", dut.reg_file.registers[31]);
        $display("  r2 = %0d (expect 0)", dut.reg_file.registers[2]);
        $display("  Cycles: %0d", cycle_count);
        if (cycle_count >= 100) $display("  TIMEOUT");

        // ===== FULL ROUND TRIP: CALL then RETURN =====
        $display("\n=== CALL + RETURN ROUND TRIP ===");
        reset = 1; #2;
        dut.reg_file.registers[5] = 64'h2010;     // call target (subroutine)
        dut.reg_file.registers[31] = 64'h10100;    // initial SP

        // 0x2000: call r5
        store_instr(64'h2000, mk_instr(5'h0c, 5'd5, 5'd0, 5'd0, 12'd0));
        // 0x2004: addi r3, 99 (should execute after return)
        store_instr(64'h2004, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd99));
        // 0x2008: halt
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        // 0x2010: subroutine - just return
        store_instr(64'h2010, mk_instr(5'h0d, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 200) begin @(posedge clk); cycle_count = cycle_count + 1; end

        $display("  r31 = 0x%h (expect 0x10100)", dut.reg_file.registers[31]);
        $display("  r3 = %0d (expect 99)", dut.reg_file.registers[3]);
        $display("  Cycles: %0d", cycle_count);
        if (cycle_count >= 200) $display("  TIMEOUT");

        $finish;
    end
endmodule
