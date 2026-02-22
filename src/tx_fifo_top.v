module tx_fifo_top (
    input wire iClk,
    input wire iRst,

    //tx input
    input wire iTick16x,

    //fifo input
    input wire iPushValid,
    input wire [7:0] iPushData,
    input wire iPopValid,
    
    //tx
    output wire oTx,
    output wire oBusy,

    //fifo
    output wire oFull,
    output wire [7:0] oPopData,
    output wire oEmpty
);

    //------------
    //instance fifo
    //------------
    Fifo #(
        .P_DATA_WIDTH(8),
        .P_FIFO_DEPTH(16)
    ) u_tx_fifo (
        .iClk(iClk),
        .iRst(iRst),
        .iPush(iPushValid),
        .iPushData(iPushData),
        .oFull(oFull),
        .iPop(iPopValid),
        .oPopData(oPopData),
        .oEmpty(oEmpty)
    );

    //------------
    //instance tx
    //------------
    uart_tx u_uart_tx (
    .iClk(iClk),
    .iRst(iRst),
    .iTick16x(iTick16x),
    .iData(oPopData),
    .iValid(iPopValid),
    .oTx(oTx),
    .oBusy(oBusy)
  );
endmodule