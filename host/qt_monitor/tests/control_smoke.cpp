// Explicitly invoked board test; normal GUI startup never runs this sequence.
#include <QCoreApplication>
#include <QTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QTextStream>
#include <functional>
#include "worker.h"

int main(int argc,char **argv){
    QCoreApplication app(argc,argv);
    if(app.arguments().size()!=2)return 2;
    Worker w;QJsonObject state,snapshot,baseline;QJsonArray logs,stages;
    QString expected;int stage=-1,exitCode=0;bool closing=false,advancing=false;
    double beforeCycle[2]={-1,-1};
    auto reg=[&](const QJsonObject &s,quint32 a){return quint32(s.value("registers").toObject().value(QString::number(a,16)).toDouble());};
    auto params=[&](int c){quint32 b=0x5000+0x100*c;quint32 mode=reg(baseline,b+0x20);
        return QJsonObject{{"channel",c},{"referenceMode",int(mode&1)},{"referenceHz",reg(baseline,b+0x10)/1000.0},
            {"phase1Deg",reg(baseline,b+0x14)*360.0/4294967296.0},{"phase2Deg",reg(baseline,b+0x18)*360.0/4294967296.0},
            {"outputHz",int(reg(baseline,b+0x1c))},{"lpfBypass",bool(mode&4)},{"fragmentPoints",int(reg(baseline,b+0x40))}};};
    auto save=[&]{QFile f(app.arguments()[1]);if(f.open(QIODevice::WriteOnly))f.write(QJsonDocument(QJsonObject{{"exitCode",exitCode},{"stage",stage},{"state",state},{"snapshot",snapshot},{"stages",stages},{"logs",logs}}).toJson());};
    auto fail=[&](QString reason){logs.append("FAIL "+reason);QTextStream(stderr)<<reason<<"\n";exitCode=1;closing=true;w.action("disconnect");};
    auto require=[&](bool value,QString reason){if(!value)fail(reason);return value;};
    std::function<void()> advance;
    auto run=[&](QString action,QJsonObject p,QString completion){
        const auto channels=snapshot.value("dlia").toArray();
        for(int i=0;i<2;i++)beforeCycle[i]=i<channels.size()?channels[i].toObject().value("cycle").toDouble():-1;
        expected=completion;advancing=false;w.action(action,p);
    };
    advance=[&]{
        if(closing)return;
        stages.append(QJsonObject{{"stage",stage},{"state",state},{"sensorCounts",snapshot.value("sensors")}});
        // Actual register readback checks, not button states.
        if(stage==0){baseline=state;if(!require(reg(state,0x2004)==1&&reg(state,0x2104)==1,"Both existing WMS must be running for this test"))return;}
        if(stage==2||stage==3||stage==4||stage==5||stage==6||stage==7||stage==8){
            if(!require(reg(state,0x4004)==1&&reg(state,0x4104)==1,"Independent action stopped ADC"))return;
        }
        if(stage==2&&!require(reg(state,0x5014)==0x10000000&&reg(state,0x504c)==5000&&reg(state,0x5114)==reg(baseline,0x5114)&&reg(state,0x511c)==reg(baseline,0x511c),"DLIA0 configuration/readback or channel isolation failed"))return;
        if(stage==3&&!require(reg(state,0x5104)==0&&reg(state,0x5004)==1,"DLIA1 independent stop failed"))return;
        if(stage==4&&!require(reg(state,0x5104)==1,"DLIA1 independent start failed"))return;
        if(stage==2||stage==4||stage==7||stage==8||stage==10){
            const int c=(stage==4||stage==8)?1:0;
            const auto data=snapshot.value("dlia").toArray()[c].toObject();
            if(!require(data.value("displayFullCycle").toBool()&&!data.value("stale").toBool()&&
                data.value("cycle").toDouble()!=beforeCycle[c]&&!(quint32(data.value("flags").toDouble())&0x38)&&reg(state,0x500c+c*0x100)==0,
                QString("DLIA%1 enabled but no NEW clean complete harmonic cycle").arg(c)))return;
            logs.append(QString("DATA_PASS DLIA%1 new_cycle=%2 age_ms=%3 count=%4").arg(c).arg(data.value("cycle").toDouble(),0,'f',0).arg(data.value("ageMs").toDouble()).arg(data.value("count").toDouble(),0,'f',0));
        }
        if(stage==10&&!require(reg(state,0x4004)==1&&reg(state,0x4104)==0&&reg(state,0x5104)==0,"Standalone DLIA0 start failed or started other lane"))return;
        if(stage==5&&!require(reg(state,0x2004)==0&&reg(state,0x2104)==1&&reg(state,0x3004)==1,"WMS0 independent stop or DAC hold failed"))return;
        if(stage==6&&!require(reg(state,0x2004)==1&&reg(state,0x2104)==1,"WMS0 restart failed"))return;
        if(stage==7){for(quint32 o:{0x10u,0x14u,0x18u,0x1cu,0x20u,0x40u})if(!require(reg(state,0x5000+o)==reg(baseline,0x5000+o),"DLIA0 restore failed"))return;}
        if(stage==9){
            for(quint32 a:{0x4004u,0x4104u,0x5004u,0x5104u})if(!require(reg(state,a)==0,"Stop acquisition readback failed"))return;
            for(quint32 a:{0x2004u,0x2104u,0x3004u,0x3104u})if(!require(reg(state,a)==1,"DAC/WMS not preserved"))return;
        }
        ++stage;
        switch(stage){
        case 0:run("connect",{},QStringLiteral("USB 已连接"));break;
        case 1:run("start",{},QStringLiteral("实时采集中"));break;
        case 2:{auto p=params(0);p["referenceMode"]=0;p["phase1Deg"]=22.5;p["outputHz"]=5000;run("dlia_apply",p,"DLIA0 参数应用");break;}
        case 3:run("dlia_stop",{{"channel",1}},"DLIA1 停止");break;
        case 4:run("dlia_start",{{"channel",1}},"DLIA1 启动");break;
        case 5:run("wms_stop",{{"channel",0}},"WMS0 停止");break;
        case 6:run("wms_start",{{"channel",0}},"WMS0 启动");break;
        case 7:run("dlia_apply",params(0),"DLIA0 参数应用");break;
        case 8:run("dlia_apply",params(1),"DLIA1 参数应用");break;
        case 9:run("stop",{},QStringLiteral("采集已停止"));break;
        case 10:run("dlia_start",{{"channel",0}},"DLIA0 启动");break;
        case 11:run("stop",{},QStringLiteral("采集已停止"));break;
        default:closing=true;w.action("disconnect");break;
        }
    };
    QObject::connect(&w,&Worker::stateReady,&app,[&](const QJsonObject&s){state=s;});
    QObject::connect(&w,&Worker::snapshotReady,&app,[&](const QJsonObject&s){snapshot=s;});
    QObject::connect(&w,&Worker::logMessage,&app,[&](QString msg){logs.append(msg);QTextStream(stdout)<<msg<<"\n";
        if(!advancing&&!closing&&!expected.isEmpty()&&msg.startsWith(expected)){
            advancing=true;expected.clear();QTimer::singleShot(stage==8?15000:500,&app,advance);
        }
    });
    QObject::connect(&w,&Worker::disconnected,&app,[&]{if(!closing){exitCode=1;logs.append("Unexpected disconnect");}save();app.exit(exitCode);});
    QTimer::singleShot(110000,&app,[&]{fail("Control smoke timeout");QTimer::singleShot(5000,&app,[&]{save();app.exit(1);});});
    QTimer::singleShot(0,&app,advance);return app.exec();
}
