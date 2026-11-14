`default_nettype none
// Round-robin ownership lasts for a whole Modbus request/response transaction,
// including quiet time, timeout and retries. DE alone is not an ownership signal.
module rs485_transaction_arbiter #(parameter integer N=2)(
    input wire clk, rst_n,
    input wire [N-1:0] request, busy, txd, de,
    input wire uart_rxd,
    output wire [N-1:0] grant, rxd,
    output wire uart_txd, rs485_de
);
    function integer owner_width;
        input integer count;
        integer remaining;
        begin
            owner_width=0;
            for(remaining=count-1;remaining>0;remaining=remaining>>1)
                owner_width=owner_width+1;
            if(owner_width==0)owner_width=1;
        end
    endfunction
    localparam W=owner_width(N);
    reg owned;
    reg [W-1:0] owner,prefer,candidate;
    integer k,index;
    reg found;
    assign grant = !rst_n || !owned ? {N{1'b0}} : ({{(N-1){1'b0}},1'b1} << owner);
    assign uart_txd = !owned || !rst_n ? 1'b1 : txd[owner];
    assign rs485_de = owned && rst_n && de[owner];
    // Both masters may observe idle-line activity; only the granted master can
    // accept a request, so the waiting driver's silence counters remain honest.
    assign rxd = {N{uart_rxd}};
    always @* begin
        candidate=0;found=0;index=0;
        for(k=0;k<N;k=k+1)begin
            index=prefer+k;
            if(index>=N)index=index-N;
            if(!found && request[index])begin candidate=index;found=1;end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin owned<=0; owner<=0; prefer<=0; end
        else if (owned) begin
            if (!busy[owner] && !request[owner] && !de[owner]) begin
                owned<=0; prefer<=owner==N-1 ? 0 : owner+1;
            end
        end else if(found)begin owned<=1;owner<=candidate;end
    end
endmodule
`default_nettype wire
