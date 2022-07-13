module cache (
						input						clk,
						input						rst_n,
						
						input						cpu_cs,
						input						cpu_we,
						input			[31:0]	cpu_addr,
						input			[31:0]	cpu_din,
						output reg	[31:0]	cpu_dout,
						output					cpu_nwait,
						
						output					dram_cs,
						output					dram_we,
						output		[31:0]	dram_addr,
						output		[31:0]	dram_din,
						input			[31:0]	dram_dout,
						input						dram_nwait
);

parameter	IDLE		=	4'b0000;
parameter	READ		=	4'b0001;
parameter	R_WMEM	=	4'b0010;
parameter	R_RMEM	=	4'b0011;
parameter	R_REND	=	4'b0100;
parameter	R_OUT		=	4'b0101;
parameter	WRITE		=	4'b1001;
parameter	W_WMEM	=	4'b1010;
parameter	W_RMEM	=	4'b1011;
parameter	W_REND	=	4'b1100;

reg	[3:0]		state,next;
reg	[1:0]		cnt;
wire				hit,dirty,valid;

			/*FSM*/
	
always@(*) begin
	next = state;
	case(state)
		
		IDLE : begin
			if(cpu_cs) begin
				if(cpu_we) begin
					next = WRITE;
				end
				else begin
					next = READ;
				end
			end
		end
		
		READ : begin	//read -> do not need to wait
			if(hit) begin
				if(cpu_cs) begin
					if(cpu_we) begin
						next = WRITE;
					end
					else begin
						next = READ;
					end
				end
				else begin
					next = IDLE;
				end
			end
			else begin
				if(dirty) begin	//miss -> dirty = 0 ? -> Read // dirty = 1 ? -> Write
					next = R_WMEM;
				end
				else begin
					next = R_RMEM;
				end
			end
		end
		
		R_WMEM : begin
			if((dram_nwait == 1'b1)&&(cnt==3)) begin
				next = R_RMEM;
			end
		end
		
		R_RMEM : begin
			if((dram_nwait == 1'b1)&&(cnt==3)) begin
				next = R_REND;
			end
		end
		
		R_REND : begin
			if(dram_nwait) begin
				next = R_OUT;
			end
		end
		
		R_OUT : begin
			if(cpu_cs) begin
				if(cpu_we) begin
					next = WRITE;
				end
				else begin
					next = READ;
				end
			end
			else begin
				next = IDLE;
			end
		end
		
		WRITE : begin
			if(hit) begin
				next = IDLE;
			end
			else begin
				if(dirty) begin
					next = W_WMEM;
				end
				else begin
					next = W_RMEM;
				end
			end
		end
		
		W_WMEM : begin
			if((dram_nwait == 1'b1) && (cnt == 3)) begin
				next = W_RMEM;
			end
		end
		
		W_RMEM : begin
			if((dram_nwait == 1'b1) && (cnt == 3)) begin
				next = W_REND;
			end
		end
		
		W_REND : begin
			if(dram_nwait == 1'b1) begin
				next = IDLE;
			end
		end
	
	endcase
end

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		state <= IDLE;
		cnt	<= 0;
	end
	else begin
		state <= next;
		/*counting DRAM access*/
		if((state == R_WMEM) || (state == R_RMEM) || (state == W_WMEM) || (state == W_RMEM)) begin
			if(dram_nwait) begin
				cnt	<=	cnt+1;
			end
		end
	end
end


	//* CPU interface  *//

reg		[31:0]	cpu_addr_d;
reg		[31:0]	cpu_din_d;
wire		[145:0]	cache_dout;
reg		[145:0]	cache_line;

/*store signal from CPU interface*/
always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		cpu_addr_d 	<= 'b0;
		cpu_din_d	<= 'b0;
	end
	else begin
		if((cpu_cs == 1'b1) && (cpu_nwait == 1'b1)) begin
			cpu_addr_d	<=	cpu_addr;
			if(cpu_we) begin
				cpu_din_d	<=	cpu_din;
			end
		end
	end
end

assign cpu_nwait = (state == IDLE) || ((state == READ) && (hit == 1'b1)) || (state == R_OUT);

/*cpu_dout : output data in READ -> data read from cache
				 output data in R_OUT -> data fetched from DRAM */
always@(*) begin
	if(state == READ) begin
		case(cpu_addr_d[3:2])
			2'b00: cpu_dout = cache_dout[31:0];
			2'b01: cpu_dout = cache_dout[63:32];
			2'b10: cpu_dout = cache_dout[95:64];
			2'b11: cpu_dout = cache_dout[127:96];
		endcase
	end
	else begin
		case(cpu_addr_d[3:2])
			2'b00: cpu_dout = cache_line[31:0];
			2'b01: cpu_dout = cache_line[63:32];
			2'b10: cpu_dout = cache_line[95:64];
			2'b11: cpu_dout = cache_line[127:96];
		endcase
	end
end


	//* cache interface *//
//read case : new access from CPU	
wire cache_read = ((state == IDLE)&&(cpu_cs == 1'b1)) || ((state==READ)&&(cpu_cs == 1'b1)&&(hit==1'b1))
											|| ((state == R_OUT) && (cpu_cs == 1'b1));
//write case : on WRITE(cpu) / on R_REND(dram)					
wire cache_write = ((state==WRITE)&&(hit==1'b1)) || ((state==R_REND)&&(dram_nwait==1'b1))
											||	((state == W_REND) && (dram_nwait == 1'b1));
wire 		cache_cs = cache_read || cache_write;
wire 		cache_we = cache_write;
wire	[9:0]	cache_addr = (state==IDLE) || (state == READ) || (state == R_OUT) ? cpu_addr[13:4] : cpu_addr_d[13:4];


//tag 18, 4 words
reg		[145:0]	cache_din;

always@(*) begin
	if(state == WRITE) begin
		cache_din[145:0] = cache_dout[145:0];
		//insert write data
		if(cpu_addr_d[3:2] == 2'b00) cache_din[31:0] = cpu_din_d;
		if(cpu_addr_d[3:2] == 2'b01) cache_din[63:32] = cpu_din_d;
		if(cpu_addr_d[3:2] == 2'b10) cache_din[95:64] = cpu_din_d;
		if(cpu_addr_d[3:2] == 2'b11) cache_din[127:96] = cpu_din_d;
	end
	else if(state == R_REND) begin
		cache_din[145:128] = cpu_addr_d[31:14];	//tag
		cache_din[127:96]	= dram_dout;				//last DRAM data
		cache_din[95:0] = cache_line[95:0];			//DRAM data
	end
	else if(state == W_REND) begin
		cache_din[145:128] = cpu_addr_d[31:14];	//tag
		cache_din[127:96]	= dram_dout;				//last DRAM data
		cache_din[95:0] = cache_line[95:0];			//DRAM data
		//insert write data
		if(cpu_addr_d[3:2] == 2'b00) cache_din[31:0] = cpu_din_d;
		if(cpu_addr_d[3:2] == 2'b01) cache_din[63:32] = cpu_din_d;
		if(cpu_addr_d[3:2] == 2'b10) cache_din[95:64] = cpu_din_d;
		if(cpu_addr_d[3:2] == 2'b11) cache_din[127:96] = cpu_din_d;
	end
	else begin
		cache_din = cache_line;
	end
end

sram		#(.
				WIDTH(146),.
				DEPTH(1024)
	) mem0 (.
				clk(clk),.
				cs(cache_cs),.
				write_en(cache_we),.
				addr(cache_addr),.
				data_in(cache_din),.
				data_out(cache_dout)
);
		//* DRAM interface *//
reg		[1023:0]	valids;
reg		[1023:0]	dirtys;

always@(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		cache_line	<=	'b0;
		valids		<=	1024'b0;
		dirtys		<= 1024'b0;
	end
	else begin //keep cache read data
		if(state == READ) begin
			cache_line 	<=	cache_dout;
		end
		else if (state == WRITE) begin
			cache_line	<=	cache_dout;
		end
		//gather DRAM data
		else if ((state == R_RMEM) && (dram_nwait == 1'b1)) begin
			if(cnt==2'b01) cache_line[31:0]	<=	dram_dout;
			if(cnt==2'b10) cache_line[63:32]	<=	dram_dout;
			if(cnt==2'b11) cache_line[95:64]	<=	dram_dout;
		end
		else if((state == R_REND) && (dram_nwait == 1'b1)) begin
			cache_line[127:96] <= dram_dout;
		end
		else if((state==W_RMEM)&& (dram_nwait == 1'b1)) begin
			if(cnt==2'b01) cache_line[31:0]	<=	dram_dout;
			if(cnt==2'b10) cache_line[63:32]	<=	dram_dout;
			if(cnt==2'b11) cache_line[95:64]	<=	dram_dout;
		end
		else if((state == W_REND)&&(dram_nwait==1'b1)) begin
			cache_line[127:96] <= dram_dout;
		end
		
		if((state==WRITE) &&(hit == 1'b1)) begin
			dirtys[cpu_addr_d[13:4]]	<=	1'b1;	//set dirty on write
		end
		else if((state ==R_REND)&&(dram_nwait == 1'b1)) begin
			dirtys[cpu_addr_d[13:4]]	<=	1'b0; //clear dirty for fetched line
		end
		else if((state ==W_REND)&&(dram_nwait == 1'b1)) begin
			dirtys[cpu_addr_d[13:4]]	<=	1'b1;	//set dirty on write
		end
		
		if((state == R_REND)&&(dram_nwait == 1'b1)) begin
			valids[cpu_addr_d[13:4]]	<= 1'b1; //set valid for fetched DRAM line
		end
		else if((state==W_REND)&&(dram_nwait==1'b1)) begin
			valids[cpu_addr_d[13:4]]	<= 1'b1; //set valid for fetched DRAM line
		end
	end
end

assign valid = valids[cpu_addr_d[13:4]];
assign dirty = dirtys[cpu_addr_d[13:4]];
wire 	[17:0]	tag = cache_dout[145:128];
assign hit = (tag == cpu_addr_d[31:14]) && (valid == 1'b1);

wire		dram_read = (state == R_RMEM) || (state == W_RMEM);
wire		dram_write = (state == R_WMEM) || (state == W_WMEM);
assign	dram_cs = dram_read || dram_write;
assign 	dram_we = dram_write;
//read address : neighbor of the read address from CPU
//write address : stored in tag
assign 	dram_addr = (state == R_RMEM) || (state == W_RMEM) ? 
								{cpu_addr_d[31:4],cnt,2'b00} :
								{cache_line[145:128], cpu_addr_d[13:4], cnt, 2'b00};
assign	dram_din = (cnt == 2'b00) ? cache_line[31:0] :
							(cnt == 2'b01) ? cache_line[63:32] :
							(cnt == 2'b10) ? cache_line[95:64] : cache_line[127:96];

endmodule							