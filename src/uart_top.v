// ============================================================================
// Модуль:      uart_top
// Призначення: Верхній модуль для синтезу. Об'єднує передавач uart_tx та
//              приймач uart_rx в одну схему (повнодуплексний UART-контролер).
//              Передавач і приймач працюють незалежно: TxD - вихід на лінію,
//              RxD - вхід з лінії.
// ============================================================================
`timescale 1ns / 1ps

module uart_top #(
    parameter integer CLK_FREQ  = 50_000_000,  // Тактова частота, Гц
    parameter integer BAUD_RATE = 115_200      // Баудова швидкість, біт/с
)(
    input  wire       clk,          // Системний тактовий сигнал 50 МГц
    input  wire       rst,          // Синхронне скидання

    // Інтерфейс передавача
    input  wire       tx_start,     // Запуск передачі байта
    input  wire [7:0] tx_data,      // Байт для передачі
    output wire       txd,          // Послідовний вихід UART (TxD)
    output wire       tx_busy,      // Передавач зайнятий
    output wire       tx_done,      // Кадр передано

    // Інтерфейс приймача
    input  wire       rxd,          // Послідовний вхід UART (RxD)
    output wire [7:0] rx_data,      // Прийнятий байт
    output wire       rx_valid,     // Байт прийнято
    output wire       frame_error   // Помилка кадру
);

    // Передавач
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (txd),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    // Приймач
    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk        (clk),
        .rst        (rst),
        .rx         (rxd),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .frame_error(frame_error)
    );

endmodule
