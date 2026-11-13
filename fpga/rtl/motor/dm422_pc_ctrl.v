// Standalone JTAG GUI controller. control is a single clock-synchronous VIO bus.
// [0] enable, [1] move toggle, [2] stop toggle, [3] direction,
// [4] heartbeat toggle, [31:16] pulse count, [63:32] half-period clocks.
module dm422_pc_ctrl #(
    parameter integer CLK_HZ = 25000000,
    parameter integer WATCHDOG_CYCLES = 50000000
)(
    input wire clk,
    input wire rst_n,
    input wire [63:0] control,
    output reg motor_pul,
    output reg motor_dir,
    output reg motor_disable,
    output wire [31:0] status
);
    localparam [2:0] IDLE=0, SETTLE=1, HIGH_PHASE=2, LOW_PHASE=3;
    localparam integer SETTLE_CYCLES = CLK_HZ / 100; // 10 ms
    localparam integer MIN_HALF = (CLK_HZ + 799) / 800; // <=400 Hz
    localparam integer MAX_HALF = CLK_HZ / 40; // >=20 Hz
    reg [2:0] state;
    reg move_d, stop_d, heartbeat_d, alive;
    reg busy, done, stopped, fault, range_error, stop_pending;
    reg [31:0] watchdog, timer, half_period;
    reg [15:0] target, sent;
    wire move_edge = control[1] != move_d;
    wire stop_edge = control[2] != stop_d;
    wire heartbeat_edge = control[4] != heartbeat_d;
    wire valid_config = control[31:16] >= 1 && control[31:16] <= 400 &&
                        control[63:32] >= MIN_HALF && control[63:32] <= MAX_HALF;
    // Status is not an encoder position. sent counts completed output pulses.
    assign status = {5'b0,state,sent,stopped,motor_dir,alive,range_error,
                     fault,done,busy,!motor_disable};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motor_pul <= 0; motor_dir <= 0; motor_disable <= 1;
            state <= IDLE; move_d <= 0; stop_d <= 0; heartbeat_d <= 0;
            alive <= 0; busy <= 0; done <= 0; stopped <= 0; fault <= 0;
            range_error <= 0; stop_pending <= 0; watchdog <= 0; timer <= 0;
            half_period <= 0; target <= 0; sent <= 0;
        end else begin
            move_d <= control[1]; stop_d <= control[2]; heartbeat_d <= control[4];
            if (heartbeat_edge) begin
                watchdog <= 0;
                alive <= 1;
            end else if (watchdog < WATCHDOG_CYCLES - 1)
                watchdog <= watchdog + 1'b1;
            else begin
                alive <= 0;
                if (control[0]) fault <= 1;
            end
            // A timeout remains latched until the host explicitly disables.
            if (!control[0] && alive) fault <= 0;
            if (!control[0] || !alive || fault ||
                (!heartbeat_edge && watchdog >= WATCHDOG_CYCLES - 1)) begin
                motor_disable <= 1;
                motor_pul <= 0;
                if (busy) stopped <= 1;
                busy <= 0; state <= IDLE; timer <= 0; stop_pending <= 0;
                done <= 0;
            end else begin
                motor_disable <= 0;
                if (stop_edge) stop_pending <= 1;
                // Normal stop completes an existing high pulse; no new rise.
                if ((stop_edge || stop_pending) && state != HIGH_PHASE) begin
                    motor_pul <= 0; busy <= 0; state <= IDLE;
                    stop_pending <= 0; stopped <= 1; done <= 0;
                end else case (state)
                    IDLE: begin
                        motor_pul <= 0; busy <= 0;
                        if (move_edge && !stop_edge) begin
                            if (!valid_config) begin
                                range_error <= 1;
                            end else begin
                                range_error <= 0; done <= 0; stopped <= 0;
                                target <= control[31:16]; half_period <= control[63:32];
                                motor_dir <= control[3]; sent <= 0; busy <= 1;
                                timer <= SETTLE_CYCLES - 1; state <= SETTLE;
                            end
                        end
                    end
                    SETTLE: begin
                        if (timer == 0) begin
                            motor_pul <= 1; timer <= half_period - 1; state <= HIGH_PHASE;
                        end else timer <= timer - 1'b1;
                    end
                    HIGH_PHASE: begin
                        if (timer == 0) begin
                            motor_pul <= 0; sent <= sent + 1'b1;
                            timer <= half_period - 1; state <= LOW_PHASE;
                        end else timer <= timer - 1'b1;
                    end
                    LOW_PHASE: begin
                        if (timer == 0) begin
                            if (sent == target) begin
                                busy <= 0; done <= 1; state <= IDLE;
                            end else begin
                                motor_pul <= 1; timer <= half_period - 1; state <= HIGH_PHASE;
                            end
                        end else timer <= timer - 1'b1;
                    end
                    default: begin
                        motor_pul <= 0; motor_disable <= 1;
                        busy <= 0; state <= IDLE; fault <= 1;
                    end
                endcase
            end
        end
    end
endmodule
