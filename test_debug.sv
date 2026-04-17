`include "tinker.sv"

module test_debug;
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

        // ===== TEST MOVI =====
        $display("\n=== MOVI DEBUG ===");
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'hDEAD_BEEF_CAFE_BABE;
        // movi r1, 5
        store_instr(64'h2000, mk_instr(5'h12, 5'd1, 5'd0, 5'd0, 12'd5));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 100) begin @(posedge clk); cycle_count = cycle_count + 1; end
        $display("  r1 = 0x%016h", dut.reg_file.registers[1]);
        $display("  Expected {5, rd[51:0]} = 0x%016h", {12'd5, 52'hDEAD_BEEF_CAFE_BABE & 52'hFFFFFFFFFFFFF});
        $display("  Expected {5, 52'd0}    = 0x%016h", {12'd5, 52'd0});
        $display("  Expected sign_ext(5)   = 0x%016h", 64'd5);

        // ===== TEST CALL =====
        $display("\n=== CALL DEBUG ===");
        reset = 1; #2;
        dut.reg_file.registers[5] = 64'h2020;    // target
        dut.reg_file.registers[31] = 64'h10100;   // stack pointer
        // call r5 (opcode 0x0c, rd=5)
        store_instr(64'h2000, mk_instr(5'h0c, 5'd5, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd77)); // addi r2, 77 (should be skipped)
        store_instr(64'h2020, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt at target
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 100) begin @(posedge clk); cycle_count = cycle_count + 1; end
        $display("  Cycles: %0d", cycle_count);
        $display("  r31 = 0x%h (expect 0x100F8 = r31-8)", dut.reg_file.registers[31]);
        $display("  r2 = %0d (expect 0 - call should skip addi)", dut.reg_file.registers[2]);
        $display("  mem[0x100F8] = 0x%h (expect 0x2004 = PC+4)", read_mem64(64'h100F8));
        $display("  mem[0x10100] = 0x%h (check if stored at r31 instead)", read_mem64(64'h10100));

        // ===== TEST RETURN =====
        $display("\n=== RETURN DEBUG ===");
        reset = 1; #2;
        dut.reg_file.registers[31] = 64'h100F8;  // SP after a call
        // Store return address at various potential locations
        store_mem64(64'h100F8, 64'h2020);  // at r31
        store_mem64(64'h10100, 64'h2020);  // at r31+8
        store_mem64(64'h100F0, 64'h2020);  // at r31-8
        // return (opcode 0x0d)
        store_instr(64'h2000, mk_instr(5'h0d, 5'd0, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd77)); // addi r2, 77 (should be skipped)
        store_instr(64'h2020, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt at return target
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 100) begin @(posedge clk); cycle_count = cycle_count + 1; end
        $display("  Cycles: %0d", cycle_count);
        $display("  r31 = 0x%h", dut.reg_file.registers[31]);
        $display("  r2 = %0d (expect 0 - return should skip addi)", dut.reg_file.registers[2]);
        if (cycle_count >= 100) $display("  TIMEOUT - return didn't reach halt");

        // ===== TEST CALL+RETURN round trip =====
        $display("\n=== CALL+RETURN ROUND TRIP ===");
        reset = 1; #2;
        dut.reg_file.registers[5] = 64'h2010;     // call target
        dut.reg_file.registers[31] = 64'h10100;    // stack pointer
        // 0x2000: call r5 -> should jump to 0x2010, store return addr
        store_instr(64'h2000, mk_instr(5'h0c, 5'd5, 5'd0, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd99)); // addi r3, 99 (return target - should execute)
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt after return
        // 0x2010: subroutine - return
        store_instr(64'h2010, mk_instr(5'h0d, 5'd0, 5'd0, 5'd0, 12'd0));
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 200) begin @(posedge clk); cycle_count = cycle_count + 1; end
        $display("  Cycles: %0d", cycle_count);
        $display("  r31 = 0x%h (expect 0x10100 - restored)", dut.reg_file.registers[31]);
        $display("  r3 = %0d (expect 99 - should execute after return)", dut.reg_file.registers[3]);
        if (cycle_count >= 200) $display("  TIMEOUT");

        $finish;
    end
endmodule
