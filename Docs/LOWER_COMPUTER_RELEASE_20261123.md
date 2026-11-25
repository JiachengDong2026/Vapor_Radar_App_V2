# 2026-11-23 下位机版本：PPS、可调SOS与启动观测

本版BIT于2026-11-23使用Vivado 2020.2完成构建，2026-11-25归档至GitHub，目标器件为Xilinx XCKU11P-2FFVA1156I。版本分支`codex/release-20261123-start-outputs`，标签`fpga-20261123-start-outputs`。

源码基于`48abb8f`，包含既有双AD4630、WMS/DAC、两路DLIA、传感器、温控UART桥和电机接口，以及本轮新增的三路真实事件观测及DLIA参考流水修复。GitHub main的后续提交`0bfb750`（丢帧后完整周期恢复）不属于本版BIT；该修复仍保留在main，本标签用于准确还原本次已验证镜像。后续若合并main或修改RTL，须重新构建和签核，不应继续使用本版BIT的验证结论。

## 功能与使用

| 功能 | 本版行为 |
|---|---|
| DLIA阶数 | 双路独立配置2、3、4、5、6、7、8阶SOS，默认内置四阶 |
| 截止频率 | 内置100/250/500/1000/2000/5000/10000Hz档位，默认1kHz；自定义由上位机按实际Fs、阶数和Fc设计并上传整组系数 |
| 自定义滤波提交 | 完整系数银行、稳定性和节形状校验，边界原子提交，生效配置可读回；单写Fc元数据不会自动生成系数 |
| PPS同步扫描 | 每路可选合格PPS启动一次WMS扫描，DLIA按实际DAC窗口接收并排空；上电仍为连续模式 |
| 启动观测 | ADC_START、DLIA1_START、DLIA2_START，3.3V、10us脉冲 |
| DLIA参考流水 | 插值参考与混频乘法之间增加一级寄存器，样本和194位标签同步延迟；混频结果增加10ns，吞吐及START事件定义不变 |

SOS能力由两路DLIA寄存器页`0x5000/0x5100`的`+0xF0=0x534F5301`识别，WMS PPS能力由`+0x84=0x50505301`识别。上传步骤、配置生效条件及异常处理以[SOS对接](protocol/DLIA_SOS_HOST_HANDOFF_20261116.md)、[PPS对接](protocol/PPS_WMS_DLIA_HOST_HANDOFF_20261116.md)为准。Qt界面是否暴露配置取决于上位机版本，本次归档没有新增Qt控件。

| 输出 | 接口 | FPGA ball | 标记事件 |
|---|---|---|---|
| ADC_START | CON11-12 | AL12 | 双路PPS窗口首采样共用的实际CNV |
| DLIA1_START | CON11-14 | AE13 | DLIA1实际接受窗口首个有效样本 |
| DLIA2_START | CON11-16 | AF13 | DLIA2实际接受窗口首个有效样本 |

连续模式不输出这些PPS观测脉冲。两路ADC首次采样错位或单路工作时不输出共同ADC_START，缺失不能视为零延迟。CON11无GND，示波器参考地需接已确认板卡地（例如CON21-4），使用高阻探头。完整接线、测试条件和测量限制见[启动观测规范](integration/MEASUREMENT_START_OUTPUTS_20261119.md)。

## 镜像与复核

BIT：[vapor_lidar_start_outputs_20261123.bit](../firmware/fpga/releases/20261123_start_outputs/vapor_lidar_start_outputs_20261123.bit)，23581028字节。

SHA256：`21f786684b501f91d7254f68e9a207aeaecc0ce4c8d9d44ba176177406346b4a`。

配套[归档目录](../firmware/fpga/releases/20261123_start_outputs/README.md)保存原始字节及LF规范化的构建输入哈希、回归源哈希、116项结果和构建摘要；不提交Vivado工程、DCP、波形或大体积报告。BIT与本标签源码可用以下命令核验：

```powershell
python -B firmware/fpga/releases/20261123_start_outputs/verify.py
python -B fpga/scripts/check_baseline.py
```

## 已完成验证与边界

- 116项Vivado/XSim全量回归全部通过，包括SOS系数上传、截止频率、数值精度、PPS整机、启动观测、参考/样本/标签对齐、STOP排空和复位恢复；250项回归源哈希一致。
- 公共Vivado仿真、综合、timing、CDC、check_timing与资源检查完成。
- 全新整机综合、布局、布线及BIT生成通过；283954/283954条可布线网络完成，路由错误0。
- WNS=+0.009ns、TNS=0、setup失败端点0；WHS报告值0.000ns、THS=0、hold失败端点0。余量很小，hold数值被报告舍入至0.000ns。
- 最终布线DRC为4861条Warning，0 Error、0 Critical Warning；时钟脉宽无违例。check_timing唯一预期例外为转发时钟FPGA_GPIF_PCLK的no_output_delay。
- CDC逐端点与此前PPS基线2/2一致，保留既有CDC-10 Critical一项和CDC-3 Info一项；复位链和UART同步器只读网表复核通过，不能称为CDC零Critical。
- 三路观测输出最终网表、管脚、电平及setup/hold检查通过；DAC/AD4630管脚时序预算检查通过，最小余量7.409ns/2.571ns；bus skew无违例。

首次实现未收敛而停止，无BIT。随后增加参考流水并重新运行全量回归和全新整机构建，最终镜像只对应修复后的结果。23个已审阅USB/FIFO Gray一级同步端点执行局部保持时间重布线，原始时钟和I/O约束未放宽。完整过程及本地报告位置见[实现记录](integration/MEASUREMENT_START_OUTPUTS_20261119.md)。

本版BIT尚未下载到板卡或写入Flash，尚未进行测试大纲4.11“小于1ms”实板验收。START测首样本启动，不代表低通群延迟、滤波建立时间或USB数据到达时间。
