`include "tinker.sv"

module test_memory_perf;
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

    task run_case(input [80*8:1] name);
        integer cycle_count;
        begin
            #8 reset = 0;
            cycle_count = 0;
            while (!hlt && cycle_count < 200) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            $display("%0s cycles=%0d hlt=%b", name, cycle_count, hlt);
        end
    endtask

    initial begin
        clk = 0;

        // Case 1: four independent loads should stream through the LQ.
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'h3000;
        store_mem64(64'h3000, 64'd11);
        store_mem64(64'h3008, 64'd22);
        store_mem64(64'h3010, 64'd33);
        store_mem64(64'h3018, 64'd44);
        store_instr(64'h2000, mk_instr(5'h10, 5'd2, 5'd1, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h10, 5'd3, 5'd1, 5'd0, 12'd8));
        store_instr(64'h2008, mk_instr(5'h10, 5'd4, 5'd1, 5'd0, 12'd16));
        store_instr(64'h200c, mk_instr(5'h10, 5'd5, 5'd1, 5'd0, 12'd24));
        store_instr(64'h2010, mk_instr(5'h18, 5'd6, 5'd2, 5'd3, 12'd0));
        store_instr(64'h2014, mk_instr(5'h18, 5'd7, 5'd4, 5'd5, 12'd0));
        store_instr(64'h2018, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_case("independent_loads");
        if (dut.reg_file.registers[6] === 64'd33 && dut.reg_file.registers[7] === 64'd77)
            $display("PASS independent_loads");
        else
            $display("FAIL independent_loads r6=%0d r7=%0d", dut.reg_file.registers[6], dut.reg_file.registers[7]);

        // Case 2: load must forward from an older store before it writes memory.
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd99;
        dut.reg_file.registers[2] = 64'h3100;
        store_mem64(64'h3100, 64'd1);
        store_instr(64'h2000, mk_instr(5'h13, 5'd2, 5'd1, 5'd0, 12'd0));
        store_instr(64'h2004, mk_instr(5'h10, 5'd3, 5'd2, 5'd0, 12'd0));
        store_instr(64'h2008, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd1));
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_case("store_forward_load");
        if (dut.reg_file.registers[3] === 64'd100)
            $display("PASS store_forward_load");
        else
            $display("FAIL store_forward_load r3=%0d", dut.reg_file.registers[3]);

        // Case 3: load base is produced by an ALU op just before the load.
        reset = 1; #2;
        dut.reg_file.registers[2] = 64'h3200;
        store_mem64(64'h3208, 64'd1234);
        store_instr(64'h2000, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd8));  // r2 += 8
        store_instr(64'h2004, mk_instr(5'h10, 5'd3, 5'd2, 5'd0, 12'd0));  // load [r2]
        store_instr(64'h2008, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd1));  // r3 += 1
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        run_case("computed_base_load");
        if (dut.reg_file.registers[3] === 64'd1235)
            $display("PASS computed_base_load");
        else
            $display("FAIL computed_base_load r3=%0d", dut.reg_file.registers[3]);

        $finish;
    end
endmodule
