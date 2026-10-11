#include <QApplication>
#include <QThread>
#include <QTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QTabWidget>
#include <QFileInfo>
#include <QFontDatabase>
#include <QDateTime>
#include <QDir>
#include <QEvent>
#include <QCommandLineParser>
#include <functional>
#include "mainwindow.h"
#include "worker.h"

class CloseGuard : public QObject {
public:
    std::function<void()> closeAction; bool allow=false;
    bool eventFilter(QObject *obj,QEvent *e) override {
        Q_UNUSED(obj);
        if(e->type()==QEvent::Close&&!allow){if(closeAction)closeAction();return true;}
        return false;
    }
};
int main(int argc,char **argv){
    QApplication app(argc,argv);
    if(QGuiApplication::platformName()=="offscreen"){
        QFontDatabase::addApplicationFont("C:/Windows/Fonts/msyh.ttc");
        QFontDatabase::addApplicationFont("C:/Windows/Fonts/msyhbd.ttc");
        QFontDatabase::addApplicationFont("C:/Windows/Fonts/segoeui.ttf");
    }
    app.setApplicationName("VaporMonitor");app.setOrganizationName("VaporLab");
    QCommandLineParser cli;cli.setApplicationDescription(QStringLiteral("Vapor Qt 实时监控"));cli.addHelpOption();
    cli.addOptions({QCommandLineOption("replay","Replay a captured bulk_in.bin", "path"),
        QCommandLineOption("smoke-live","Verify connect/start/stop on board; preserve DAC", "seconds"),
        QCommandLineOption("smoke-wms","In live test reapply existing validated 100Hz/20kHz WMS settings"),
        QCommandLineOption("quit-after","Close after N seconds", "seconds"),
        QCommandLineOption("screenshot","Save widget screenshot before close", "path"),
        QCommandLineOption("summary","Save JSON snapshot/state and command logs", "path")});
    cli.addOption(QCommandLineOption("record", "Record live USB bytes to a new file", "path"));
    cli.process(app);
    if(cli.isSet("replay")&&cli.isSet("smoke-live"))return 2;
    MainWindow window;window.resize(1400,920);window.show();
    QThread thread;Worker *worker=new Worker;worker->moveToThread(&thread);
    QObject::connect(&thread,&QThread::finished,worker,&QObject::deleteLater);
    QObject::connect(&window,&MainWindow::requestAction,worker,&Worker::action);
    QObject::connect(worker,&Worker::snapshotReady,&window,&MainWindow::updateSnapshot);
    QObject::connect(worker,&Worker::stateReady,&window,&MainWindow::updateState);
    QObject::connect(worker,&Worker::logMessage,&window,&MainWindow::appendLog);
    QJsonObject lastState,lastSnapshot;QStringList logs;
    auto send=[worker](QString a,QJsonObject p=QJsonObject()){QMetaObject::invokeMethod(worker,[worker,a,p]{worker->action(a,p);},Qt::QueuedConnection);};
    CloseGuard guard;window.installEventFilter(&guard);bool quitting=false;
    bool screenshotSaved=false;
    auto save=[&]{
        if(cli.isSet("screenshot")&&!screenshotSaved){
            const QString path=cli.value("screenshot");
            window.grab().save(path);
            if(auto *tabs=window.findChild<QTabWidget*>()){
                int old=tabs->currentIndex();QFileInfo fi(path);
                for(int i=0;i<tabs->count();i++){
                    tabs->setCurrentIndex(i);window.grab().save(fi.path()+"/"+fi.completeBaseName()+QString("_tab%1.png").arg(i));
                }
                tabs->setCurrentIndex(old);
            }
            screenshotSaved=true;
        }
        if(cli.isSet("summary")){
            QFile f(cli.value("summary"));if(f.open(QIODevice::WriteOnly)){
                QJsonArray logArray;for(const auto&l:logs)logArray.append(l);
                f.write(QJsonDocument(QJsonObject{{"state",lastState},{"snapshot",lastSnapshot},{"logs",logArray},
                    {"savedAt",QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}}).toJson());
            }
        }
    };
    guard.closeAction=[&]{if(quitting)return;quitting=true;save();send("disconnect");QTimer::singleShot(15000,&app,[&]{guard.allow=true;window.close();app.quit();});};
    QObject::connect(worker,&Worker::disconnected,&window,[&]{if(quitting){save();guard.allow=true;window.close();app.quit();}});
    QObject::connect(worker,&Worker::snapshotReady,&window,[&](const QJsonObject&s){lastSnapshot=s;});
    QObject::connect(worker,&Worker::logMessage,&window,[&](const QString&s){logs.append(QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)+" "+s);if(logs.size()>2000)logs.removeFirst();});
    int liveStage=0;
    QObject::connect(worker,&Worker::stateReady,&window,[&](const QJsonObject&s){
        lastState=s;
        if(!cli.isSet("smoke-live")||quitting||!s.value("ready").toBool()||s.value("busy").toBool())return;
        if(liveStage==0){
            if(cli.isSet("smoke-wms")){
                const auto regs=s.value("registers").toObject();
                // Do not use automation to introduce an unknown output setting.
                for(int c=0;c<2;c++){
                    quint32 b=0x2000+c*0x100;
                    auto reg=[&](quint32 a){return quint32(regs.value(QString::number(a,16)).toDouble());};
                    if(reg(b+0x10)!=100000||reg(b+0x1c)!=20000000||reg(b+0x14)!=0x06666666||reg(b+0x20)!=0x0147ae14||reg(b+0x18)!=0||reg(b+0x24)!=(c?0x40000000:0)||!(reg(b+4)&1)){
                        logs.append("Live WMS smoke refused: existing parameters differ from validated preset");liveStage=99;return;
                    }
                }
                liveStage=1;send("wms_apply",{{"channel",0},{"sawHz",100},{"sineHz",20000},{"sawAmplitude",.05},{"sineAmplitude",.01},{"offset",0},{"phaseDeg",0}});return;
            }else liveStage=2;
        }
        if(liveStage==1&&s.value("message").toString().startsWith("WMS0")){liveStage=2;send("wms_apply",{{"channel",1},{"sawHz",100},{"sineHz",20000},{"sawAmplitude",.05},{"sineAmplitude",.01},{"offset",0},{"phaseDeg",90}});return;}
        if(liveStage==2&&(!cli.isSet("smoke-wms")||s.value("message").toString().startsWith("WMS1"))){
            liveStage=3;if(cli.isSet("record"))send("record",{{"path",cli.value("record")}});send("start");return;
        }
        if(liveStage==3&&s.value("acquiring").toBool()){
            liveStage=4;int ms=qBound(3000,cli.value("smoke-live").toInt()*1000,120000);
            QTimer::singleShot(ms,&window,[&]{save();send("stop");liveStage=5;});
        }else if(liveStage==5&&!s.value("acquiring").toBool()){liveStage=6;QTimer::singleShot(400,&window,[&]{guard.closeAction();});}
    });
    thread.start();
    if(cli.isSet("replay"))QTimer::singleShot(50,&window,[&]{send("replay",{{"path",cli.value("replay")}});});
    if(cli.isSet("smoke-live"))QTimer::singleShot(50,&window,[&]{send("connect");});
    if(cli.isSet("quit-after"))QTimer::singleShot(qMax(1000,cli.value("quit-after").toInt()*1000),&window,[&]{guard.closeAction();});
    int rc=app.exec();
    QMetaObject::invokeMethod(worker,[worker]{worker->action("disconnect");},Qt::BlockingQueuedConnection);
    thread.quit();thread.wait();
    if(cli.isSet("smoke-live")&&liveStage!=6)return 3;
    return rc;
}
