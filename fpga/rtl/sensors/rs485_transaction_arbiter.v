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
    reg owned;
    integer owner,prefer,candidate,k;
    reg found;
    assign grant = !rst_n || !owned ? {N{1'b0}} : ({{(N-1){1'b0}},1'b1} << owner);
    assign uart_txd = !owned || !rst_n ? 1'b1 : txd[owner];
    assign rs485_de = owned && rst_n && de[owner];
    // Both masters may observe idle-line activity; only the granted master can
    // accept a request, so the waiting driver's silence counters remain honest.
    assign rxd = {N{uart_rxd}};
    always @* begin
        candidate=0;found=0;
        for(k=0;k<N;k=k+1)begin
            if(!found && request[(prefer+k)%N])begin candidate=(prefer+k)%N;found=1;end
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
