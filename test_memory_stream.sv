`include "tinker.sv"

module test_memory_stream;
    reg clk, reset;
    wire hlt;
    integer cycle_count;
    integer i;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    function [31:0] mk_instr(input [4:0] op, input [4:0] rd,
                             input [4:0] rs, input [4:0] rt, input [11:0] L);
        mk_instr = {op, rd, rs, rt, L};
    endfunction

    task clear_mem(input [63:0] lo, input [63:0] hi);
        begin
            for (i = lo; i < hi; i = i + 1)
                dut.memory.bytes[i] = 8'h0;
        end
    endtask

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
        read_mem64 = {dut.memory.bytes[addr + 7], dut.memory.bytes[addr + 6],
                      dut.memory.bytes[addr + 5], dut.memory.bytes[addr + 4],
                      dut.memory.bytes[addr + 3], dut.memory.bytes[addr + 2],
                      dut.memory.bytes[addr + 1], dut.memory.bytes[addr + 0]};
    endfunction

    task run_until_halt(input [80*8:1] name, input integer max_cycles);
        begin
            #8 reset = 0;
            cycle_count = 0;
            while (!hlt && cycle_count < max_cycles) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            $display("%0s cycles=%0d hlt=%b", name, cycle_count, hlt);
        end
    endtask

    initial begin
        clk = 0;

        // Hidden-style streaming copy loop:
        // load value, store it, bump source/dest pointers, decrement count, branch back.
        reset = 1; #2;
        clear_mem(64'h2000, 64'h2100);
        clear_mem(64'h3000, 64'h3100);
        clear_mem(64'h4000, 64'h4100);
        dut.reg_file.registers[1] = 64'h3000;
        dut.reg_file.registers[2] = 64'h4000;
        dut.reg_file.registers[3] = 64'd16;
        dut.reg_file.registers[10] = 64'h2000;
        for (i = 0; i < 16; i = i + 1)
            store_mem64(64'h3000 + i * 8, 64'd100 + i);
        store_instr(64'h2000, mk_instr(5'h10, 5'd5, 5'd1, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h13, 5'd2, 5'd5, 5'd0, 12'd0));
        store_instr(64'h2008, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd8));
        store_instr(64'h200c, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd8));
        store_instr(64'h2010, mk_instr(5'h1b, 5'd3, 5'd0, 5'd0, 12'd1));
        store_instr(64'h2014, mk_instr(5'h0b, 5'd10, 5'd3, 5'd0, 12'd0));
        store_instr(64'h2018, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_until_halt("copy_loop", 2000);
        if (hlt && dut.reg_file.registers[3] === 64'd0 &&
            read_mem64(64'h4000) === 64'd100 &&
            read_mem64(64'h4078) === 64'd115)
            $display("PASS copy_loop");
        else
            $display("FAIL copy_loop r3=%0d first=%0d last=%0d",
                     dut.reg_file.registers[3], read_mem64(64'h4000), read_mem64(64'h4078));

        // Exit-mispredict with older loads in flight. A taken-biased BRNZ predicts the
        // final not-taken exit incorrectly; older loads must still complete and retire.
        reset = 1; #2;
        clear_mem(64'h2000, 64'h2100);
        clear_mem(64'h3200, 64'h3300);
        dut.reg_file.registers[1] = 64'h3200;
        dut.reg_file.registers[2] = 64'h2000;
        dut.reg_file.registers[3] = 64'd1;
        for (i = 0; i < 8; i = i + 1)
            store_mem64(64'h3200 + i * 8, 64'd200 + i);
        store_instr(64'h2000, mk_instr(5'h10, 5'd11, 5'd1, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h10, 5'd12, 5'd1, 5'd0, 12'd8));
        store_instr(64'h2008, mk_instr(5'h10, 5'd13, 5'd1, 5'd0, 12'd16));
        store_instr(64'h200c, mk_instr(5'h10, 5'd14, 5'd1, 5'd0, 12'd24));
        store_instr(64'h2010, mk_instr(5'h1b, 5'd3, 5'd0, 5'd0, 12'd1));
        store_instr(64'h2014, mk_instr(5'h0b, 5'd2, 5'd3, 5'd0, 12'd0));
        store_instr(64'h2018, mk_instr(5'h18, 5'd15, 5'd11, 5'd14, 12'd0));
        store_instr(64'h201c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_until_halt("exit_mispredict_older_loads", 2000);
        if (hlt && dut.reg_file.registers[15] === 64'd403)
            $display("PASS exit_mispredict_older_loads");
        else
            $display("FAIL exit_mispredict_older_loads r15=%0d", dut.reg_file.registers[15]);

        $finish;
    end
endmodule
