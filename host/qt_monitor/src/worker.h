#pragma once
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QFile>
#include <QJsonObject>
#include <QHash>
#include <QQueue>
#include <QTcpSocket>
#include "protocol.h"

class Worker : public QObject {
    Q_OBJECT
public:
    explicit Worker(QObject *parent=nullptr);
public slots:
    void action(const QString &name, const QJsonObject &parameters=QJsonObject());
signals:
    void snapshotReady(const QJsonObject &snapshot);
    void stateReady(const QJsonObject &state);
    void logMessage(const QString &message);
    void disconnected();
private:
    struct Step {
        bool write=false; quint32 address=0; QVector<quint32> values; quint32 count=1;
        int delay=0; bool check=false; quint32 mask=0, expected=0;
        bool checkDliaProfile=false;
    };
    static Step read(quint32 a, quint32 count=1);
    static Step write(quint32 a, quint32 value);
    static Step check(quint32 a, quint32 mask, quint32 value);
    static Step checkDliaProfile(quint32 a);
    static Step delay(int ms);
    void setupTimers(); void consume(const QByteArray &bytes); void next();
    void execute(const QVector<Step>& steps, const QString &purpose);
    void finish(); void fail(const QString &reason); void publish();
    void refresh(); void disconnectDevice(); void closeBridge();
    QVector<Step> stopPlan() const; QVector<Step> readPlan() const;
    void startAcquisition(); void applyWms(const QJsonObject &p);
    void applyDlia(const QJsonObject &p);
    void startReplay(const QString &path);
    QProcess *process=nullptr;
    QTcpSocket *commandSocket=nullptr;
    QString ipcToken;
    QTimer *uiTimer=nullptr, *timeout=nullptr, *stepTimer=nullptr, *replayTimer=nullptr;
    QFile replay, recording;
    VlpParser parser; DataDecoder decoder;
    QHash<quint32,quint32> registers;
    QQueue<Step> queue; Step pending;
    QQueue<QPair<QString,QJsonObject>> deferredActions;
    QByteArray errorBuffer;
    quint32 sequence=100000, awaiting=0;
    QString purpose, message=QStringLiteral("未连接"), lastFailure;
    bool connected=false, ready=false, acquiring=false, busy=false, replaying=false;
    bool rawEnabled=true, adcTouched=false, closing=false, disconnectAfter=false, recovering=false;
    double gains[2]={0.5,0.5}; int refreshTicks=0;
};
