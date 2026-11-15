# ASIC front-end flow cho RV32IM core (sky130hd)

Tài liệu này ghi lại toàn bộ ASIC flow đã chạy cho core: chạy thế nào, mỗi bước
làm gì, kết quả ra sao, gặp vấn đề gì và xử lý ra sao. Phạm vi là **front-end**
(RTL → netlist cổng đã kiểm chứng). Back-end (floorplan → GDS) chưa làm.

Người đọc được giả định đã quen flow FPGA (Vivado). Mỗi bước đều so sánh với
bước tương ứng bên FPGA.

---

## 1. Bức tranh tổng thể

```
               FRONT-END (đã làm)                         BACK-END (chưa làm)
 ┌──────────────────────────────────────────────┐   ┌────────────────────────────┐
 RTL ──► Lint ──► Sim/ISA ──► Synthesis ──► netlist ──► Floorplan ► Place ► CTS ► Route ► GDS
 (rtl/)   make lint  make test   make asic-synth  │
                                                  ├─► Pre-layout STA   make asic-sta
                                                  ├─► Gate-level sim   make asic-gls
                                                  └─► LEC              make asic-lec
```

| Bước ASIC | Bên FPGA tương đương | Lệnh |
|---|---|---|
| Synthesis | `synth_design` | `make asic-synth` |
| Pre-layout STA | Timing Summary sau `synth_design` | `make asic-sta` |
| Gate-level simulation (GLS) | post-synthesis functional sim | `make asic-gls` |
| Logic equivalence check (LEC) | (Vivado không có bước này cho người dùng) | `make asic-lec` |
| Floorplan → Route → GDS | `opt/place/route_design` + `write_bitstream` | `make asic` |

**Bàn giao front-end → back-end** = netlist (`1_2_yosys.v`) + SDC + thư viện cell.

Khác biệt cốt lõi so với FPGA:

- FPGA map logic vào LUT/FF/DSP/BRAM **có sẵn** trên chip. ASIC map vào
  **standard cell** (NAND, NOR, flop, full adder…) của một công nghệ (ở đây là
  SkyWater 130 nm, thư viện `sky130_fd_sc_hd`), rồi tự vẽ ra chip.
- Trên FPGA, flop/regfile/nhân gần như "miễn phí" (có sẵn trong slice, LUTRAM,
  DSP48). Trên ASIC, **mỗi bit là diện tích thật**.
- Trên FPGA, mọi flop khởi động bằng 0 nhờ bitstream (GSR). Trên ASIC, flop bật
  nguồn lên **ngẫu nhiên** → reset phải thật sự đưa mọi trạng thái điều khiển về
  giá trị biết trước (xem mục 6.4: GLS tìm ra đúng loại lỗi này).

---

## 2. Toolchain

| Thành phần | Ở đâu | Ghi chú |
|---|---|---|
| OpenROAD-flow-scripts (ORFS) | Docker image `openroad/orfs@sha256:a2715a86…5fd0` | Yosys, OpenROAD, OpenSTA, KLayout đều nằm trong image. Pin theo digest để kết quả tái lập được. |
| PDK sky130hd | Có sẵn trong image (`flow/platforms/sky130hd`) | Chỉ có corner `tt_025C_1v80` (typical, 25 °C, 1.8 V). |
| Questa FSE 25.1 | `~/altera_lite/25.1std/questa_fse` | Mô phỏng 4 trạng thái cho GLS. |
| eqy + bitwuzla | oss-cad-suite (`~/.local/oss-cad-suite`) | LEC. |
| Bản clone ORFS | `/data/eda/OpenROAD-flow-scripts` | Chỉ để tham khảo script/ví dụ; flow chạy bằng script trong image. |

Cài đặt một lần (đã làm):

```bash
sudo apt install docker.io
echo '{ "data-root": "/data/docker" }' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
sudo usermod -aG docker $USER      # rồi reboot để nhóm docker có hiệu lực
docker pull openroad/orfs:latest   # Makefile dùng digest cố định
```

---

## 3. Các file trong `asic/`

| File | Vai trò |
|---|---|
| [`asic_core_top.sv`](asic_core_top.sv) | Top cho ASIC. Đổi 2 interface `rv32_mem_if` thành dây phẳng (chân chip không mang được SV interface). `trace_*`/`perf_*` để hở để synthesis xóa logic chỉ phục vụ quan sát. **Không có TCM** bên trong. |
| [`constraint.sdc`](constraint.sdc) | Ràng buộc timing (≈ `.xdc`). Clock `core_clk` trên `clk_i`, mặc định 20 ns; I/O giả định 20% chu kỳ ở ngoài chip. |
| [`config.mk`](config.mk) | Cấu hình ORFS: PDK, danh sách RTL (lấy từ `files/core.f`), frontend `slang`, `SYNTH_ARGS=-nofsm`, `CORE_UTILIZATION`. |
| [`sta_prelayout.tcl`](sta_prelayout.tcl) | Script OpenSTA cho STA trên netlist. |
| [`tb_gls.sv`](tb_gls.sv) | Testbench dùng chung cho RTL và netlist. |
| [`run_gls.sh`](run_gls.sh) | Compile + chạy GLS, so số chu kỳ RTL vs gate. |
| [`run_lec.sh`](run_lec.sh) | Sinh cấu hình eqy và chạy LEC. |

Kết quả nằm trong `build/asic/` (đã gitignore):

```
build/asic/
├── results/sky130hd/rv32im_core/base/1_2_yosys.v   netlist cổng (bàn giao)
├── reports/sky130hd/rv32im_core/base/synth_stat.txt thống kê cell/diện tích
├── logs/sky130hd/rv32im_core/base/                 log Yosys
├── sta_prelayout.rpt                               báo cáo STA
├── gls/                                            model cell, log GLS
└── lec/                                            cấu hình + kết quả eqy
```

Các target Makefile:

```bash
make asic-synth                  # bước 1
make asic-sta                    # bước 2  (CLK_PERIOD_NS=10 để thử clock khác)
make asic-gls                    # bước 3  (GLS_IMAGES="..." để chọn chương trình)
make asic-lec                    # bước 4
make asic-clean                  # xóa kết quả ORFS (BẮT BUỘC sau khi sửa config.mk/RTL,
                                 # vì ORFS không coi config.mk là dependency)
make asic                        # (chưa dùng) chạy cả back-end tới GDS
```

---

## 4. Bước 1 — Synthesis

### Làm gì

Yosys đọc RTL SystemVerilog (qua frontend **slang**, đọc thẳng SV có interface,
package, struct), tối ưu, rồi map sang cell sky130 (qua **ABC**). Đầu ra là
netlist Verilog chỉ gồm instance cell:

```verilog
sky130_fd_sc_hd__nand2_1 _21949_ (.A(_123_), .B(\u_core.foo ), .Y(imem_req_valid_o));
```

### Kết quả (clock 20 ns)

| Chỉ số | Giá trị |
|---|---|
| Số cell | 18,015 |
| Diện tích cell | **174,230 µm²** (≈ 0.174 mm²) |
| Flip-flop | 2,534 |
| `check` | 0 problems |

Diện tích lớn nhất theo loại cell:

| Cell | Số lượng | Diện tích | Đến từ đâu |
|---|---|---|---|
| `dfxtp_1` (flop thường) | 1,536 | 30.7k µm² | thanh ghi pipeline, CSR (`mcycle`/`minstret` 64-bit), state bộ chia/nhân |
| `edfxtp_1` (flop có enable) | 998 | 30.0k µm² | **regfile 31×32 = 992 bit** |
| `fa_1` (full adder) | 1,130 | 22.6k µm² | **bộ nhân 33×33** (~33×33 FA) |
| `mux4_2` | 543 | 12.2k µm² | 2 cổng đọc regfile |

**Bài học:** riêng flop chiếm ~35% diện tích. Trên FPGA regfile nằm trong
LUTRAM và bộ nhân nằm trong DSP48 nên gần như không tốn gì; trên ASIC chúng là
hai khối lớn nhất. Muốn giảm diện tích thì regfile là ứng viên số 1 (dùng
SRAM/latch-based regfile thay flop).

### Đọc báo cáo

- `reports/.../synth_stat.txt`: bảng cell. Cột 1 = số lượng, cột 2 = diện tích.
- `logs/.../1_2_yosys.log`: log đầy đủ, tìm `Warning` nếu có.

---

## 5. Bước 2 — Pre-layout STA

### Làm gì

STA tính delay trên **mọi đường** từ flop đến flop, không cần vector test.
Đầu vào: netlist + liberty (`.lib`: bảng delay của từng cell) + SDC. Script
[`sta_prelayout.tcl`](sta_prelayout.tcl) làm đúng 4 việc:

1. `read_lef` — OpenROAD bắt buộc có dữ liệu vật lý trước khi đọc netlist.
2. `read_liberty` — bảng delay sky130 `tt`.
3. `read_verilog` + `link_design` — netlist từ bước 1.
4. `read_sdc` — clock.

"Pre-layout" = **chưa có dây** (chỉ có delay cell, không có delay/điện dung
dây, không có clock tree/skew) → kết quả **lạc quan**. Dùng để tìm critical path
sớm, không dùng để báo cáo Fmax cuối.

### Kết quả (clock 20 ns)

| Kiểm tra | Slack |
|---|---|
| Setup, toàn chip | +7.945 ns (MET) |
| Setup, reg→reg | +11.006 ns (MET) |
| Hold | +0.426 ns (MET) |
| WNS / TNS | 0 / 0 |

**Path tệ nhất toàn chip là path I/O**: `rst_i` → logic tổ hợp →
`imem_req_valid_o` (không qua flop nào). Slack của nó phụ thuộc vào con số 20%
I/O budget tự đặt trong SDC, nên không nói lên tốc độ của core. Vì vậy script
lọc riêng path **reg→reg**.

**Critical path reg→reg (≈ 8.99 ns):**

```
ex_mem_q.wb_sel          (flop EX/MEM: lệnh ở MEM có phải load không?)
  → forwarding_unit      ex_mem_value_ready = ... && wb_sel != WB_LOAD   (forwarding_unit.sv:36)
  → mux chọn toán hạng ALU (fanout 64 bit → nhiều tầng buffer)
  → bộ cộng ALU (chuỗi ha/fa)
  → ex_mem_q.ex_result   (flop EX/MEM)
```

→ **Fmax pre-layout ≈ 1 / 8.99 ns ≈ 111 MHz** (lạc quan; sau place & route
thường giảm 20–40%). Để so: FPGA chạy 75 MHz trên Artix-7.

Bộ nhân **không** nằm trên critical path: nó có pipeline (`lhs_q`/`rhs_q` →
`result`), không phải 1 chu kỳ thuần tổ hợp.

Muốn tăng tần số, chỗ cần sửa là quyết định forwarding: giải mã sẵn "có forward
từ MEM không" ở stage trước (lưu thành 1 bit trong pipeline register) thay vì
so `wb_sel` rồi mới chọn toán hạng.

### Thử clock khác

```bash
make asic-sta CLK_PERIOD_NS=10     # không cần synth lại cho STA pre-layout
```

(Synthesis vẫn tối ưu theo SDC lúc synth; muốn synth nhắm clock khác thì
`make asic-clean && make asic-synth CLK_PERIOD_NS=10`.)

---

## 6. Bước 3 — Gate-level simulation (GLS)

### Làm gì

Chạy lại chương trình thật trên **netlist** thay vì RTL, so với kết quả RTL.
Bắt được những thứ RTL sim không thấy: X-propagation, flop không được reset,
khác biệt do synthesis hiểu RTL khác người viết.

Ba thành phần:

1. **Model cell.** Netlist chỉ ghi `sky130_fd_sc_hd__nand2_1`, simulator cần
   biết cell đó làm gì. Model được Yosys sinh **từ chính file liberty** mà
   synthesis dùng (`read_liberty` → `write_verilog`, 422 cell) — không tải gì
   thêm, và chắc chắn khớp với cái synthesis đã giả định.
2. **Testbench [`tb_gls.sv`](tb_gls.sv).** Top ASIC không có cổng `trace_*`, nên
   testbench phát hiện kết thúc trên **bus dữ liệu**: chương trình ghi `1` (pass)
   hoặc mã lẻ (fail) vào word cuối TCM (`tohost`) — cùng quy ước với
   `tb_baremetal`. Testbench còn kiểm tra **X trên `valid`/`addr`** mỗi chu kỳ.
3. **Cùng một testbench chạy 2 lần**: với RTL và với netlist. Phải PASS cả hai
   và **số chu kỳ giống hệt nhau**.

Simulator: Questa (4 trạng thái 0/1/X/Z). Verilator chỉ có 2 trạng thái nên
không thấy được X.

### Kết quả

**32 / 32 chương trình MATCH** — PASS trên cả RTL và netlist, số chu kỳ giống hệt:

| Nhóm | Chương trình | Chu kỳ (RTL = gate) |
|---|---|---|
| Bare-metal | `smoke`, `trap` (exception/CSR) | 1535, 625 |
| RV32M (tất cả 8) | `mul`, `mulh`, `mulhsu`, `mulhu`, `div`, `divu`, `rem`, `remu` | 177 – 567 |
| RV32I ALU | `add`, `sub`, `and`, `or`, `xor`, `slt`, `sll`, `sra`, `lui`, `auipc` | 39 – 518 |
| RV32I load/store | `lw`, `lh`, `lb`, `sw`, `sh`, `sb` | 267 – 598 |
| RV32I control | `beq`, `bne`, `blt`, `bgeu`, `jal`, `jalr` | 35 – 380 |

Không có X trên bus (testbench kiểm mỗi chu kỳ) — với giả định flop khởi động
bằng 0, xem 6.4.

Chạy lại đúng bộ này:

```bash
I=/tmp/rv32im-core-isa-$(id -u); W=/tmp/rv32im-core-software-$(id -u)
make asic-gls GLS_IMAGES="$W/smoke.mem $W/trap.mem $(ls $I/rv32um-*.mem) \
  $(for t in add sub and or xor slt sll sra lui auipc lw lh lb sw sh sb beq bne blt bgeu jal jalr; do echo $I/rv32ui-$t.mem; done)"
```

`make asic-gls` không có `GLS_IMAGES` chạy toàn bộ 54 image (gồm 4 benchmark dài
— rất chậm trên Questa Starter, xem giới hạn bên dưới).

### 6.4 Phát hiện: core có thể treo khi bật nguồn (chỉ có trên ASIC)

Lần chạy GLS đầu tiên, netlist báo **X trên `valid` của bus ngay sau reset**.
Lần ngược fan-in cone của `imem_req_valid_o` (script tự động) tìm ra nguồn X là
các flop `state_q`, `request_sent_q`, `discard_q` của **IF** và **LSU**.

Nguyên nhân nằm ở cơ chế *reset drain* ([`if_stage.sv:277-283`](../rtl/core/if_stage.sv#L277-L283),
[`lsu.sv:222-228`](../rtl/core/lsu.sv#L222-L228)):

```systemverilog
if (rst_i) begin
  state_q <= IF_IDLE; ...
  // A request accepted before reset cannot be cancelled. Drain its response.
  if ((state_q == IF_BUSY) && request_sent_q && !imem_m.rsp_valid) begin
    state_q <= IF_BUSY; request_sent_q <= 1'b1; discard_q <= 1'b1;
  end
end
```

Giá trị sau reset **phụ thuộc vào giá trị trước reset**. Đúng cho *warm reset*
(reset khi đang chạy, có request thật đang bay). Nhưng khi **bật nguồn**:

| Môi trường | `state_q` lúc bật nguồn | Kết quả |
|---|---|---|
| FPGA | 0 (GSR từ bitstream) | luôn IDLE → chạy bình thường |
| RTL sim | X, nhưng `if (X)` được coi là false (*X-optimism*) | luôn IDLE → chạy bình thường |
| Netlist (GLS) | X, cổng logic lan truyền X (*pessimism*) | X mãi → bị bắt |
| **Silicon** | **ngẫu nhiên** | nếu rơi vào `BUSY + request_sent=1` → **treo** |

Đã xác nhận bằng **RTL** (không phải lỗi tool): ép trạng thái bật nguồn
`state_q=BUSY, request_sent_q=1, imem.rsp_valid=0` lúc 0 ns → chương trình
`smoke` **timeout sau 20,000 chu kỳ** (bình thường pass ở 1,535 chu kỳ). Core
đứng chờ một response cho request không hề tồn tại.

**Chưa sửa RTL** — đây là quyết định thiết kế. Các hướng sửa:

1. Thêm **power-on reset bất đồng bộ** (`por_n`) chỉ cho vài flop điều khiển
   (`state_q`, `request_sent_q`, `discard_q` của IF/LSU); giữ `rst_i` đồng bộ
   và cơ chế drain cho warm reset.
2. Một flop `drain_allowed_q` được reset về 0 và chỉ lên 1 sau khi core đã từng
   phát request; chỉ drain khi bit đó bằng 1.
3. Quy định ở mức SoC: reset bus/memory cùng lúc với core và bỏ drain khi đó.

Để GLS tiếp tục làm việc chính (so netlist với RTL), [`run_gls.sh`](run_gls.sh)
khởi tạo mọi flop = 0 lúc 0 ns (`vsim -voptargs=+initreg+0`) — **giả định giống
FPGA**. Chạy `GLS_INIT= asic/run_gls.sh ...` để bỏ giả định này và thấy lại lỗi.

### Giới hạn của GLS ở đây

- **Zero-delay**: chỉ kiểm chức năng, không có delay cell (chưa có SDF). GLS có
  timing cần SDF sau place & route.
- **Questa Starter Edition** giới hạn 5,000 instance (netlist có ~18,000):
  vẫn đúng nhưng **chậm ~60 chu kỳ/giây**. Vì vậy chỉ chạy bộ đại diện, không
  chạy benchmark dài/CoreMark.

---

## 7. Bước 4 — Logic Equivalence Check (LEC)

### Làm gì

Chứng minh **toán học** (không cần vector) rằng netlist ≡ RTL. Cách làm của
`eqy`:

1. Đọc RTL (*gold*) và netlist (*gate*).
2. **Ghép flop theo tên** giữa hai bên (`ex_mem_q[220]` ↔ `ex_mem_q[220]`).
3. Cắt design tại các flop đã ghép → nhiều *partition* tổ hợp nhỏ.
4. Với mỗi partition, solver (bitwuzla) chứng minh "cùng đầu vào → cùng đầu ra"
   (basecase + induction, depth 2).

LEC bổ sung cho GLS: GLS chỉ kiểm các chương trình đã chạy; LEC phủ **mọi**
đầu vào.

### Vì sao phải cấu hình nhiều

Tool thương mại (Synopsys Formality, Cadence Conformal) nhận file *guidance*
từ synthesis (vd. `.svf` của Design Compiler) ghi lại mọi biến đổi: FSM đã mã hóa
lại, flop hằng đã xóa, flop đã đổi tên… Yosys/ORFS **không xuất file này** và
eqy chỉ ghép theo tên, nên mỗi biến đổi phải được khai báo tay. Mỗi dòng cấu hình
trong [`run_lec.sh`](run_lec.sh) ứng với một vấn đề LEC kinh điển:

| Vấn đề gặp | Triệu chứng | Xử lý | Tool thương mại làm bằng |
|---|---|---|---|
| Module cell thừa phía gate | eqy lỗi "unmatched module" | `hierarchy -purge_lib` | đọc thư viện riêng |
| **FSM bị mã hóa lại** (LSU 2 bit → 3 bit) | `state_q[0]` cùng tên khác nghĩa | `SYNTH_ARGS = -nofsm` trong `config.mk` | FSM mapping trong guidance |
| **Điểm cắt tại port output** tổ hợp | counterexample "LSU BUSY mà valid=0" (không thể xảy ra) | `bind imem_req_*`, `bind dmem_req_*` | tự chọn cut point ở flop |
| **Flop hằng bị synthesis xóa** (`mcause[30:5]` luôn 0) | induction fail | `wreduce; opt; opt_dff -sat <CSR>` phía gold | sequential-constant analysis |
| **Flop mang tên alias** (`mtvec_q`/`mtvec_o`/`csr_mtvec`) | không ghép được → trạng thái tự do | `gold-match` | renaming rule, function-based mapping |

`-nofsm` làm netlist đổi chút (diện tích 174,839 → 174,230 µm², reg→reg
8.60 → 8.99 ns); mọi số liệu trong tài liệu này là của netlist `-nofsm`.

### Kết quả

| | |
|---|---|
| Tên được ghép (flop + port) | 2,660 |
| Partition | **21 / 22 chứng minh tương đương** |
| Còn lại | 1 partition lớn (~4,000 đầu vào): **basecase pass** (không tìm được input nào làm khác trong 2 chu kỳ), **induction chưa khép** |

Partition còn lại chưa khép vì còn **13 bit CSR luôn bằng 0** (`mie` ×7,
`mstatus` ×6) synthesis đã xóa nhưng phía gold chưa xóa được. Khi bắt đầu từ
trạng thái tùy ý, solver cho các bit đó ≠ 0 ở phía RTL → output lệch. Đây là
giới hạn *sequential equivalence có xét reset* của eqy, không phải sai khác thật;
kết hợp với GLS (MATCH từng chu kỳ) cho mức tin cậy tốt.

### Các giả định của LEC (đọc kỹ)

Mỗi quy tắc là một giả định; nếu sai, LEC có thể pass sai:

- `opt`/`opt_dff -sat` phía gold giả định **chip luôn được reset trước khi chạy**
  (cùng giả định synthesis đã dùng khi xóa flop hằng).
- `gold-match` giả định các cặp tên alias là cùng một thanh ghi — đã kiểm bằng
  cách đọc chân `Q` của flop trong netlist.
- `bind` không làm yếu chứng minh (chỉ đưa thêm logic vào partition).

---

## 8. Tóm tắt kết quả

| Hạng mục | Kết quả |
|---|---|
| Synthesis | 18,015 cell, 174,230 µm², 2,534 flop, 0 lỗi check |
| Pre-layout STA @ 20 ns | MET; reg→reg 8.99 ns (≈111 MHz, lạc quan) |
| GLS | 32/32 chương trình MATCH (RTL = gate, từng chu kỳ), không X trên bus |
| LEC | 21/22 partition proven; 1 partition basecase pass, induction chưa khép |
| Phát hiện thiết kế | IF/LSU reset-drain có thể treo khi bật nguồn trên ASIC (đã tái hiện trên RTL) |

---

## 9. Bước tiếp theo (gợi ý)

1. **Sửa lỗi power-on** (mục 6.4), chạy lại `make asic-gls` với `GLS_INIT=` để
   xác nhận không còn X.
2. **Chạy back-end tự động** một lần: `make asic` → số post-route (Fmax, diện tích
   die, công suất) đặt cạnh kết quả Vivado.
3. **Timing**: sweep `CLK_PERIOD_NS` sau route; thử tách quyết định forwarding.
4. **Diện tích**: regfile 31×32 flop là khối lớn nhất.

---

## 10. Sự cố thường gặp

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| `permission denied ... docker.sock` | user chưa có nhóm `docker` trong phiên hiện tại → reboot. |
| Sửa `config.mk` mà kết quả không đổi | ORFS báo "Nothing to be done" → `make asic-clean` trước. |
| `vopt-14408` / `vsim-16154` | giới hạn 5,000 instance của Questa Starter; đã suppress, chỉ chậm. |
| `vopt-7061` | testbench nạp TCM trước khi chạy; repo vốn suppress lỗi này. |
| GLS báo X ngay sau reset | xem mục 6.4; mặc định đã khởi tạo flop = 0. |
| `openroad` báo `no technology has been read` | phải `read_lef` trước `read_verilog`. |
