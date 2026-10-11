#pragma once

#include <QMainWindow>
#include <QJsonObject>
#include <QVector>
#include <array>

class QLabel;
class QPushButton;
class QCheckBox;
class QComboBox;
class QDoubleSpinBox;
class QSpinBox;
class QPlainTextEdit;
class TracePlot;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);
signals:
    void requestAction(const QString &action, const QJsonObject &parameters);
public slots:
    void updateSnapshot(const QJsonObject &snapshot);
    void updateState(const QJsonObject &state);
    void appendLog(const QString &message);
private:
    struct SensorCard {
        QLabel *name = nullptr;
        QLabel *value = nullptr;
        QLabel *fields = nullptr;
        QLabel *quality = nullptr;
        TracePlot *plot = nullptr;
    };
    struct AdcCard {
        QLabel *summary = nullptr;
        QLabel *quality = nullptr;
        QComboBox *gain = nullptr;
        TracePlot *plot = nullptr;
    };
    struct HarmonicCard {
        QLabel *summary = nullptr;
        TracePlot *wave = nullptr;
        TracePlot *h2Wave = nullptr;
        TracePlot *peaks = nullptr;
    };
    struct WmsCard {
        QDoubleSpinBox *sawHz = nullptr;
        QDoubleSpinBox *sineHz = nullptr;
        QDoubleSpinBox *sawAmp = nullptr;
        QDoubleSpinBox *sineAmp = nullptr;
        QDoubleSpinBox *offset = nullptr;
        QDoubleSpinBox *phase = nullptr;
        QLabel *readback = nullptr;
        QPushButton *apply = nullptr;
        QPushButton *start = nullptr;
        QPushButton *stop = nullptr;
        QPushButton *load = nullptr;
        bool loaded = false;
    };
    struct DliaCard {
        QComboBox *referenceMode = nullptr;
        QDoubleSpinBox *referenceHz = nullptr;
        QDoubleSpinBox *phase1 = nullptr;
        QDoubleSpinBox *phase2 = nullptr;
        QSpinBox *outputHz = nullptr;
        QCheckBox *lpfBypass = nullptr;
        QSpinBox *fragmentPoints = nullptr;
        QLabel *readback = nullptr;
        QPushButton *apply = nullptr;
        QPushButton *start = nullptr;
        QPushButton *stop = nullptr;
        QPushButton *load = nullptr;
        bool loaded = false;
    };
    bool loadWmsParameters(int channel);
    bool loadDliaParameters(int channel);
    std::array<SensorCard, 6> m_sensors;
    std::array<AdcCard, 2> m_adc;
    std::array<HarmonicCard, 2> m_harmonics;
    std::array<WmsCard, 2> m_wms;
    std::array<DliaCard, 2> m_dlia;
    QLabel *m_connection = nullptr;
    QLabel *m_acquisition = nullptr;
    QLabel *m_message = nullptr;
    QLabel *m_statistics = nullptr;
    QPushButton *m_connect = nullptr;
    QPushButton *m_disconnect = nullptr;
    QPushButton *m_start = nullptr;
    QPushButton *m_stop = nullptr;
    QPushButton *m_refresh = nullptr;
    QPushButton *m_replay = nullptr;
    QPushButton *m_record = nullptr;
    QCheckBox *m_raw = nullptr;
    QPlainTextEdit *m_log = nullptr;
    QJsonObject m_state;
    bool m_recording = false;
};
