module tb_cache();

reg	clk,rst_n;

initial clk = 1'b0;
always #5 clk = ~clk;

reg [31:0] dram_data[0:64*1024*1024-1];


reg				cpu_cs;
reg				cpu_we;
reg	[31:0]	cpu_addr;
reg	[31:0]	cpu_din;
wire	[31:0]	cpu_dout;
wire				cpu_nwait;


integer i;
initial begin
	rst_n = 1'b1;
	for(i=0;i<64*1024*1024;i=i+1) dram_data[i] = $random;
	#3;
	rst_n = 1'b0;
	#20;
	rst_n = 1'b1;
	cpu_cs = 1'b0;
	
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	
	//first miss
	cpu_cs = 1'b1;
	cpu_we = 1'b0;
	cpu_addr = 32'h00A37B9C;
	while(!cpu_nwait) begin
		@(posedge clk);
		#6;
		cpu_cs = 1'b0;
	end

	@(posedge clk);
	@(posedge clk);
	@(posedge clk);

	
	//hit
	cpu_cs = 1'b1;
	cpu_we = 1'b0;
	cpu_addr = 32'h00A37B9C;
	while(!cpu_nwait) begin
		@(posedge clk);
		#6;
		cpu_cs = 1'b0;
	end

	@(posedge clk);
	@(posedge clk);
	@(posedge clk);

	
	//miss on the same cache line
	cpu_cs = 1'b1;
	cpu_we = 1'b0;
	cpu_addr = 32'h00A3BB98;
	while(!cpu_nwait) begin
		@(posedge clk);
		#6;
		cpu_cs = 1'b0;
	end
	

	@(posedge clk);
	@(posedge clk);
	@(posedge clk);

					
	
	
	//write hit
	cpu_cs = 1'b1;
	cpu_we = 1'b1;
	cpu_addr = 32'h00A3BB90;
	cpu_din = 32'hFFFFFFFF;
	while(!cpu_nwait) begin
		@(posedge clk);
		#6;
		cpu_cs = 1'b0;
	end
	
		

	@(posedge clk);
	@(posedge clk);
	@(posedge clk);


	//miss & write back because of dirty
	cpu_cs = 1'b1;
	cpu_we = 1'b0;
	cpu_addr = 32'h00A37B94;
	while(!cpu_nwait) begin
		@(posedge clk);
		#6;
		cpu_cs = 1'b0;
	end

	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);

	$finish;
end

wire				dram_cs;
wire				dram_we;
wire	[31:0]	dram_addr;
wire	[31:0]	dram_din;
wire	[31:0]	dram_dout;
wire				dram_nwait;

cache cachectrl0(.
						clk(clk),.
						rst_n(rst_n),.
						cpu_cs(cpu_cs),.
						cpu_we(cpu_we),.
						cpu_addr(cpu_addr),.
						cpu_din(cpu_din),.
						cpu_dout(cpu_dout),.
						cpu_nwait(cpu_nwait),.
						dram_cs(dram_cs),.
						dram_we(dram_we),.
						dram_addr(dram_addr),.
						dram_din(dram_din),.
						dram_dout(dram_dout),.
						dram_nwait(dram_nwait)
);


reg	[1:0]		cnt;
reg				dram_we_d;
reg	[31:0]	dram_addr_d;
reg	[31:0]	dram_din_d;

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		cnt	<=	0;
	end
	else begin
		if((dram_cs == 1'b1) || (cnt>0)) begin
			cnt <= cnt+1;
		end
		
		if((dram_cs == 1'b1) || (dram_nwait == 1'b1)) begin
			dram_we_d	<= dram_we;
			dram_addr_d	<= dram_addr;
			dram_din_d	<= dram_din;
		end
		
		if((dram_we_d == 1'b1) && (cnt == 3)) begin
			dram_data[dram_addr_d[31:2]] <= dram_din_d;
		end
	end
end

assign dram_dout = (dram_nwait == 1'b1) ? dram_data[dram_addr_d[31:2]] : 'bx;
assign dram_nwait = (cnt == 0);

endmodule
	