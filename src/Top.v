/*
[MODULE_INFO_START]
Name: Top
Role: FPGA Top-Level Module
Summary:
  - Integrates all system components: Clock Gen, UART, Sensors (SR04, DHT11), Watch, and FND Controller
  - Manages internal scaffolding: Reset logic, data paths between modules
  - Connects physical I/O (Buttons, Switches, LEDs, PMODs) to internal logic
  - Instantiates `control_unit` for centralized mode management
[MODULE_INFO_END]
*/

`timescale 1ns / 1ps

module Top (
  input        iClk,
  input        iRst,

  // UART
  input        iRx,
  output       oTx,

  // Switches
  // iSw0: watch mode (0 stopwatch / 1 clock)
  // iSw1: watch display (0 sec:cs / 1 hour:min)
  // iSw2: display source group (0 watch / 1 sensor)
  // iSw3: sensor select when iSw2=1 (0 sr04 / 1 dht11)
  input        iSw0,
  input        iSw1,
  input        iSw2,
  input        iSw3,

  // Buttons
  input        iBtnC,
  input        iBtnU,
  input        iBtnD,
  input        iBtnL,
  input        iBtnR,

  // HC-SR04
  input        iSr04Echo,
  output       oSr04Trig,

  // DHT11 (single-wire data)
  inout        ioDht11Data,

  // FND
  output [3:0] oFndCom,
  output [7:0] oFndFont
);

  // ---------------------------------------------------------------------------
  // 1) Shared clocks
  // ---------------------------------------------------------------------------
  wire wTick100Hz;  // Watch time base tick
  wire wTick1kHz;   // FND scan tick
  wire wTick1us;    // Shared sensor tick (SR04/DHT11)
  wire wTick16x;    // UART oversampling tick

  gen_clk u_gen_clk (
    .iClk(iClk),
    .iRst(iRst),
    .oClk100hz(wTick100Hz),
    .oClk1khz(wTick1kHz),
    .oTick1us(wTick1us)
  );

  baud_rate_gen #(
    .CLK_FREQ(100_000_000),
    .BAUD_RATE(9600)
  ) u_baud_gen (
    .iClk(iClk),
    .iRst(iRst),
    .oTick16x(wTick16x)
  );

  // ---------------------------------------------------------------------------
  // 2) UART RX/TX + FIFO buffering
  // ---------------------------------------------------------------------------
  wire [7:0] wRxData;      // Byte from uart_rx
  wire       wRxValid;     // Byte valid pulse from uart_rx
  wire [7:0] wRxFifoData;  // Decoded command input byte (FIFO output)
  wire       wRxFifoPop;   // Pop strobe to consume one RX byte
  wire       wRxFifoEmpty; // RX FIFO empty flag
  wire       wRxFifoFull;  // RX FIFO full flag

  wire [7:0] wTxData;      // Byte from uart_ascii_sender
  wire       wTxPushValid; // FIFO push-valid pulse from uart_ascii_sender
  wire       wTxBusy;      // uart_tx busy
  wire       wTxPathBusy;  // TX FIFO backpressure (fifo full)
  wire [7:0] wTxFifoData;  // Byte fed to uart_tx
  wire       wTxFifoPop;   // Pop strobe to launch next TX byte
  wire       wTxFifoEmpty; // TX FIFO empty flag
  wire       wTxFifoFull;  // TX FIFO full flag

  uart_rx u_uart_rx (
    .iClk(iClk),
    .iRst(iRst),
    .iTick16x(wTick16x),
    .iRx(iRx),
    .oData(wRxData),
    .oValid(wRxValid)
  );

  Fifo #(
    .P_DATA_WIDTH(8),
    .P_FIFO_DEPTH(16)
  ) u_uart_rx_fifo (
    .iClk(iClk),
    .iRst(iRst),
    // Guard push with full flag to make overflow policy explicit at top level.
    .iPush(wRxValid && !wRxFifoFull),
    .iPushData(wRxData),
    .oFull(wRxFifoFull),
    .iPop(wRxFifoPop),
    .oPopData(wRxFifoData),
    .oEmpty(wRxFifoEmpty)
  );

  assign wRxFifoPop = !wRxFifoEmpty;

  Fifo #(
    .P_DATA_WIDTH(8),
    .P_FIFO_DEPTH(16)
  ) u_uart_tx_fifo (
    .iClk(iClk),
    .iRst(iRst),
    // Guard push with full flag to avoid issuing redundant push requests.
    .iPush(wTxPushValid && !wTxFifoFull),
    .iPushData(wTxData),
    .oFull(wTxFifoFull),
    .iPop(wTxFifoPop),
    .oPopData(wTxFifoData),
    .oEmpty(wTxFifoEmpty)
  );

  assign wTxFifoPop = (!wTxFifoEmpty) && (!wTxBusy);

  uart_tx u_uart_tx (
    .iClk(iClk),
    .iRst(iRst),
    .iTick16x(wTick16x),
    .iData(wTxFifoData),
    .iValid(wTxFifoPop),
    .oTx(oTx),
    .oBusy(wTxBusy)
  );

  // ---------------------------------------------------------------------------
  // 3) Physical button edge
  // ---------------------------------------------------------------------------
  wire wPhysBtnC; // Center button edge pulse
  wire wPhysBtnU; // Up button edge pulse
  wire wPhysBtnD; // Down button edge pulse
  wire wPhysBtnL; // Left button edge pulse
  wire wPhysBtnR; // Right button edge pulse

  button_sync #(
    .P_BUTTON_WIDTH(5)
  ) u_button_sync (
    .iClk(iClk),
    .iRst(iRst),
    .iButtonRaw({iBtnC, iBtnU, iBtnD, iBtnL, iBtnR}),
    .oButtonEdge({wPhysBtnC, wPhysBtnU, wPhysBtnD, wPhysBtnL, wPhysBtnR})
  );

  // ---------------------------------------------------------------------------
  // 4) UART decode -> control unit
  // ---------------------------------------------------------------------------
  wire wDecBtnC;               // UART-emulated C button pulse
  wire wDecBtnU;               // UART-emulated U button pulse
  wire wDecBtnD;               // UART-emulated D button pulse
  wire wDecBtnL;               // UART-emulated L button pulse
  wire wDecBtnR;               // UART-emulated R button pulse

  wire wDecTglSw0;             // UART sw0 toggle pulse
  wire wDecTglSw1;             // UART sw1 toggle pulse
  wire wDecTglSw2;             // UART sw2 toggle pulse
  wire wDecTglSw3;             // UART sw3 toggle pulse

  wire wDecClrSwTgl;           // UART clear toggle pulse
  wire wDecReqWatchRpt;        // UART watch report request
  wire wDecReqSr04Rpt;         // UART SR04 report request
  wire wDecReqTempRpt;         // UART DHT11 temp report request
  wire wDecReqHumRpt;          // UART DHT11 hum report request

  wire [7:0] wDecLoopData;     // Raw RX loopback byte
  wire wDecLoopValid;          // Loopback byte valid pulse

  // UART ASCII decode
  uart_ascii_decoder u_uart_ascii_decoder (
    .iClk(iClk),
    .iRst(iRst),
    .iRxData(wRxFifoData),
    .iRxValid(wRxFifoPop),

    // Virtual buttons
    .oBtnC(wDecBtnC),
    .oBtnU(wDecBtnU),
    .oBtnD(wDecBtnD),
    .oBtnL(wDecBtnL),
    .oBtnR(wDecBtnR),

    // Virtual switch toggles
    .oTglSw0(wDecTglSw0),
    .oTglSw1(wDecTglSw1),
    .oTglSw2(wDecTglSw2),
    .oTglSw3(wDecTglSw3),

    // Toggle clear
    .oClrSwTgl(wDecClrSwTgl),

    // UART report requests
    .oReqWatchRpt(wDecReqWatchRpt),
    .oReqSr04Rpt(wDecReqSr04Rpt),
    .oReqTempRpt(wDecReqTempRpt),
    .oReqHumRpt(wDecReqHumRpt),

    // Loopback payload
    .oLoopData(wDecLoopData),
    .oLoopValid(wDecLoopValid)
  );

  wire wBtnC;                // Effective C input (physical OR UART)
  wire wBtnU;                // Effective U input (physical OR UART)
  wire wBtnD;                // Effective D input (physical OR UART)
  wire wBtnL;                // Effective L input (physical OR UART)
  wire wBtnR;                // Effective R input (physical OR UART)

  wire wWatchMode;           // Effective watch mode
  wire wWatchDisplay;        // Effective watch display format
  wire [1:0] wDisplaySelect; // Effective top display source

  wire wReqWatchRpt;         // Watch report request to sender
  wire wReqSr04Rpt;          // SR04 report request to sender
  wire wReqTempRpt;          // DHT11 temp report request to sender
  wire wReqHumRpt;           // DHT11 hum report request to sender
  
  wire wSr04Start;           // SR04 start pulse from control policy
  wire wDht11Start;          // DHT11 start pulse from control policy

  // Input merge and policy
  control_unit u_control_unit (
    .iClk(iClk),
    .iRst(iRst),
    // Physical inputs
    .iSw0(iSw0),
    .iSw1(iSw1),
    .iSw2(iSw2),
    .iSw3(iSw3),
    .iPhysBtnC(wPhysBtnC),
    .iPhysBtnU(wPhysBtnU),
    .iPhysBtnD(wPhysBtnD),
    .iPhysBtnL(wPhysBtnL),
    .iPhysBtnR(wPhysBtnR),
    // UART virtual inputs
    .iDecBtnC(wDecBtnC),
    .iDecBtnU(wDecBtnU),
    .iDecBtnD(wDecBtnD),
    .iDecBtnL(wDecBtnL),
    .iDecBtnR(wDecBtnR),
    .iDecTglSw0(wDecTglSw0),
    .iDecTglSw1(wDecTglSw1),
    .iDecTglSw2(wDecTglSw2),
    .iDecTglSw3(wDecTglSw3),
    .iDecClrSwTgl(wDecClrSwTgl),
    .iDecReqWatchRpt(wDecReqWatchRpt),
    .iDecReqSr04Rpt(wDecReqSr04Rpt),
    .iDecReqTempRpt(wDecReqTempRpt),
    .iDecReqHumRpt(wDecReqHumRpt),
    // Effective watch switches
    .oWatchMode(wWatchMode),
    .oWatchDisplay(wWatchDisplay),
    // Effective display select
    .oDisplaySelect(wDisplaySelect),
    // Effective buttons
    .oBtnC(wBtnC),
    .oBtnU(wBtnU),
    .oBtnD(wBtnD),
    .oBtnL(wBtnL),
    .oBtnR(wBtnR),
    // Report + sensor triggers
    .oReqWatchRpt(wReqWatchRpt),
    .oReqSr04Rpt(wReqSr04Rpt),
    .oReqTempRpt(wReqTempRpt),
    .oReqHumRpt(wReqHumRpt),
    
    .oSr04Start(wSr04Start),
    .oDht11Start(wDht11Start)
  );

  // ---------------------------------------------------------------------------
  // 5) Watch / SR04 / DHT11 blocks
  // ---------------------------------------------------------------------------
  wire [13:0] wWatchDispData;   // Watch digits packed as two 2-digit fields
  wire [3:0]  wWatchBlinkMask;  // Per-digit blink mask from watch UI state
  wire [6:0]  wWatchCurHour;    // Current watch hour for UART report
  wire [6:0]  wWatchCurMin;     // Current watch minute for UART report
  wire [6:0]  wWatchCurSec;     // Current watch second for UART report
  wire [6:0]  wWatchCurCenti;   // Current watch centisecond (reserved)

  watch_top u_watch_top (
    .iClk(iClk),
    .iRst(iRst),
    .iTick100Hz(wTick100Hz),
    .iSw0(wWatchMode),
    .iSw1(wWatchDisplay),
    .iBtnCEdge(wBtnC),
    .iBtnREdge(wBtnR),
    .iBtnLEdge(wBtnL),
    .iBtnUEdge(wBtnU),
    .iBtnDEdge(wBtnD),

    .oDispData(wWatchDispData), //watch display
    .oBlinkMask(wWatchBlinkMask),//in watch mode, modify blink mask

    //current time output
    .oCurrentHour(wWatchCurHour),
    .oCurrentMin(wWatchCurMin),
    .oCurrentSec(wWatchCurSec),
    .oCurrentCenti(wWatchCurCenti)
  );

  wire [9:0] wSr04DistanceCm;   // Measured SR04 distance in cm
  wire       wSr04DistanceValid;// SR04 measurement valid strobe/flag
  sr04_controller u_sr04_controller (
    .iClk(iClk),
    .iRst(iRst),
    .iTickUs(wTick1us),
    .iEcho(iSr04Echo),
    .iStart(wSr04Start),
    
    .oTrig(oSr04Trig),
    .oDistanceCm(wSr04DistanceCm),
    .oDistanceValid(wSr04DistanceValid)
  );

  wire [7:0] wDhtHumInt;      // DHT11 humidity integer field
  wire [7:0] wDhtTempInt;     // DHT11 temperature integer field
  wire       wDhtDataValid;   // DHT11 frame valid flag
  // DHT11 starts only when start request is asserted.
  dht11_controller u_dht11_controller (
    .iClk(iClk),
    .iRst(iRst),
    .iTickUs(wTick1us),
    .iStart(wDht11Start),
    .ioData(ioDht11Data),
    .oHumInt(wDhtHumInt),
    .oTempInt(wDhtTempInt),
    .oDataValid(wDhtDataValid)
  );

  // ---------------------------------------------------------------------------
  // 6) UART sender (loopback + watch/sr04/dht reports)
  // ---------------------------------------------------------------------------
  assign wTxPathBusy = wTxFifoFull;

  // UART TX message builder
  uart_ascii_sender u_uart_ascii_sender (
    .iClk(iClk),
    .iRst(iRst),

    //tx signal
    .iTxFifoFull(wTxPathBusy),
    .oTxData(wTxData),
    .oTxPushValid(wTxPushValid),

    //loopback
    .iLoopData(wDecLoopData),
    .iLoopValid(wDecLoopValid),

    //watch and sensor Request signal
    .iReqWatchReport(wReqWatchRpt),
    .iReqSr04Report(wReqSr04Rpt),
    .iReqTempReport(wReqTempRpt),
    .iReqHumReport(wReqHumRpt),

    //stopwatch -> uart sender // watch data
    .iWatchHour(wWatchCurHour),
    .iWatchMin(wWatchCurMin),
    .iWatchSec(wWatchCurSec),
    
    //sensor -> uart sender // data and valid signal
    .iSr04DistanceCm(wSr04DistanceCm),
    .iSr04DistanceValid(wSr04DistanceValid),
    .iDhtHumInt(wDhtHumInt),
    .iDhtTempInt(wDhtTempInt),
    .iDhtDataValid(wDhtDataValid)
  );

  // ---------------------------------------------------------------------------
  // 7) Display source mux -> shared FND
  // ---------------------------------------------------------------------------
  wire [6:0] wSr04High = wSr04DistanceCm / 100; 
  wire [6:0] wSr04Low  = wSr04DistanceCm % 100; 

  wire [13:0] wSr04DispData = wSr04DistanceValid ? {wSr04High, wSr04Low} : 14'd0;
  // DHT11 display data: {Temp, Humidity} as two 2-digit fields.
  wire [13:0] wDht11DispData = wDhtDataValid ? {wDhtTempInt[6:0], wDhtHumInt[6:0]} : 14'd0;

  reg [13:0] rSelectedDispData; // Muxed display value routed to fnd_controller
  reg [3:0]  rSelectedBlinkMask;  // Muxed blink mask routed to FND anodes

  always @(*) begin
    case (wDisplaySelect)
      2'b00: begin
        rSelectedDispData = wWatchDispData;
        rSelectedBlinkMask  = wWatchBlinkMask;
      end
      2'b01: begin
        rSelectedDispData = wSr04DispData;
        rSelectedBlinkMask  = 4'b0000;
      end
      2'b10: begin
        rSelectedDispData = wDht11DispData;
        rSelectedBlinkMask  = 4'b0000;
      end
      default: begin
        rSelectedDispData = 14'd0;
        rSelectedBlinkMask  = 4'b1111;
      end
    endcase
  end

  wire [3:0] wFndCom;  //  FND common/anode control
  wire [7:0] wFndFont; //  FND segment pattern

  fnd_controller u_fnd_controller (
    .iClk(iClk),
    .iRst(iRst),
    .iScanTick(wTick1kHz),
    .iDigit(rSelectedDispData),
    .oFndFont(wFndFont),
    .oFndCom(wFndCom)
  );

  assign oFndCom  = wFndCom | rSelectedBlinkMask;
  assign oFndFont = wFndFont;

endmodule
