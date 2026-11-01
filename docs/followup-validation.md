# Báo cáo xử lý 5 việc sau review

Ngày ghi nhận: **01/11/2026**. Điểm bắt đầu: `02367e0` trên `main`.
Bản sửa reset `77617e1` và test SoC 12 scenario/596 checks được giữ nguyên.

## Tổng hợp commit và regression

| Việc | Commit | Kết quả sau sửa/khôi phục mutant |
|---|---|---|
| 1. Assertion giả định reset demux | `595d2b8` | `make -j4 test`: PASS |
| 2. Biên shortcut divider | `74671a6` | `make -j4 test`: PASS |
| 3. Ghi fixed WARL misa | `fe00167` | `make -j4 test`: PASS |
| 4. FreeRTOS config stamp | `d42de23` | `make -j4 test`: PASS, gồm config checker mới |
| 5. Thống nhất branch penalty | Commit chứa tài liệu này; tra bằng lệnh dưới | `make -j4 test`: PASS |

Tra hash commit cuối bằng:

```sh
git log -1 --format='%h %s' -- docs/followup-validation.md
```

Không ghi hash của chính commit vào nội dung commit đó vì sẽ làm thay đổi hash.
Mỗi cổng `make test` đã hoàn tất lint, 21 unit test, 8 integration test, một
FreeRTOS SoC simulation, hai chương trình bare-metal và 48 ISA test. Từ việc 4,
cổng này còn chạy regression về cấu hình build trong cache tạm riêng.

Thông báo kết thúc của cả năm cổng:

```text
[PASS] RTL lint, 30 RTL simulations (including FreeRTOS SoC bring-up), 2 bare-metal programs, and 48 ISA tests completed
```

Tool được truy vấn trong phiên: Verilator 5.020, RISC-V GCC 16.1.0,
GNU Make 4.3, Python 3.11.6. Kết quả này là simulation/build, không phải
implementation, timing closure hoặc xác nhận chạy board cho RTL mới.

## 1. Assertion xuyên reset của demux

**File:** `rtl/soc/rv32_mem_demux.sv`, `tb/unit/tb_rv32_mem_demux.sv`,
`docs/architecture.md`, `docs/verification.md`, `README.md`.

Thêm hai assertion bên trong `ifndef SYNTHESIS`, không có `disable iff`:

```systemverilog
(rst_i && pending_q) |-> pending_rsp_valid
(rst_i && pending_q) |-> core_s.rsp_valid
```

Assertion thứ nhất kiểm tra giả định response đã sẵn sàng tại cạnh xóa
ownership. Assertion thứ hai kiểm tra response thực sự được chuyển tới
master; chỉ kiểm tra tín hiệu phía slave chưa bắt được việc che response.

**Mutation 1 — response slave trễ:** unit test có nhánh negative-only
`+delay_reset_response`, giữ response chưa sẵn sàng tại cạnh reset thay vì
trả sau một chu kỳ. Chạy executable đã build bởi `make test`:

```sh
ulimit -c 0
/tmp/rv32im-core-verilator-1000/tb_rv32_mem_demux/Vtb_rv32_mem_demux +delay_reset_response
```

Exit `134`, FAIL đúng tại assertion:

```text
a_reset_owned_response_available: demux reset would discard ownership before its response is available
```

**Mutation 2 — che response bằng reset:** trong bản sao demux dưới `/tmp`,
khôi phục `!rst_i && pending_q && pending_rsp_valid`. Bản sao unit test bỏ
ba kiểm tra tổ hợp ngay trước cạnh reset để cho phép SVA tại cạnh đó chạy;
source test và RTL trong repo không bị thay đổi. Lệnh đã chạy:

```sh
make tb_rv32_mem_demux BUILD_DIR=/tmp/rv32-followup-mask \
  'tb_rv32_mem_demux_SRCS=rtl/core/rv32_mem_if.sv /tmp/rv32-followup-evidence/mask-mutant/rv32_mem_demux.sv /tmp/rv32-followup-evidence/mask-mutant/tb_rv32_mem_demux.sv'
```

Exit `2`, FAIL đúng tại assertion thứ hai:

```text
a_reset_owned_response_forwarded: demux reset hid an owned response from the master
```

**Giả định còn lại:** assertion phát hiện việc vi phạm hợp đồng, không biến
demux thành interconnect hỗ trợ reset với response latency tùy ý. Không thêm
LSU liveness property tổng quát vì yêu cầu đó cần giả định về khả năng phản
hồi của môi trường. Deadline reboot của `tb_soc_reset` vẫn được giữ.

## 2. Test ngưỡng shortcut divider

**File:** `tb/unit/tb_div_unit.sv`, `sw/tests/smoke.c`,
`docs/architecture.md`, `docs/verification.md`, `README.md`.

Không sửa RTL divider. Thêm cả bốn lệnh DIV/DIVU/REM/REMU với các cặp bit:
7/7, -7/7, 7/-7, -7/-7, INT_MIN/INT_MIN, UINT_MAX/UINT_MAX, 6/7 và 7/6.
Với lệnh unsigned, các mẫu bit âm được diễn giải như số unsigned.
Unit test dùng phép chia/lấy dư tham chiếu và kiểm tra identity. Smoke dùng
inline assembly để compiler không tối ưu x/x, với kết quả kỳ vọng hằng số.

**Mutation:** tạm đổi trong `rtl/core/div_unit.sv`:

```text
(input_lhs_magnitude < input_rhs_magnitude)
→ (input_lhs_magnitude <= input_rhs_magnitude)
```

Các lệnh chạy trên mutant đều exit `2`:

```sh
make tb_div_unit
make baremetal-smoke
```

FAIL unit:

```text
equal positive magnitudes DIV special-case latency: expected=0 actual=1
```

FAIL pipeline/bare-metal:

```text
smoke: software reported failure status=00000201 code=00000100
```

`0x100` là kiểm tra thương signed của vector 7/7. Sau khi khôi phục phép
so sánh `<`, chạy lại `make -j4 test`: PASS. Unit divider đạt 6705 checks.

**Giới hạn:** các vector bổ sung đóng lỗ hổng equality đã biết; đây không
phải formal proof hoặc tuyên bố đã phủ mọi operand/handshake có thể có.

## 3. Ghi misa hợp lệ, giá trị giữ nguyên

**File:** `rtl/core/csr_file.sv`, `tb/unit/tb_csr.sv`,
`tb/integration/tb_csr_core.sv`, `sw/tests/smoke.c`,
`docs/architecture.md`, `docs/verification.md`, `README.md`.

Cho phép access-write tới `misa`, bỏ qua dữ liệu tại commit và tiếp tục trả
`MISA_RV32IM`. Các ID CSR read-only không đổi quyền truy cập. Test tích hợp
đổi instruction tạo illegal-write trap từ `misa` sang `mvendorid`, giữ nguyên
kiểm tra precise trap. Unit test và smoke kiểm tra cả sáu dạng lệnh ghi misa.

Cơ sở là [Machine ISA specification, misa và mvendorid](https://docs.riscv.org/reference/isa/priv/machine.html):
misa là WARL tại địa chỉ read-write; implementation này chỉ hỗ trợ một giá
trị. Điều đó khác với các ID CSR ở vùng địa chỉ read-only.

**Mutation:** tạm đặt `access_writable = 1'b0` riêng cho nhánh `CSR_MISA`.
Chạy:

```sh
make tb_csr
make baremetal-smoke
```

Cả hai exit `2`. Unit FAIL:

```text
CSRRW misa zero write is legal mismatch: data=40001100/40001100 illegal=1/0
```

Smoke ghi nhận instruction `30101073` trap với cause `2`, rồi FAIL:

```text
smoke: software reported failure status=00000205 code=00000102
```

Khôi phục quyền ghi misa rồi chạy lại `make -j4 test`: PASS. Unit CSR đạt
95 checks; integration vẫn kiểm tra ghi `mvendorid` gây illegal instruction.

**ISA/ACT4:** đã tìm test misa trong source và kiểm tra cấu hình. Bộ ISA
đang ghim chỉ chạy I/M, không có bài misa-write chuyên biệt. ACT4 hiện đặt
`include_priv_tests: false`, nên không chạy ACT4 trong đợt này và không dùng
kết quả I/M để khẳng định conformance privileged. Cấu hình reference model
giữ extension set cố định; không bật privileged tests ngoài phạm vi.

## 4. FreeRTOS config stamp và rebuild regression

**File:** `sw/Makefile`, `Makefile`, `tools/check_freertos_config.py`,
`docs/software.md`, `docs/architecture.md`, `docs/verification.md`, `README.md`.

Stamp `freertos/config.stamp` dưới BUILD_DIR chứa CC, FREERTOS_CPPFLAGS,
FREERTOS_PROJECT_CFLAGS và FREERTOS_KERNEL_CFLAGS. Cả tám object, gồm BSP,
phụ thuộc stamp. So sánh nội dung chỉ thêm FORCE khi cấu hình khác; recipe
dùng `cmp` trước khi thay file, giữ nguyên timestamp khi không đổi.
Điều kiện FORCE này còn tránh việc `make -n` lên lịch compile giả khi cấu
hình không đổi. Parse-time comparison không ghi file.

Checker mới thực sự build trong cache riêng, kiểm tra dry-run và timestamp
của cả tám object, đổi blink, đổi clock, rồi trở về mặc định. Sau mỗi thay
đổi còn kiểm tra lần build kế tiếp là no-op. Nó được gọi trong `make test`.

Các lệnh đã chạy:

```sh
python3 tools/check_freertos_config.py
make -n -C sw freertos-images
make -n -C sw FREERTOS_BLINK_PERIOD_MS=250 freertos-images
make -n -C sw FREERTOS_CPU_CLOCK_HZ=50000000 freertos-images
make fpga-freertos-images
```

Hai dry-run thay đổi cấu hình đều có tám recipe compile C/assembly;
dry-run mặc định sau build mặc định không có recipe compile nào.
Checker xác nhận unchanged build không đổi timestamp stamp/object.
Board-image target build thành công ELF/BIN/MEM/DUMP trong BUILD_DIR riêng
với `-B`; không chạy program board. Không sửa CoreMark.

**Mutation:** tạm bỏ prerequisite FORCE khỏi rule stamp:

```text
$(FREERTOS_CONFIG_STAMP): $(FREERTOS_CONFIG_FORCE)
→ $(FREERTOS_CONFIG_STAMP):
```

Chạy lại `python3 tools/check_freertos_config.py` exit `1`:

```text
RuntimeError: changed configuration did not schedule C/assembly rebuilds: ['FREERTOS_BLINK_PERIOD_MS=250']
```

Khôi phục rule rồi `make -j4 test`: PASS, gồm dòng:

```text
[PASS] FreeRTOS configuration stamp regression
```

**Giới hạn:** stamp theo nội dung command/flags; không fingerprint binary
compiler nếu binary bị thay tại cùng một đường dẫn. Cấu hình firmware vẫn
phải được chọn đúng với clock hardware; stamp không tự thay clock RTL.

## 5. Thống nhất diễn đạt branch penalty

**File:** `README.md`, `docs/architecture.md`, `docs/waveform-debug.md`,
`docs/verification.md` và báo cáo này.

Diễn đạt thống nhất: accepted EX redirect đưa control instruction sang
EX/MEM, xóa slot ID/EX cũ, squash younger IF/ID và fetch work. Thời gian
phục hồi còn phụ thuộc fetch-response timing; không suy ra penalty cố định
hai chu kỳ chỉ từ số boundary được flush.

Đây là thay đổi tài liệu, không sửa RTL hoặc tạo test mới. Vì vậy mutation
test không áp dụng cho việc 5. `make -j4 test` vẫn đã được chạy và PASS theo
yêu cầu; `tb_core_control_flow` hiện có giữ oracle retirement/wrong-path.

## Log và phạm vi giữ nguyên

Log đầy đủ trong phiên nằm dưới `/tmp/rv32-followup-evidence/`:

- `01-make-test.log`, `01-delayed-response-fail.log`, `01-mask-assertion-fail.log`.
- `02-make-test-restored.log`, `02-mutant-unit.log`, `02-mutant-baremetal.log`.
- `03-make-test-restored.log`, `03-mutant-unit.log`, `03-mutant-baremetal.log`.
- `04-make-test.log`, `04-config-check.log`, `04-mutant-config.log`,
  `04-dry-unchanged.log`, `04-dry-blink.log`, `04-dry-clock.log`, `04-board-image.log`.
- `05-make-test.log`.

Các file `/tmp` có thể mất; các trích đoạn FAIL/PASS được lưu ở đây để giữ
bằng chứng có thể đọc lại. Những mutant tại file thật được khôi phục trong
khối `finally` trước khi chạy regression sau cùng. Mutant che response dùng
bản sao riêng; không thay ngược bản sửa `77617e1` trong working tree.

Không thêm predictor, formal, coverage hoặc đổi pipeline/timing architecture.
Không chạy lại Questa/Vivado/board trong đợt này. Các thay đổi ngoài phạm vi
đã có trước được giữ lại ngoài năm commit; chỉnh sửa waveform liên quan tới
branch được đưa vào việc 5 theo yêu cầu.
