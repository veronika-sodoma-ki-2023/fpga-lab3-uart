// ============================================================================
// Тестбенч:    tb_uart
// Призначення: Функціональна верифікація модулів uart_tx та uart_rx.
//
// Сценарії перевірки:
//   ТЕСТ 1 (Loopback): вихід передавача tx з'єднано з входом приймача rx.
//          Передаємо набір байтів через uart_tx і перевіряємо, що uart_rx
//          прийняв рівно ті самі байти.
//   ТЕСТ 2 (Зовнішній пристрій): тестбенч сам формує UART-кадри на лінії,
//          імітуючи інший пристрій (наприклад, ПК), і перевіряє uart_rx.
//   ТЕСТ 3 (Помилка кадру): зовнішній пристрій надсилає кадр з неправильним
//          стоп-бітом ('0'). Приймач має видати frame_error.
//
// Результат: у консоль симулятора виводиться PASS/FAIL для кожного байта
//            та підсумок. Симуляція завершується сама ($finish).
// ============================================================================
`timescale 1ns / 1ps

module tb_uart;

    // ------------------------------------------------------------------------
    // Параметри
    // ------------------------------------------------------------------------
    localparam integer CLK_FREQ  = 50_000_000;            // 50 МГц
    localparam integer BAUD_RATE = 115_200;               // біт/с
    localparam real    CLK_PERIOD_NS = 1.0e9 / CLK_FREQ;  // 20 нс
    localparam real    BIT_NS        = 1.0e9 / BAUD_RATE; // ~8680.6 нс

    // ------------------------------------------------------------------------
    // Сигнали
    // ------------------------------------------------------------------------
    reg        clk = 1'b0;      // Тактовий сигнал
    reg        rst = 1'b1;      // Скидання

    // Інтерфейс передавача
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'h00;
    wire       tx_line;         // Вихід TxD передавача
    wire       tx_busy;
    wire       tx_done;

    // Інтерфейс приймача
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       frame_error;

    // Лінія "зовнішнього пристрою" та перемикач джерела для приймача
    reg        ext_line   = 1'b1;  // Лінія, якою керує тестбенч
    reg        use_ext    = 1'b0;  // 0 - loopback (tx -> rx), 1 - зовнішній
    wire       rx_line    = use_ext ? ext_line : tx_line;

    // Лічильники та результати
    integer    rx_count    = 0;    // Скільки байтів прийнято
    integer    fe_count    = 0;    // Скільки помилок кадру зафіксовано
    reg  [7:0] last_rx     = 8'h00;// Останній прийнятий байт
    integer    errors      = 0;    // Кількість помилок перевірки
    integer    checks      = 0;    // Кількість виконаних перевірок

    // ------------------------------------------------------------------------
    // Генерація тактового сигналу 50 МГц
    // ------------------------------------------------------------------------
    always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

    // ------------------------------------------------------------------------
    // Тестовані модулі (DUT)
    // ------------------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (tx_line),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut_rx (
        .clk        (clk),
        .rst        (rst),
        .rx         (rx_line),
        .rx_data    (rx_data),
        .rx_valid   (rx_valid),
        .frame_error(frame_error)
    );

    // ------------------------------------------------------------------------
    // Монітор виходів приймача: фіксує кожен прийнятий байт / помилку
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rx_valid) begin
            rx_count <= rx_count + 1;
            last_rx  <= rx_data;
            $display("[%0t ns] RX: received byte 0x%02h", $time, rx_data);
        end
        if (frame_error) begin
            fe_count <= fe_count + 1;
            $display("[%0t ns] RX: frame error detected", $time);
        end
    end

    // ------------------------------------------------------------------------
    // Задача: передати байт через uart_tx і перевірити прийом (loopback)
    // ------------------------------------------------------------------------
    task send_via_tx(input [7:0] data);
        integer cnt_before;
        begin
            wait (tx_busy == 1'b0);
            cnt_before = rx_count;

            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;           // Імпульс запуску на 1 такт
            @(posedge clk);
            tx_start <= 1'b0;

            $display("[%0t ns] TX: start sending 0x%02h", $time, data);
            wait (tx_done == 1'b1);     // Кадр передано повністю
            @(posedge clk);
            @(posedge clk);

            checks = checks + 1;
            if (rx_count == cnt_before + 1 && last_rx == data)
                $display("    PASS: sent 0x%02h, received 0x%02h", data, last_rx);
            else begin
                $display("    FAIL: sent 0x%02h, received 0x%02h (frames: %0d)",
                         data, last_rx, rx_count - cnt_before);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Задача: імітація зовнішнього пристрою - формує кадр UART на ext_line
    //   data     - байт для передачі
    //   stop_bit - значення стоп-біта (1 - коректний кадр, 0 - помилковий)
    // ------------------------------------------------------------------------
    task ext_send(input [7:0] data, input stop_bit);
        integer i;
        begin
            ext_line = 1'b0;                 // Старт-біт
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                ext_line = data[i];          // Біти даних, LSB first
                #(BIT_NS);
            end
            ext_line = stop_bit;             // Стоп-біт
            #(BIT_NS);
            ext_line = 1'b1;                 // Повернення лінії в спокій
            #(BIT_NS);                       // Пауза між кадрами
        end
    endtask

    // Перевірка коректного кадру від зовнішнього пристрою
    task check_ext(input [7:0] data);
        integer cnt_before;
        begin
            cnt_before = rx_count;
            $display("[%0t ns] EXT: external device sends 0x%02h", $time, data);
            ext_send(data, 1'b1);
            checks = checks + 1;
            if (rx_count == cnt_before + 1 && last_rx == data)
                $display("    PASS: expected 0x%02h, received 0x%02h", data, last_rx);
            else begin
                $display("    FAIL: expected 0x%02h, received 0x%02h", data, last_rx);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Основна послідовність тестів
    // ------------------------------------------------------------------------
    integer fe_before, rx_before;

    initial begin
        $dumpfile("tb_uart.vcd");   // Для GTKWave (Vivado ігнорує)
        $dumpvars(0, tb_uart);

        // Скидання
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // ---------------- ТЕСТ 1: Loopback ----------------
        $display("\n===== TEST 1: Loopback (uart_tx -> uart_rx) =====");
        use_ext = 1'b0;
        send_via_tx(8'h55);   // 01010101 - чергування біт
        send_via_tx(8'hA5);   // 10100101
        send_via_tx(8'h00);   // усі нулі
        send_via_tx(8'hFF);   // усі одиниці
        send_via_tx(8'h3C);   // 00111100

        // ---------------- ТЕСТ 2: Зовнішній пристрій ----------------
        $display("\n===== TEST 2: Receive from external device =====");
        repeat (100) @(posedge clk);
        use_ext = 1'b1;
        #(BIT_NS);
        check_ext(8'h4B);     // 'K'
        check_ext(8'h49);     // 'I'
        check_ext(8'h81);     // 10000001

        // ---------------- ТЕСТ 3: Помилка кадру ----------------
        $display("\n===== TEST 3: Invalid stop bit =====");
        fe_before = fe_count;
        rx_before = rx_count;
        $display("[%0t ns] EXT: frame 0x77 with stop bit = 0", $time);
        ext_send(8'h77, 1'b0);
        checks = checks + 1;
        if (fe_count == fe_before + 1 && rx_count == rx_before)
            $display("    PASS: frame_error raised, no byte output");
        else begin
            $display("    FAIL: frame_error not detected");
            errors = errors + 1;
        end

        // Після помилки приймач має працювати далі
        check_ext(8'hC3);

        // ---------------- Підсумок ----------------
        $display("\n==============================================");
        if (errors == 0)
            $display(" ALL TESTS PASSED: %0d of %0d", checks, checks);
        else
            $display(" FAILED: %0d of %0d checks", errors, checks);
        $display("==============================================\n");
        $finish;
    end

    // Захист від "зависання" симуляції
    initial begin
        #20_000_000;   // 20 мс
        $display("TIMEOUT: simulation time limit exceeded");
        $finish;
    end

endmodule
