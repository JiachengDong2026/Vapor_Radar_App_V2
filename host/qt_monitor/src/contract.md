# Internal implementation contract

Qt 6.11.2 C++17. Reference host implementation V0.2.5, imported 2026-10-11. Build products and captures belong outside this repository.

## Protocol API (protocol.h/.cpp)

```
struct VlpFrame {
 quint8 kind; quint32 sequence; quint16 source, message;
 quint32 flags; quint64 ticks; quint32 cycle; QByteArray payload;
};
class VlpParser {
 public: QVector<VlpFrame> feed(const QByteArray &bytes);
 void reset(); QJsonObject statistics() const;
 static QByteArray command(quint32 sequence, bool write, quint32 address, const QVector<quint32>& values, quint32 readCount=1);
};
class DataDecoder {
 public: void accept(const VlpFrame &frame); QJsonObject snapshot() const;
 void reset(); void setAdcGain(int channel, double gain);
};
```

VlpParser statistics keys: frames, crcErrors, framingErrors, paddingErrors, bytes.
DataDecoder snapshot keys: sensors (array six entries), adc (two entries), dlia (two entries).
Sensor entry: name, source (int), fields (object human Chinese names -> number/string), quality (string), flags (int), ticks (double), count (number), trend (array [seconds,value]), trendLabel (string), trendUnit (string).
ADC entry: channel, count, minV, maxV, gain, cycle, flags, points (array [milliseconds, connectorVolts]), quality (string).
DLIA entry: channel, count, cycle, flags, h1/h2 (array [milliseconds,digitalAmplitude]), peaks (array [seconds,h2Peak]), quality (string).
Only complete fragments produce cycles. Keep bounded histories. Downsample min/max preserving extrema to <=1200 plot points. RAW CON15 sign +, CON16 sign -, VREF5V, gain default0.5; never fit to setpoints. H1/H2 stay code. Quality flags and stale values remain explicit, missing is not zero.

## MainWindow API (mainwindow.h/.cpp)

```
class MainWindow : public QMainWindow {
 Q_OBJECT
 public: explicit MainWindow(QWidget *parent=nullptr);
 signals: void requestAction(const QString &action, const QJsonObject &parameters);
 public slots: void updateSnapshot(const QJsonObject&); void updateState(const QJsonObject&);
 void appendLog(const QString&);
};
```

Actions: connect, disconnect, start, stop, raw {enabled:bool}, wms_apply {channel:0/1,sawHz:100,sineHz:20000,sawAmplitude:0.05,sineAmplitude:0.01,offset:0,phaseDeg:0/90}, wms_stop {channel}, refresh, gain {channel,gain:0.5/1}, replay {path:string}, record {path:string; empty stops}.
State keys connected, ready, acquiring, replaying, busy, raw (bool); message (string); registers (object lowercase hex address without 0x -> numeric value), stats (parser statistics).
No hidden enabling on connect; WMS and DLIA controls are independent of acquisition. Complete RAW/DLIA scan frames require corresponding WMS scan boundaries. Apply WMS is explicit start and uses amplitude/offset normalized to full scale, NOT volts. Defaults are board-proven100Hz/20kHz/0.05/0.01, 500k update fixed. Stop WMS holds last DAC value (explicit UI label); no zero claim. WMS can be applied/started/stopped during acquisition; commands remain serialized. Disconnect stops only acquisition/sensors/RAW; preserves WMS/DAC. UI should disable unsafe duplicate/busy actions, reflect readback instead of optimistic success. Plot refresh ~5Hz.

worker.h/.cpp owns command sequencing, USB process management, recording and replay. bridge/VaporUsbBridge.cs handles CyUSB transport.

UI requirements: Chinese; tabs overview/six sensors, ADC, harmonics, WMS control; quality/freshness visible, trace gaps not fabricated. Provide replay browse and recording path. No dependency on QtCharts; custom QPainter plot is acceptable. MainWindow should use object names for testing. No hardware access from UI implementation.

## V0.2.5 WMS voltage UI (2026-10-09)
WMS edit fields and readback use nominal volts with a +/-10 V AD5791 reference. Amplitudes are peak (Vpp = 2 * peak), offset is DC volts. The UI divides by 10 before emitting wms_apply; action payloads and device registers remain normalized Q1.31. Default 0.5 V / 0.1 V maps to the original 0.05 / 0.01. UI sum limit is 9.5 V; the worker normalized limit includes 1e-12 floating-point tolerance. CON27/28 3-4 and high-impedance loading yield approximately unity analog gain; other wiring/loading and measured calibration may differ. Values are not measured connector voltages.
