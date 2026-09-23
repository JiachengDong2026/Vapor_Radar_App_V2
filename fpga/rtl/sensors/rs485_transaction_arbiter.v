`default_nettype none
// Round-robin ownership lasts for a whole Modbus request/response transaction,
// including quiet time, timeout and retries. DE alone is not an ownership signal.
module rs485_transaction_arbiter (
    input wire clk, rst_n,
    input wire [1:0] request, busy, txd, de,
    input wire uart_rxd,
    output wire [1:0] grant, rxd,
    output wire uart_txd, rs485_de
);
    reg owned, owner, prefer;
    assign grant = !rst_n || !owned ? 2'b00 : owner ? 2'b10 : 2'b01;
    assign uart_txd = !owned || !rst_n ? 1'b1 : txd[owner];
    assign rs485_de = owned && rst_n && de[owner];
    // Both masters may observe idle-line activity; only the granted master can
    // accept a request, so the waiting driver's silence counters remain honest.
    assign rxd = {2{uart_rxd}};
    always @(posedge clk) begin
        if (!rst_n) begin owned<=0; owner<=0; prefer<=0; end
        else if (owned) begin
            if (!busy[owner] && !request[owner] && !de[owner]) begin
                owned<=0; prefer<=!owner;
            end
        end else if (request[prefer]) begin owned<=1; owner<=prefer; end
        else if (request[!prefer]) begin owned<=1; owner<=!prefer; end
    end
endmodule
`default_nettype wire
