# 离线 VLP 参考示例

Python 3.9+，仅使用标准库。所有脚本只处理文件/字节，不加载 USB 库，不连接设备，不执行寄存器写入。

在交付目录 `host_protocol_20260919` 中运行：

```powershell
python -B examples/vlp_reference.py examples/capture_example.bin --chunk-size 7
python -B examples/test_vlp_reference.py
```

第一条逐帧打印 JSON 与最后的 parser 统计；第二条运行 13 个测试。`capture_example_summary.json` 已附六传感器数据解释和原始偏移，不需要原采集目录即可阅读；运行 parser 不会重算传感器物理量。

生成命令字节：

```python
from vlp_reference import pack_ping, pack_read, pack_write, StreamParser, decode_response

ping_bytes = pack_ping(sequence=1, echo=b"PING")
read_bytes = pack_read(address=0x0000, count=5, sequence=2)
enable_ptb_bytes = pack_write(address=0x6004, values=[1], sequence=1009)
# 上面生成已按 GPIF 要求补零到 4 字节边界的 wire bytes，没有发送操作。

parser = StreamParser()  # IN 流：帧后补零到 4 字节边界
for frame in parser.feed(some_received_bytes):
    h = frame.header
    if (h['kind'] in (2, 0x7f) and h['sequence'] == 2
            and h['source'] == 1 and h['message'] == 2):
        response = decode_response(frame, 2, 1, 2,
                                   expected_address=0x0000, expected_count=5)
        if response['ok']:
            values = response['values']
        else:
            status = response['status']
    # DATA / EVENT / HEALTH 必须交给独立分发逻辑，不能把下一帧当作响应。
```

此片段中的 `some_received_bytes` 是调用方已有的字节块；离线可用文件分块替代。调用方负责超时、连接生命周期、序号分配、并发串行化与真实发送。发生写入响应超时不能推断“未执行”，也不要盲目重试。

## 文件与证据

- `vlp_reference.py`：40 字节头、CRC-32、PING/READ/simple WRITE、增量帧 parser、响应解析。字段按小端编码；CRC 覆盖头和 payload，外层补零不进入 total/payload length 或 CRC。
- `golden_vectors.json`：三个命令的完整 hex 和 SHA-256，以及三条已保存的真实响应。READ 使用 `0x0000` 开始的 5 个寄存器，seq=2，与原 commands/read_system.bin 完全相同；PTB enable 使用 seq=1009，与原 request_1009.bin 完全相同。真实 READ 响应 seq=1002，不能直接当作 seq=2 请求的匹配响应。PING 响应时间戳为实测值，不是固定的期望常量。
- `capture_example.bin`：656 字节、9 帧，来自 `sensor_six_60s_01/bulk_in.bin` 的不连续片段，保留原字节和原顺序；六路首条可解码采样、BMP390 校准 metadata、READ 与 PTB WRITE 响应。序号跳变是摘录造成，不能据此算丢帧率或采样率。
- `capture_example_summary.json`：原文件 SHA-256、每帧原偏移/新偏移/SHA-256，以及由原 `analyze_sensors.py` 离线生成的解析结果。AI8 首帧 `flags=0x11`、`host_status=0x200`，是 flagged sample；六路存在不等于六路健康。BMP390 ADC 未做 Bosch 补偿，EPSILON 通信 CRC 正确不表示 GNSS 定位有效。
- `test_vlp_reference.py`：拆包/粘包、真实样本、坏 CRC、内嵌帧恢复、长度/版本/补零错误、伪长帧 EOF/超时、响应匹配、资源上限与边界验证。
- `build_examples.py`：可选重建工具，需要原实测目录内已有的 host/commands/reports 文件；只读取这些文件，只在 examples 目录写入产物。普通使用无需运行。

重建命令：

```powershell
python -B examples/build_examples.py E:/Documents/Vapor_Lc_App_Test/fx3_gpif_debug_20260918
```

## 明确的限制

当前集成 `vlp_cmd_rx` 的命令缓存是 4096 字节；此示例限制 PING echo<=4052 字节，READ count<=1021，simple WRITE count<=1011，且地址必须 4 字节对齐、范围不能超过 16-bit 地址空间。source/page 权限和寄存器实际可访问性仍由 FPGA 判定；简单 WRITE 的 option bits 均为 0，不实现 auto-commit、MASK_WRITE 或 action。多字寄存器操作不是原子事务。

parser 默认接受的单帧上限是 8236 字节，对应当前集成 IN 路径的 8192 字节最大 payload 加 40 字节头和 4 字节 CRC。可显式覆盖 `max_frame_bytes`，但应核对实际数据生产端，不能把任意 host 上限称为协议能力。内部待解析缓冲最多为上限向 4 字节取整；每次 feed 返回的帧列表仍与输入量相关，因此应分块读取。错误候选逐字节重同步，默认连续丢弃上限 1 MiB；超过预算抛出 `ResyncLimitError`，调用方须停止使用当前 parser，并决定恢复策略。只保留最近 64 条诊断，累计计数不会丢失。

`pack_ping` / `pack_read` / `pack_write` 输出包含 GPIF 四字节边界补零，可直接作为待发送 wire bytes。补零不进入 header 的 total/payload length 或 CRC；例如 1 字节 PING echo 的 total=45、wire bytes=48、末尾补 3 字节零。通用 `pack_frame` 仍保留可选 `word_padding` 参数，默认 false，用于明确构造不含外层补零的逻辑帧。

如果损坏的头恰好声明了“合法但尚未收齐”的长度，parser 会等待；离线末尾调用 `finish()`，实时应用在自己判定超时后调用 `expire_partial()`。不能用 USB 短包/读调用返回作为 VLP 帧结束。EOF/超时重同步会明确记录丢弃字节。CRC 只能检错，不提供身份认证。
