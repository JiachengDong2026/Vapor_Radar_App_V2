#include "mainwindow.h"
#include "traceplot.h"

#include <QCheckBox>
#include <QComboBox>
#include <QDateTime>
#include <QDoubleSpinBox>
#include <QFileDialog>
#include <QFormLayout>
#include <QFrame>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QLabel>
#include <QMessageBox>
#include <QPainter>
#include <QPainterPath>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSignalBlocker>
#include <QSpinBox>
#include <QScrollArea>
#include <QTabWidget>
#include <QTabBar>
#include <QVBoxLayout>
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
// Nominal AD5791 reference +/-10 V; connector calibration is not implied.
constexpr double wmsFullScaleVolts = 10.0;
const QColor teal("#087f8c");
const QColor orange("#d77825");
QString number(double value, int precision = 5) {
    return std::isfinite(value) ? QString::number(value, 'g', precision) : QStringLiteral("—");
}
QString jsonText(const QJsonValue &value) {
    if (value.isDouble()) return number(value.toDouble(), 7);
    if (value.isString()) return value.toString();
    if (value.isBool()) return value.toBool() ? QStringLiteral("是") : QStringLiteral("否");
    return QStringLiteral("—");
}
QLabel *label(const QString &text, const QString &style = QString()) {
    auto *item = new QLabel(text);
    item->setWordWrap(true);
    if (!style.isEmpty()) item->setStyleSheet(style);
    return item;
}
void setStyleIfChanged(QWidget *widget, const QString &style) {
    if (widget->styleSheet() != style) widget->setStyleSheet(style);
}
QFrame *card() {
    auto *frame = new QFrame;
    frame->setObjectName("card");
    return frame;
}
QDoubleSpinBox *spin(const QString &name, double value, double min, double max,
                     int decimals, const QString &suffix = QString()) {
    auto *box = new QDoubleSpinBox;
    box->setObjectName(name);
    box->setRange(min, max);
    box->setDecimals(decimals);
    box->setValue(value);
    box->setSuffix(suffix);
    box->setKeyboardTracking(false);
    box->setMinimumHeight(32);
    box->setSingleStep(decimals >= 3 ? 0.001 : 1.0);
    return box;
}
bool qualityWarning(const QJsonObject &entry) {
    if (entry.value("stale").toBool() || (quint32(entry.value("flags").toDouble()) & 0x38u)) return true;
    const QString quality = entry.value("quality").toString();
    for (const QString &word : {QStringLiteral("报警"), QStringLiteral("无效"), QStringLiteral("异常"), QStringLiteral("故障"), QStringLiteral("错误"), QStringLiteral("超时"), QStringLiteral("缺片"), QStringLiteral("过期"), QStringLiteral("未有效")})
        if (quality.contains(word)) return true;
    return false;
}
QString qualityText(const QJsonObject &entry) {
    const QString quality = entry.value("quality").toString(QStringLiteral("质量未知"));
    const quint32 flags = quint32(entry.value("flags").toDouble());
    return quality + (flags ? QStringLiteral(" · 标记 0x%1").arg(flags, 0, 16) : QString());
}
}

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    setWindowTitle(QStringLiteral("Vapor · 采集与调制监视器 V0.2.5"));
    resize(1360, 900);
    setMinimumSize(1100, 760);
    setStyleSheet(QStringLiteral(
        "QMainWindow,QWidget#page{background:#f1f5f8;color:#243747;}"
        "QWidget{font-family:'Microsoft YaHei UI','Microsoft YaHei','Segoe UI';font-size:13px;}"
        "QFrame#card{background:white;border:1px solid #dce5ec;border-radius:8px;}"
        "QLabel{border:none;background:transparent;color:#243747;}"
        "QPushButton{background:white;border:1px solid #c7d5df;border-radius:5px;padding:7px 14px;color:#254355;}"
        "QPushButton:hover{background:#e6f3f5;border-color:#7aafb6;}"
        "QPushButton:disabled{background:#eef2f5;color:#9caab4;border-color:#e0e6ec;}"
        "QPushButton#startAcquisition,QPushButton#connectDevice{background:#087f8c;color:white;border-color:#087f8c;}"
        "QPushButton#startAcquisition:disabled,QPushButton#connectDevice:disabled{background:#b8cbd0;color:#f6fafb;border-color:#b8cbd0;}"
        "QTabWidget::pane{border:0;}QTabBar::tab{background:transparent;color:#647b8c;padding:11px 23px;border-bottom:3px solid transparent;}"
        "QTabBar::tab:selected{color:#087f8c;border-bottom:3px solid #087f8c;font-weight:600;}"
        "QComboBox,QDoubleSpinBox,QSpinBox{background:white;border:1px solid #cbd8e1;border-radius:4px;padding:4px 8px;}"
        "QPlainTextEdit{background:#f8fafc;border:1px solid #dce5ec;border-radius:5px;color:#617585;font-size:11px;}"));
    auto *central = new QWidget; central->setObjectName("page"); setCentralWidget(central);
    auto *root = new QVBoxLayout(central); root->setContentsMargins(22, 16, 22, 12); root->setSpacing(10);
    auto *heading = new QHBoxLayout;
    heading->addWidget(label(QStringLiteral("VAPOR  /  采集监视器"), "font-size:23px;font-weight:600;color:#143b4b;"));
    heading->addStretch();
    m_connection = label(QStringLiteral("设备未连接"), "color:#748895;font-weight:600;");
    m_acquisition = label(QStringLiteral("采集未运行"), "color:#748895;font-weight:600;");
    heading->addWidget(m_connection); heading->addSpacing(22); heading->addWidget(m_acquisition); root->addLayout(heading);
    auto *toolbar = new QHBoxLayout; toolbar->setSpacing(8);
    auto button = [&](const QString &title, const QString &name, const QString &action) {
        auto *b = new QPushButton(title); b->setObjectName(name); toolbar->addWidget(b);
        if (!action.isEmpty()) connect(b, &QPushButton::clicked, this, [this, action] { emit requestAction(action, {}); });
        return b;
    };
    m_connect = button(QStringLiteral("连接设备"), "connectDevice", "connect");
    m_start = button(QStringLiteral("开始采集"), "startAcquisition", "start");
    m_stop = button(QStringLiteral("停止采集"), "stopAcquisition", "stop");
    m_disconnect = button(QStringLiteral("断开连接"), "disconnectDevice", "disconnect");
    m_disconnect->setToolTip(QStringLiteral("停止采集并断开 USB；WMS / DAC 保持当前输出。"));
    m_refresh = button(QStringLiteral("刷新状态"), "refreshState", "refresh");
    toolbar->addStretch();
    m_replay = button(QStringLiteral("打开回放"), "openReplay", "");
    m_record = button(QStringLiteral("记录数据"), "recordData", "");
    connect(m_replay, &QPushButton::clicked, this, [this] {
        const QString path = QFileDialog::getOpenFileName(this, QStringLiteral("打开采集数据回放"), QString(), QStringLiteral("采集数据 (*.bin *.vlp *.raw);;所有文件 (*)"));
        if (!path.isEmpty()) emit requestAction("replay", {{"path", path}});
    });
    connect(m_record, &QPushButton::clicked, this, [this] {
        if (m_recording) { emit requestAction("record", {{"path", QString()}}); return; }
        const QString path = QFileDialog::getSaveFileName(this, QStringLiteral("保存采集数据"), "vapor_" + QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss") + ".bin", QStringLiteral("采集数据 (*.bin)"));
        if (!path.isEmpty()) emit requestAction("record", {{"path", path}});
    });
    root->addLayout(toolbar);
    m_message = label(QStringLiteral("连接后可独立控制采集、WMS 扫描和两路 DLIA 解调。"), "color:#617b8a;");
    m_message->setObjectName("statusMessage"); root->addWidget(m_message);
    root->addWidget(label(QStringLiteral("曲线坐标固定 · 滚轮缩放纵轴 · 左键上下拖动平移 · 双击适配当前数据"), "font-size:11px;color:#617b8a;"));
    auto *tabs = new QTabWidget; tabs->setObjectName("mainTabs");
    tabs->tabBar()->setMinimumWidth(800);
    tabs->tabBar()->setExpanding(false);
    tabs->tabBar()->setUsesScrollButtons(false);
    root->addWidget(tabs, 1);

    auto *sensorPage = new QWidget;
    auto *sensorGrid = new QGridLayout(sensorPage); sensorGrid->setContentsMargins(0, 10, 0, 0); sensorGrid->setSpacing(12);
    const QStringList names = {"PTB210", "EPSILON", "BMP390", "SHT45", "TFA1500-L", "AI8"};
    for (int i = 0; i < 6; ++i) {
        auto &s = m_sensors[i]; auto *panel = card(); auto *v = new QVBoxLayout(panel); v->setContentsMargins(14, 11, 14, 10); v->setSpacing(5);
        s.name = label(names[i], "font-size:15px;font-weight:600;"); s.name->setObjectName(QString("sensor%1Name").arg(i)); v->addWidget(s.name);
        s.value = label(QStringLiteral("—"), "font-size:23px;font-weight:600;color:#087f8c;"); v->addWidget(s.value);
        s.fields = label(QStringLiteral("尚无测量值"), "font-size:11px;color:#59717f;");
        s.fields->setTextFormat(Qt::PlainText);
        auto *fieldArea = new QScrollArea; fieldArea->setWidgetResizable(true); fieldArea->setFrameShape(QFrame::NoFrame); fieldArea->setFixedHeight(44); fieldArea->setWidget(s.fields); fieldArea->setStyleSheet("QScrollArea{background:white;border:0;}"); v->addWidget(fieldArea);
        s.plot = new TracePlot; s.plot->setHistoryWindow(60); s.plot->setMinimumHeight(90); s.plot->setObjectName(QString("sensor%1Plot").arg(i)); v->addWidget(s.plot, 1);
        s.quality = label(QStringLiteral("未接收 · 新鲜度未知"), "font-size:11px;color:#8a9aa5;"); v->addWidget(s.quality);
        sensorGrid->addWidget(panel, i / 3, i % 3);
    }
    for (int c = 0; c < 3; ++c) sensorGrid->setColumnStretch(c, 1);
    for (int r = 0; r < 2; ++r) sensorGrid->setRowStretch(r, 1);
    tabs->addTab(sensorPage, QStringLiteral("传感器概览"));

    auto *adcPage = new QWidget; auto *adcLayout = new QVBoxLayout(adcPage); adcLayout->setContentsMargins(0, 10, 0, 0);
    auto *adcTop = new QHBoxLayout;
    adcTop->addWidget(label(QStringLiteral("低速 ADC · 连接器输入电压 / V"), "font-weight:600;font-size:15px;"));
    adcTop->addStretch(); m_raw = new QCheckBox(QStringLiteral("传输原始 ADC 波形")); m_raw->setObjectName("rawEnabled"); adcTop->addWidget(m_raw); adcLayout->addLayout(adcTop);
    connect(m_raw, &QCheckBox::clicked, this, [this](bool enabled) { emit requestAction("raw", {{"enabled", enabled}}); updateState(m_state); });
    adcLayout->addWidget(label(QStringLiteral("按实物增益换算。S3 全 OFF 默认 G = 0.5；更改此选项仅更改电压换算。"), "color:#728795;font-size:12px;"));
    for (int ch = 0; ch < 2; ++ch) {
        auto &a = m_adc[ch]; auto *panel = card(); auto *v = new QVBoxLayout(panel); v->setContentsMargins(14, 10, 14, 9);
        auto *row = new QHBoxLayout; row->addWidget(label(QString("ADC%1 · CON%2").arg(ch).arg(ch ? 16 : 15), "font-size:15px;font-weight:600;"));
        a.summary = label(QStringLiteral("范围 — · 样本 —"), "color:#617b8a;"); row->addWidget(a.summary, 1); row->addWidget(label(QStringLiteral("实物增益")));
        a.gain = new QComboBox; a.gain->setObjectName(QString("adc%1Gain").arg(ch)); a.gain->addItem("0.5  (S3 全 OFF)", 0.5); a.gain->addItem("1.0", 1.0); row->addWidget(a.gain);
        connect(a.gain, &QComboBox::activated, this, [this, ch](int index) { emit requestAction("gain", {{"channel", ch}, {"gain", m_adc[ch].gain->itemData(index).toDouble()}}); });
        v->addLayout(row); a.plot = new TracePlot; a.plot->setLabels(QStringLiteral("周期内时间 / ms"), QStringLiteral("连接器输入 / V")); a.plot->setObjectName(QString("adc%1Plot").arg(ch)); v->addWidget(a.plot, 1);
        a.quality = label(QStringLiteral("未接收"), "font-size:11px;color:#728795;"); v->addWidget(a.quality); adcLayout->addWidget(panel, 1);
    }
    tabs->addTab(adcPage, QStringLiteral("ADC 电压"));

    auto *harmonicPage = new QWidget; auto *harmonicLayout = new QVBoxLayout(harmonicPage); harmonicLayout->setContentsMargins(0, 10, 0, 0);
    harmonicLayout->addWidget(label(QStringLiteral("H1、H2 纵轴各自固定，可独立滚轮缩放；均为原始数字码值。右侧显示最近 10 秒峰值，曲线高度不可直接比较。"), "font-size:12px;color:#728795;"));
    for (int ch = 0; ch < 2; ++ch) {
        auto &h = m_harmonics[ch]; auto *panel = card(); auto *v = new QVBoxLayout(panel); v->setContentsMargins(14, 10, 14, 9);
        auto *head = new QHBoxLayout; head->addWidget(label(QString("通道 %1 · H1 / H2").arg(ch + 1), "font-size:15px;font-weight:600;")); h.summary = label(QStringLiteral("未接收"), "font-size:12px;color:#728795;"); head->addWidget(h.summary, 1); v->addLayout(head);
        auto *plots = new QHBoxLayout;
        h.wave = new TracePlot; h.wave->setLabels(QStringLiteral("周期内时间 / ms"), QStringLiteral("H1 幅值 / code")); h.wave->setObjectName(QString("dlia%1Plot").arg(ch));
        h.h2Wave = new TracePlot; h.h2Wave->setPrimaryColor(orange); h.h2Wave->setLabels(QStringLiteral("周期内时间 / ms"), QStringLiteral("H2 幅值 / code · 独立纵轴")); h.h2Wave->setObjectName(QString("dlia%1H2Plot").arg(ch));
        h.peaks = new TracePlot; h.peaks->setHistoryWindow(10); h.peaks->setPrimaryColor(orange); h.peaks->setLabels(QStringLiteral("时间 / s"), QStringLiteral("H2 周期峰值 / code")); h.peaks->setObjectName(QString("h2%1Peaks").arg(ch)); plots->addWidget(h.wave, 3); plots->addWidget(h.h2Wave, 3); plots->addWidget(h.peaks, 2); v->addLayout(plots, 1); harmonicLayout->addWidget(panel, 1);
    }
    tabs->addTab(harmonicPage, QStringLiteral("谐波与峰值"));

    auto *wmsPage = new QWidget; auto *wmsLayout = new QVBoxLayout(wmsPage); wmsLayout->setContentsMargins(0, 10, 0, 0);
    wmsLayout->addWidget(label(QStringLiteral("双路 WMS 扫描"), "font-size:17px;font-weight:600;"));
    wmsLayout->addWidget(label(QStringLiteral("电压按 DAC ±10 V 参考换算（标称值）。幅度为峰值，峰峰值为其 2 倍；偏置为直流电压。"), "color:#617b8a;"));
    auto *wmsRows = new QHBoxLayout; wmsRows->setSpacing(16);
    for (int ch = 0; ch < 2; ++ch) {
        auto &w = m_wms[ch]; auto *panel = card(); auto *v = new QVBoxLayout(panel); v->setContentsMargins(22, 18, 22, 18); v->setSpacing(14);
        auto *titleRow = new QHBoxLayout;
        titleRow->addWidget(label(QString("WMS %1").arg(ch + 1), "font-size:19px;font-weight:600;color:#164d61;"));
        titleRow->addStretch(); w.load = new QPushButton(QStringLiteral("载入设备参数")); w.load->setObjectName(QString("wms%1Load").arg(ch)); titleRow->addWidget(w.load); v->addLayout(titleRow);
        connect(w.load, &QPushButton::clicked, this, [this, ch] { loadWmsParameters(ch); });
        auto *form = new QFormLayout; form->setVerticalSpacing(13); form->setLabelAlignment(Qt::AlignLeft | Qt::AlignVCenter);
        w.sawHz = spin(QString("wms%1SawHz").arg(ch), 100, 100, 1000, 3, " Hz");
        w.sineHz = spin(QString("wms%1SineHz").arg(ch), 20000, 1000, 100000, 3, " Hz");
        w.sawAmp = spin(QString("wms%1SawAmplitude").arg(ch), 0.5, 0, 10, 4, " V");
        w.sineAmp = spin(QString("wms%1SineAmplitude").arg(ch), 0.1, 0, 10, 4, " V");
        w.offset = spin(QString("wms%1Offset").arg(ch), 0, -10, 10, 4, " V");
        w.phase = spin(QString("wms%1Phase").arg(ch), ch ? 90 : 0, 0, 359.999, 3, QStringLiteral(" °"));
        form->addRow(QStringLiteral("锯齿波频率 / 100–1000 Hz"), w.sawHz); form->addRow(QStringLiteral("正弦波频率 / 1–100 kHz"), w.sineHz);
        form->addRow(QStringLiteral("锯齿波峰值 / V"), w.sawAmp); form->addRow(QStringLiteral("正弦波峰值 / V"), w.sineAmp);
        form->addRow(QStringLiteral("直流偏置 / V"), w.offset); form->addRow(QStringLiteral("正弦波相位"), w.phase); v->addLayout(form);
        w.readback = label(QStringLiteral("设备回读：未知"), "background:#f0f6f8;border-radius:5px;padding:10px;color:#587786;font-size:12px;"); w.readback->setObjectName(QString("wms%1Readback").arg(ch)); w.readback->setMinimumHeight(76); v->addWidget(w.readback);
        auto *controls = new QHBoxLayout; w.apply = new QPushButton(QStringLiteral("应用并启用")); w.apply->setObjectName(QString("wms%1Apply").arg(ch)); w.start = new QPushButton(QStringLiteral("启动扫描")); w.start->setObjectName(QString("wms%1Start").arg(ch)); w.start->setToolTip(QStringLiteral("使用设备中已提交的参数启动扫描；不会提交编辑框中的修改。")); w.stop = new QPushButton(QStringLiteral("停止扫描")); w.stop->setObjectName(QString("wms%1Stop").arg(ch)); controls->addWidget(w.apply); controls->addWidget(w.start); controls->addWidget(w.stop); v->addLayout(controls);
        connect(w.apply, &QPushButton::clicked, this, [this, ch] {
            const auto &item = m_wms[ch];
            if (std::abs(item.offset->value()) + item.sawAmp->value() + item.sineAmp->value() > 9.50000000001) {
                QMessageBox::warning(this, QStringLiteral("输出幅度超出范围"), QStringLiteral("请将 |偏置| + 锯齿波幅度 + 正弦波幅度 调整至不超过 9.5 V。"));
                return;
            }
            emit requestAction("wms_apply", {{"channel", ch}, {"sawHz", item.sawHz->value()}, {"sineHz", item.sineHz->value()}, {"sawAmplitude", item.sawAmp->value() / wmsFullScaleVolts}, {"sineAmplitude", item.sineAmp->value() / wmsFullScaleVolts}, {"offset", item.offset->value() / wmsFullScaleVolts}, {"phaseDeg", item.phase->value()}});
        });
        connect(w.start, &QPushButton::clicked, this, [this, ch] { emit requestAction("wms_start", {{"channel", ch}}); });
        connect(w.stop, &QPushButton::clicked, this, [this, ch] { emit requestAction("wms_stop", {{"channel", ch}}); });
        v->addStretch(); wmsRows->addWidget(panel, 1);
    }
    wmsLayout->addLayout(wmsRows, 1);
    wmsLayout->addWidget(label(QStringLiteral("标称输出：CON27/28 接 3–4、高阻负载时约等于设置电压；其他接法需实测标定。|偏置| + 两个峰值 ≤ 9.5 V。停止 WMS 后 DAC 保持末值；受当前设备限制，该路扫描分帧也停止。断开连接保留 WMS / DAC 输出。"), "color:#9c6a30;font-size:12px;"));
    tabs->addTab(wmsPage, QStringLiteral("WMS 控制"));

    auto *dliaPage = new QWidget;
    auto *dliaLayout = new QVBoxLayout(dliaPage); dliaLayout->setContentsMargins(0, 10, 0, 0); dliaLayout->setSpacing(8);
    dliaLayout->addWidget(label(QStringLiteral("双路 DLIA 解调参数"), "font-size:17px;font-weight:600;"));
    dliaLayout->addWidget(label(QStringLiteral("应用/启动会短暂停止对应 ADC，重置该路滤波和缓存。启动解调会开启对应 ADC；另一通道继续运行。"), "color:#617b8a;font-size:12px;"));
    auto *dliaRows = new QHBoxLayout; dliaRows->setSpacing(16);
    for (int ch = 0; ch < 2; ++ch) {
        auto &d = m_dlia[ch]; auto *panel = card(); auto *v = new QVBoxLayout(panel); v->setContentsMargins(18, 14, 18, 14); v->setSpacing(10);
        auto *titleRow = new QHBoxLayout; titleRow->addWidget(label(QString("DLIA %1").arg(ch + 1), "font-size:19px;font-weight:600;color:#164d61;")); titleRow->addStretch();
        d.load = new QPushButton(QStringLiteral("载入设备参数")); d.load->setObjectName(QString("dlia%1Load").arg(ch)); titleRow->addWidget(d.load); v->addLayout(titleRow);
        d.referenceMode = new QComboBox; d.referenceMode->setObjectName(QString("dlia%1ReferenceMode").arg(ch)); d.referenceMode->addItem(QStringLiteral("独立参考"), 0); d.referenceMode->addItem(QStringLiteral("跟随对应 WMS"), 1); d.referenceMode->setMinimumHeight(32);
        d.referenceHz = spin(QString("dlia%1ReferenceHz").arg(ch), 20000, 0.001, 1000000, 3, " Hz");
        d.referenceHz->setToolTip(QStringLiteral("独立参考模式下使用该频率；跟随 WMS 时使用对应通道的参考。"));
        d.phase1 = spin(QString("dlia%1Phase1Deg").arg(ch), 0, 0, 359.999, 3, QStringLiteral(" °"));
        d.phase2 = spin(QString("dlia%1Phase2Deg").arg(ch), 0, 0, 359.999, 3, QStringLiteral(" °"));
        d.outputHz = new QSpinBox; d.outputHz->setObjectName(QString("dlia%1OutputHz").arg(ch)); d.outputHz->setRange(1, 125000); d.outputHz->setValue(10000); d.outputHz->setSuffix(" Hz"); d.outputHz->setMinimumHeight(32); d.outputHz->setKeyboardTracking(false);
        d.fragmentPoints = new QSpinBox; d.fragmentPoints->setObjectName(QString("dlia%1FragmentPoints").arg(ch)); d.fragmentPoints->setRange(1, 256); d.fragmentPoints->setValue(256); d.fragmentPoints->setMinimumHeight(32); d.fragmentPoints->setKeyboardTracking(false);
        d.lpfBypass = new QCheckBox(QStringLiteral("旁路低通滤波")); d.lpfBypass->setObjectName(QString("dlia%1LpfBypass").arg(ch));
        auto *form = new QFormLayout; form->setVerticalSpacing(8); form->setLabelAlignment(Qt::AlignLeft | Qt::AlignVCenter);
        form->addRow(QStringLiteral("参考来源"), d.referenceMode); form->addRow(QStringLiteral("独立参考频率"), d.referenceHz);
        form->addRow(QStringLiteral("H1 参考相位"), d.phase1); form->addRow(QStringLiteral("H2 参考相位"), d.phase2);
        form->addRow(QStringLiteral("目标输出速率"), d.outputHz); form->addRow(QStringLiteral("每分片点数"), d.fragmentPoints); form->addRow(QStringLiteral("低通滤波"), d.lpfBypass); v->addLayout(form);
        d.readback = label(QStringLiteral("设备回读：未知"), "background:#f0f6f8;border-radius:5px;padding:9px;color:#587786;font-size:12px;"); d.readback->setObjectName(QString("dlia%1Readback").arg(ch)); d.readback->setMinimumHeight(96); v->addWidget(d.readback);
        auto *controls = new QHBoxLayout;
        d.apply = new QPushButton(QStringLiteral("应用参数")); d.apply->setObjectName(QString("dlia%1Apply").arg(ch)); d.apply->setToolTip(QStringLiteral("应用编辑参数并保留当前通道的运行状态。"));
        d.start = new QPushButton(QStringLiteral("启动解调")); d.start->setObjectName(QString("dlia%1Start").arg(ch)); d.start->setToolTip(QStringLiteral("使用已提交参数启动对应 ADC 和 DLIA，不提交编辑框；需对应 WMS 已运行。"));
        d.stop = new QPushButton(QStringLiteral("停止解调")); d.stop->setObjectName(QString("dlia%1Stop").arg(ch));
        controls->addWidget(d.apply); controls->addWidget(d.start); controls->addWidget(d.stop); v->addLayout(controls); v->addStretch();
        connect(d.load, &QPushButton::clicked, this, [this, ch] { loadDliaParameters(ch); });
        connect(d.apply, &QPushButton::clicked, this, [this, ch] {
            const auto &item = m_dlia[ch];
            emit requestAction("dlia_apply", {{"channel", ch}, {"referenceMode", item.referenceMode->currentData().toInt()}, {"referenceHz", item.referenceHz->value()}, {"phase1Deg", item.phase1->value()}, {"phase2Deg", item.phase2->value()}, {"outputHz", item.outputHz->value()}, {"lpfBypass", item.lpfBypass->isChecked()}, {"fragmentPoints", item.fragmentPoints->value()}});
        });
        connect(d.start, &QPushButton::clicked, this, [this, ch] { emit requestAction("dlia_start", {{"channel", ch}}); });
        connect(d.stop, &QPushButton::clicked, this, [this, ch] { emit requestAction("dlia_stop", {{"channel", ch}}); });
        dliaRows->addWidget(panel, 1);
    }
    dliaLayout->addLayout(dliaRows, 1);
    dliaLayout->addWidget(label(QStringLiteral("两路幅值计算始终启用。低通滤波系数为当前设备固定配置，带宽不可调；可选择旁路。停止 WMS 后，该路扫描分帧也停止。"), "color:#9c6a30;font-size:12px;"));
    auto *dliaScroll = new QScrollArea; dliaScroll->setWidgetResizable(true); dliaScroll->setFrameShape(QFrame::NoFrame); dliaScroll->setWidget(dliaPage);
    tabs->addTab(dliaScroll, QStringLiteral("DLIA 参数"));

    auto *bottom = new QHBoxLayout; bottom->addWidget(label(QStringLiteral("运行日志"), "font-size:11px;font-weight:600;color:#728795;")); bottom->addStretch();
    m_statistics = label(QStringLiteral("帧 —  ·  CRC 错误 —"), "font-size:11px;color:#728795;"); m_statistics->setWordWrap(false); bottom->addWidget(m_statistics); root->addLayout(bottom);
    m_log = new QPlainTextEdit; m_log->setObjectName("eventLog"); m_log->setReadOnly(true); m_log->setMaximumBlockCount(300); m_log->setFixedHeight(67); root->addWidget(m_log);
    updateState({});
}

void MainWindow::updateSnapshot(const QJsonObject &snapshot) {
    const auto sensors = snapshot.value("sensors").toArray();
    for (int i = 0; i < 6; ++i) {
        const QJsonObject entry = i < sensors.size() ? sensors[i].toObject() : QJsonObject(); auto &s = m_sensors[i];
        if (!entry.value("name").toString().isEmpty()) s.name->setText(entry.value("name").toString());
        const auto fields = entry.value("fields").toObject(); QStringList pieces;
        for (auto it = fields.begin(); it != fields.end(); ++it) pieces << it.key() + QStringLiteral("  ") + jsonText(it.value());
        s.fields->setText(pieces.isEmpty() ? QStringLiteral("尚无测量值") : pieces.join(QStringLiteral("    ·    ")));
        const QString trendLabel = entry.value("trendLabel").toString(); const QString unit = entry.value("trendUnit").toString(); const auto trend = entry.value("trend").toArray();
        QJsonValue latest;
        for (int p = trend.size() - 1; p >= 0; --p) { const auto pair = trend[p].toArray(); if (pair.size() >= 2 && pair[1].isDouble()) { latest = pair[1]; break; } }
        s.value->setText(latest.isDouble() ? number(latest.toDouble(), 6) + " " + unit : QStringLiteral("—"));
        s.plot->setLabels(QStringLiteral("时间 / s"), trendLabel + (unit.isEmpty() ? QString() : " / " + unit)); s.plot->setSeries(trend);
        QString freshness = QStringLiteral("新鲜度未知");
        if (entry.value("ageMs").isDouble()) freshness = QStringLiteral("%1 s 前更新").arg(number(entry.value("ageMs").toDouble() / 1000.0, 3));
        if (entry.value("stale").toBool()) freshness += QStringLiteral(" · 数据陈旧");
        s.quality->setText(qualityText(entry) + QStringLiteral(" · ") + freshness);
        setStyleIfChanged(s.quality, qualityWarning(entry) ? "font-size:11px;color:#ae6b29;" : "font-size:11px;color:#728795;");
    }
    const auto adc = snapshot.value("adc").toArray();
    for (int ch = 0; ch < 2; ++ch) {
        const auto entry = ch < adc.size() ? adc[ch].toObject() : QJsonObject(); auto &a = m_adc[ch];
        a.plot->setSeries(entry.value("points").toArray());
        a.summary->setText(QStringLiteral("累计范围 %1 … %2 V  ·  累计样本 %3  ·  显示周期 %4").arg(jsonText(entry.value("minV")), jsonText(entry.value("maxV")), jsonText(entry.value("count")), jsonText(entry.value("cycle"))));
        QString detail = qualityText(entry);
        if (entry.value("ageMs").isDouble()) detail += QStringLiteral(" · %1 s 前更新").arg(number(entry.value("ageMs").toDouble() / 1000.0, 3));
        if (entry.value("stale").toBool()) detail += QStringLiteral(" · 数据陈旧");
        a.quality->setText(detail);
        if (entry.value("gain").isDouble()) { QSignalBlocker blocker(a.gain); a.gain->setCurrentIndex(entry.value("gain").toDouble() == 1.0 ? 1 : 0); }
    }
    const auto dlia = snapshot.value("dlia").toArray();
    for (int ch = 0; ch < 2; ++ch) {
        const auto entry = ch < dlia.size() ? dlia[ch].toObject() : QJsonObject(); auto &h = m_harmonics[ch];
        h.wave->setSeries(entry.value("h1").toArray()); h.h2Wave->setSeries(entry.value("h2").toArray()); h.peaks->setSeries(entry.value("peaks").toArray());
        QString detail = qualityText(entry);
        if (entry.value("ageMs").isDouble()) detail += QStringLiteral(" · %1 s 前更新").arg(number(entry.value("ageMs").toDouble() / 1000.0, 3));
        if (entry.value("stale").toBool()) detail += QStringLiteral(" · 数据陈旧");
        h.summary->setText(QStringLiteral("周期 %1  ·  %2").arg(jsonText(entry.value("cycle")), detail));
    }
}

void MainWindow::updateState(const QJsonObject &state) {
    m_state = state;
    const bool connected = state.value("connected").toBool(), ready = state.value("ready").toBool();
    const bool busy = state.value("busy").toBool(), acquiring = state.value("acquiring").toBool(), replaying = state.value("replaying").toBool();
    const auto regs = state.value("registers").toObject();
    m_connection->setText(connected ? (ready ? QStringLiteral("● 设备已就绪") : QStringLiteral("● 设备已连接")) : QStringLiteral("○ 设备未连接"));
    setStyleIfChanged(m_connection, connected ? "color:#087f8c;font-weight:600;" : "color:#748895;font-weight:600;");
    m_acquisition->setText(replaying ? QStringLiteral("● 数据回放") : acquiring ? QStringLiteral("● 正在采集") : busy ? QStringLiteral("处理中…") : QStringLiteral("采集未运行"));
    setStyleIfChanged(m_acquisition, acquiring || replaying ? "color:#087f8c;font-weight:600;" : "color:#748895;font-weight:600;");
    if (state.contains("message")) m_message->setText(state.value("message").toString());
    m_connect->setEnabled(!connected && !busy && !replaying); m_disconnect->setEnabled(connected && !busy);
    m_start->setEnabled(connected && ready && !busy && !acquiring);
    m_start->setToolTip(QStringLiteral("启动采集与传感器监视；WMS 和 DLIA 可独立控制。"));
    m_stop->setEnabled(connected && acquiring && !busy); m_refresh->setEnabled(connected && !busy);
    m_replay->setEnabled(!connected && !busy && !replaying); m_raw->setEnabled(connected && ready && !busy);
    { QSignalBlocker blocker(m_raw); m_raw->setChecked(state.value("raw").toBool()); }
    m_recording = state.value("recording").toBool(); m_record->setText(m_recording ? QStringLiteral("停止记录") : QStringLiteral("记录数据")); m_record->setEnabled(!busy && (connected || m_recording));
    for (int ch = 0; ch < 2; ++ch) {
        auto &w = m_wms[ch]; const bool editable = connected && ready && !busy;
        w.apply->setEnabled(editable); w.start->setEnabled(editable); w.stop->setEnabled(editable);
        w.load->setEnabled(editable && w.loaded);
        for (auto *box : {w.sawHz, w.sineHz, w.sawAmp, w.sineAmp, w.offset, w.phase}) box->setEnabled(!busy);
        const quint32 base = ch ? 0x2100 : 0x2000;
        auto value = [&](quint32 offset) { return regs.value(QString::number(base + offset, 16)); };
        QString summary = QStringLiteral("设备回读：未知");
        if (connected && value(4).isDouble()) {
            summary = (quint32(value(4).toDouble()) & 1) ? QStringLiteral("设备回读：扫描运行中") : QStringLiteral("设备回读：扫描已停用（DAC 保持）");
            if (value(0x10).isDouble() && value(0x1c).isDouble()) summary += QStringLiteral("\n锯齿 %1 Hz · 正弦 %2 Hz").arg(number(value(0x10).toDouble() / 1000.0), number(value(0x1c).toDouble() / 1000.0));
            if (value(0x14).isDouble() && value(0x20).isDouble()) summary += QStringLiteral("\n标称峰值：锯齿 %1 V · 正弦 %2 V").arg(number(double(qint32(quint32(value(0x14).toDouble()))) * wmsFullScaleVolts / 2147483648.0), number(double(qint32(quint32(value(0x20).toDouble()))) * wmsFullScaleVolts / 2147483648.0));
            if (value(0x18).isDouble()) summary += QStringLiteral(" · 偏置 %1 V").arg(number(double(qint32(quint32(value(0x18).toDouble()))) * wmsFullScaleVolts / 2147483648.0));
        } else if (!connected) summary = QStringLiteral("设备回读：未连接，当前输出状态未知");
        w.readback->setText(summary);
        if (!connected) w.loaded = false;
        else if (ready && !w.loaded) w.loaded = loadWmsParameters(ch);
        w.load->setEnabled(editable && w.loaded);
    }
    for (int ch = 0; ch < 2; ++ch) {
        auto &d = m_dlia[ch]; const bool editable = connected && ready && !busy;
        d.apply->setEnabled(editable); d.start->setEnabled(editable); d.stop->setEnabled(editable);
        d.referenceMode->setEnabled(!busy); d.referenceHz->setEnabled(!busy);
        d.phase1->setEnabled(!busy); d.phase2->setEnabled(!busy); d.outputHz->setEnabled(!busy);
        d.lpfBypass->setEnabled(!busy); d.fragmentPoints->setEnabled(!busy);
        const quint32 base = ch ? 0x5100 : 0x5000;
        auto value = [&](quint32 offset) { return regs.value(QString::number(base + offset, 16)); };
        QString summary = QStringLiteral("设备回读：未知");
        if (connected && value(4).isDouble()) {
            summary = (quint32(value(4).toDouble()) & 1) ? QStringLiteral("设备回读：解调运行中") : QStringLiteral("设备回读：解调已停止");
            if(quint32(value(4).toDouble())&1){
                const auto channels=state.value("dliaData").toArray();
                const auto data=ch<channels.size()?channels[ch].toObject():QJsonObject();
                if(!(quint32(regs.value(QString::number(0x4004+ch*0x100,16)).toDouble())&1))summary=QStringLiteral("解调已启用，等待对应 ADC 采集");
                else if(!(quint32(regs.value(QString::number(0x2004+ch*0x100,16)).toDouble())&1))summary=QStringLiteral("解调已启用，等待对应 WMS 扫描边界");
                else if(!data.value("displayFullCycle").toBool()||data.value("stale").toBool(true))summary=QStringLiteral("解调已启用，等待新的完整谐波帧");
                else summary=QStringLiteral("解调运行中，谐波数据正在更新");
            }
            if (value(0x20).isDouble()) {
                const quint32 mode = quint32(value(0x20).toDouble());
                summary += (mode & 1) ? QStringLiteral(" · 跟随 WMS") : QStringLiteral(" · 独立参考");
                summary += (mode & 2) ? QStringLiteral(" · 幅值已启用") : QStringLiteral(" · 幅值未启用");
                summary += (mode & 4) ? QStringLiteral(" · LPF 旁路") : QStringLiteral(" · 固定 LPF");
            }
            if (value(0x10).isDouble()) summary += QStringLiteral("\n设定参考 %1 Hz").arg(number(value(0x10).toDouble() / 1000.0, 8));
            if (value(0x14).isDouble() && value(0x18).isDouble()) summary += QStringLiteral(" · 相位 %1° / %2°").arg(number(value(0x14).toDouble() / 4294967296.0 * 360.0, 6), number(value(0x18).toDouble() / 4294967296.0 * 360.0, 6));
            summary += QStringLiteral("\n目标 / 实际输出 %1 / %2 Hz · 抽取 %3").arg(jsonText(value(0x1c)), jsonText(value(0x4c)), jsonText(value(0x50)));
            summary += QStringLiteral(" · 分片 %1 点 · 固定 LPF 配置 %2").arg(jsonText(value(0x40)), jsonText(value(0x24)));
            const quint32 profile = quint32(value(0x24).toDouble());
            if (profile == 0x00040101u) summary += QStringLiteral("（四阶，1 kHz / 1 MS/s）");
            else if (profile == 0x00020101u) summary += QStringLiteral("（二阶，1 kHz / 1 MS/s）");
        } else if (!connected) summary = QStringLiteral("设备回读：未连接，当前解调状态未知");
        d.readback->setText(summary);
        if (!connected) d.loaded = false;
        else if (ready && !d.loaded) d.loaded = loadDliaParameters(ch);
        d.load->setEnabled(editable && d.loaded);
    }
    const auto stats = state.value("stats").toObject();
    m_statistics->setText(QStringLiteral("帧 %1  ·  CRC 错误 %2  ·  结构错误 %3").arg(jsonText(stats.value("frames")), jsonText(stats.value("crcErrors")), jsonText(stats.value("framingErrors"))));
}

bool MainWindow::loadWmsParameters(int channel) {
    if (!m_state.value("connected").toBool()) return false;
    const auto regs = m_state.value("registers").toObject(); const quint32 base = channel ? 0x2100 : 0x2000;
    auto value = [&](quint32 offset) { return regs.value(QString::number(base + offset, 16)); };
    for (quint32 offset : {0x10u, 0x14u, 0x18u, 0x1cu, 0x20u, 0x24u}) if (!value(offset).isDouble()) return false;
    auto &w = m_wms[channel];
    w.sawHz->setValue(value(0x10).toDouble() / 1000.0); w.sineHz->setValue(value(0x1c).toDouble() / 1000.0);
    w.sawAmp->setValue(double(qint32(quint32(value(0x14).toDouble()))) * wmsFullScaleVolts / 2147483648.0);
    w.sineAmp->setValue(double(qint32(quint32(value(0x20).toDouble()))) * wmsFullScaleVolts / 2147483648.0);
    w.offset->setValue(double(qint32(quint32(value(0x18).toDouble()))) * wmsFullScaleVolts / 2147483648.0);
    w.phase->setValue(value(0x24).toDouble() / 4294967296.0 * 360.0); return true;
}

bool MainWindow::loadDliaParameters(int channel) {
    if (!m_state.value("connected").toBool()) return false;
    const auto regs = m_state.value("registers").toObject(); const quint32 base = channel ? 0x5100 : 0x5000;
    auto value = [&](quint32 offset) { return regs.value(QString::number(base + offset, 16)); };
    for (quint32 offset : {0x10u, 0x14u, 0x18u, 0x1cu, 0x20u, 0x40u}) if (!value(offset).isDouble()) return false;
    auto &d = m_dlia[channel]; const quint32 mode = quint32(value(0x20).toDouble());
    d.referenceMode->setCurrentIndex((mode & 1) ? 1 : 0); d.referenceHz->setValue(value(0x10).toDouble() / 1000.0);
    d.phase1->setValue(value(0x14).toDouble() / 4294967296.0 * 360.0); d.phase2->setValue(value(0x18).toDouble() / 4294967296.0 * 360.0);
    d.outputHz->setValue(value(0x1c).toInt()); d.lpfBypass->setChecked((mode & 4) != 0); d.fragmentPoints->setValue(value(0x40).toInt()); return true;
}

void MainWindow::appendLog(const QString &message) {
    m_log->appendPlainText(QDateTime::currentDateTime().toString("HH:mm:ss") + "  " + message);
}
