module sram #(
					parameter WIDTH = 8,
					parameter DEPTH = 256*256
				) (
					input									clk,
					input 								cs,
					input 								write_en,
					input		[$clog2(DEPTH)-1:0]	addr,
					input		[WIDTH-1:0]				data_in,
					
					output	[WIDTH-1:0]				data_out
);


reg [WIDTH-1:0]				mem[0:DEPTH-1];
reg [$clog2(DEPTH)-1:0]		r_addr;

always@(posedge clk) begin
	if(cs) begin
	
		if(write_en) begin
			mem[addr] <= data_in;
		end
	
		r_addr <= addr;
		
	end

end

assign data_out = mem[r_addr];

endmodule