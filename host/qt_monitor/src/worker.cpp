#include "worker.h"
#include "dlia_profile.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QDateTime>
#include <QUuid>
#include <QPointer>
#include <QtEndian>
#include <cmath>

static quint32 u32(const QByteArray &b,int o){return qFromLittleEndian<quint32>(reinterpret_cast<const uchar*>(b.constData()+o));}
Worker::Worker(QObject *p):QObject(p){}
Worker::Step Worker::read(quint32 a,quint32 n){Step s;s.address=a;s.count=n;return s;}
Worker::Step Worker::write(quint32 a,quint32 v){Step s;s.write=true;s.address=a;s.values={v};return s;}
Worker::Step Worker::check(quint32 a,quint32 m,quint32 v){Step s=read(a);s.check=true;s.mask=m;s.expected=v;return s;}
Worker::Step Worker::checkDliaProfile(quint32 a){Step s=read(a);s.checkDliaProfile=true;return s;}
Worker::Step Worker::delay(int ms){Step s;s.delay=ms;return s;}
void Worker::setupTimers(){
    if(uiTimer)return;
    uiTimer=new QTimer(this);timeout=new QTimer(this);stepTimer=new QTimer(this);replayTimer=new QTimer(this);
    timeout->setSingleShot(true);stepTimer->setSingleShot(true);
    connect(timeout,&QTimer::timeout,this,[this]{fail(QStringLiteral("命令超时，未自动重发"));});
    connect(stepTimer,&QTimer::timeout,this,&Worker::next);
    connect(uiTimer,&QTimer::timeout,this,[this]{publish();if(++refreshTicks>=15){refreshTicks=0;if(ready&&!busy&&!replaying)refresh();}});
    connect(replayTimer,&QTimer::timeout,this,[this]{
        QByteArray b=replay.read(131072);
        if(b.isEmpty()){
            replayTimer->stop();replay.close();replaying=false;message=QStringLiteral("回放完成（历史记录，非实时）");
            emit logMessage(message);publish();
        } else consume(b);
    });
    uiTimer->start(200);
}
void Worker::publish(){
    QJsonObject s=decoder.snapshot();s["stats"]=parser.statistics();emit snapshotReady(s);
    QJsonObject r;for(auto i=registers.cbegin();i!=registers.cend();++i)r[QString::number(i.key(),16)]=double(i.value());
    QJsonObject st{{"connected",connected},{"ready",ready},{"acquiring",acquiring},{"busy",busy&&purpose!="refresh"},
        {"replaying",replaying},{"raw",rawEnabled},{"message",message},{"registers",r},
        {"recording",recording.isOpen()},{"stats",parser.statistics()},
        {"dliaData",s.value("dlia")},
        {"wmsRunning",QJsonArray{bool(registers.value(0x2004)&1),bool(registers.value(0x2104)&1)}}};
    emit stateReady(st);
}
void Worker::consume(const QByteArray &bytes){
    if(recording.isOpen()&&recording.write(bytes)!=bytes.size()){
        emit logMessage(QStringLiteral("记录失败：%1").arg(recording.errorString()));recording.close();
    }
    for(const auto &f:parser.feed(bytes)){
        if(qEnvironmentVariableIsSet("VAPOR_TRACE_COMMANDS")&&(f.kind==2||f.kind==0x7f))
            emit logMessage(QStringLiteral("RX seq=%1 src=%2 msg=%3 bytes=%4 awaiting=%5 busy=%6").arg(f.sequence).arg(f.source).arg(f.message).arg(f.payload.size()).arg(awaiting).arg(busy));
        if(awaiting&&f.sequence==awaiting&&f.source==1&&(f.kind==2||f.kind==0x7f)){
            if(f.message!=(pending.write?3:2)||f.kind!=2||f.payload.size()<4||u32(f.payload,0)!=0){
                fail(QStringLiteral("命令被拒绝或应答格式不符：0x%1").arg(pending.address,0,16));continue;
            }
            if(!pending.write){
                if(f.payload.size()!=int(12+4*pending.count)||u32(f.payload,4)!=pending.address||u32(f.payload,8)!=pending.count){
                    fail(QStringLiteral("寄存器回包范围不符"));continue;
                }
                for(quint32 i=0;i<pending.count;i++)registers[pending.address+4*i]=u32(f.payload,12+4*i);
                for(int c=0;c<2;c++){
                    const quint32 a=0x2010+0x100*c;
                    if(a>=pending.address&&a<pending.address+4*pending.count&&registers.value(a)>0)
                        decoder.setScanHz(c,registers.value(a)/1000.0);
                }
                if(pending.check&&(registers.value(pending.address)&pending.mask)!=pending.expected){
                    fail(QStringLiteral("回读校验失败 0x%1：0x%2").arg(pending.address,0,16).arg(registers.value(pending.address),0,16));continue;
                }
                if(pending.checkDliaProfile&&!supportedDliaProfile(registers.value(pending.address))){
                    fail(QStringLiteral("不支持的 DLIA 滤波配置 0x%1：0x%2").arg(pending.address,0,16).arg(registers.value(pending.address),0,16));continue;
                }
            }
            timeout->stop();awaiting=0;
            if(qEnvironmentVariableIsSet("VAPOR_TRACE_COMMANDS"))emit logMessage(QStringLiteral("ACK accepted; queue=%1").arg(queue.size()));
            // Queue on the event loop, avoiding reentrant handling of the same batch.
            stepTimer->start(0);
        }
        decoder.accept(f);
    }
}
void Worker::execute(const QVector<Step>& steps,const QString &why){
    if(busy){emit logMessage(QStringLiteral("正在执行操作，请稍候"));return;}
    purpose=why;busy=true;for(const auto&s:steps)queue.enqueue(s);next();publish();
}
void Worker::next(){
    if(qEnvironmentVariableIsSet("VAPOR_TRACE_COMMANDS"))emit logMessage(QStringLiteral("NEXT busy=%1 awaiting=%2 queued=%3").arg(busy).arg(awaiting).arg(queue.size()));
    if(awaiting||!busy)return;
    if(queue.isEmpty()){finish();return;}
    pending=queue.dequeue();
    if(qEnvironmentVariableIsSet("VAPOR_TRACE_COMMANDS"))emit logMessage(QStringLiteral("STEP address=%1 delay=%2 count=%3").arg(pending.address,0,16).arg(pending.delay).arg(pending.count));
    if(pending.delay){stepTimer->start(pending.delay);return;}
    if(!process||process->state()!=QProcess::Running){fail(QStringLiteral("USB 进程已退出"));return;}
    awaiting=++sequence;
    QByteArray frame=VlpParser::command(awaiting,pending.write,pending.address,pending.values,pending.count);
    QByteArray packet=frame.toBase64()+'\n';
    if(qEnvironmentVariableIsSet("VAPOR_TRACE_COMMANDS"))emit logMessage(QStringLiteral("SEND seq=%1 bytes=%2").arg(awaiting).arg(packet.size()));
    if(pending.write&&(pending.address==0x4004||pending.address==0x4104||pending.address==0x5004||pending.address==0x5104||pending.address==0x6004||pending.address==0x6204||pending.address==0x6304||pending.address==0x6404||pending.address==0x6504||pending.address==0x6604))adcTouched=true;
    timeout->start(6000);
    if(!commandSocket||commandSocket->state()!=QAbstractSocket::ConnectedState||commandSocket->write(packet)!=packet.size()){
        fail(QStringLiteral("USB 命令发送失败"));return;
    }
    commandSocket->flush();
}
QVector<Worker::Step> Worker::readPlan() const{
    return {read(0,2),read(0x2000,19),read(0x2100,19),read(0x3000,18),read(0x3100,18),
        read(0x4000,16),read(0x4100,16),read(0x5000,22),read(0x5100,22),read(0x6000,15),read(0x6600,26),read(0x7000,18),read(0x8000,16)};
}
QVector<Worker::Step> Worker::stopPlan() const{
    QVector<Step> p={write(0x4004,0),write(0x4104,0),delay(150),write(0x5004,0),write(0x5104,0),
        write(0x403c,0),write(0x413c,0),write(0x0050,0)};
    for(quint32 a:{0x6504u,0x6204u,0x6004u,0x6604u,0x6304u,0x6404u})p.append(write(a,0));
    for(quint32 a:{0x4004u,0x4104u,0x5004u,0x5104u,0x403cu,0x413cu})p.append(check(a,1,0));
    p+=readPlan();return p;
}
void Worker::finish(){
    busy=false;awaiting=0;
    if(purpose=="connect")ready=true;
    acquiring=bool((registers.value(0x4004)|registers.value(0x4104))&1);
    if(purpose=="start"){acquiring=true;message=QStringLiteral("实时采集中");}
    else if(purpose=="stop"||purpose=="recovery"){
        acquiring=false;adcTouched=false;message=recovering?QStringLiteral("操作失败，采集已停止；WMS/DAC 保持"):QStringLiteral("采集已停止；WMS/DAC 保持");recovering=false;
    }else if(purpose!="refresh")message=QStringLiteral("%1：回读验证完成").arg(purpose=="connect"?QStringLiteral("USB 已连接"):purpose);
    if(purpose!="refresh")emit logMessage(message);
    if(disconnectAfter){
        if(acquiring||adcTouched){execute(stopPlan(),"stop");return;}
        disconnectAfter=false;closeBridge();
    }
    publish();
    if(!busy&&!deferredActions.isEmpty()){
        const auto task=deferredActions.dequeue();
        QTimer::singleShot(0,this,[this,task]{action(task.first,task.second);});
    }
}
void Worker::fail(const QString &reason){
    if(timeout)timeout->stop();
    if(stepTimer)stepTimer->stop();
    awaiting=0;queue.clear();deferredActions.clear();busy=false;
    message=reason;lastFailure=reason;emit logMessage(reason);
    if(adcTouched&&connected&&!recovering&&process&&process->state()==QProcess::Running){
        recovering=true;execute(stopPlan(),"recovery");
    }else{
        if(recovering)emit logMessage(QStringLiteral("未能确认板卡已停止采集，请检查连接；没有关闭 DAC"));
        ready=false;closeBridge();
    }
    publish();
}
void Worker::refresh(){if(ready&&!busy)execute(readPlan(),"refresh");}
void Worker::closeBridge(){
    ready=false;connected=false;busy=false;acquiring=false;awaiting=0;queue.clear();deferredActions.clear();
    timeout->stop();stepTimer->stop();recording.close();
    if(commandSocket){commandSocket->disconnectFromHost();commandSocket->deleteLater();commandSocket=nullptr;}
    if(process){
        closing=true;process->closeWriteChannel();
        const QPointer<QProcess> closingProcess=process;
        QTimer::singleShot(1500,this,[closingProcess]{
            if(closingProcess&&closingProcess->state()!=QProcess::NotRunning)closingProcess->kill();
        });
        publish(); // finished() reports disconnection once the USB helper releases the device.
    }else{publish();emit disconnected();}
}
void Worker::disconnectDevice(){
    if(replaying){replayTimer->stop();replay.close();replaying=false;message=QStringLiteral("回放已停止");publish();emit disconnected();return;}
    if(!connected){closeBridge();return;}
    if(busy){disconnectAfter=true;message=QStringLiteral("当前操作完成后断开，保留 WMS/DAC");return;}
    if(acquiring||adcTouched){disconnectAfter=true;execute(stopPlan(),"stop");}
    else{message=QStringLiteral("已断开；WMS/DAC 保持原状态");closeBridge();}
}
void Worker::startAcquisition(){
    if(!ready||busy||acquiring)return;
    if(!(registers.value(0x2004)&1)||!(registers.value(0x2104)&1))
        emit logMessage(QStringLiteral("WMS 有通道未运行：传感器可采集，该路 ADC/谐波完整扫描需等待 WMS 扫描边界"));
    QVector<Step> p={check(0x4000,0xffffffff,0x00200101),check(0x4100,0xffffffff,0x00210101),
        check(0x4018,0xffffffff,0x00011800),check(0x4118,0xffffffff,0x00011800),
        write(0x6004,0),write(0x6204,0),write(0x6304,0),write(0x6404,0),write(0x6504,0),write(0x6604,0),delay(100),
        write(0x6310,0x77),write(0x4004,2),delay(250),write(0x4104,2),write(0x5004,2),write(0x5104,2),
        write(0x4010,1000000),write(0x401c,0),write(0x4004,4),delay(250),
        check(0x4008,0x96,0x12),check(0x4108,0x96,0x12)};
    for(int c=0;c<2;c++){
        quint32 b=0x5000+0x100*c;
        // Commit existing user settings; acquisition must not overwrite DLIA parameters.
        p+=QVector<Step>{write(b+4,4),delay(100),check(b+8,4,0)};
    }
    p.append(write(4,1));
    for(quint32 a:{0x6404u,0x6304u,0x6004u,0x6604u,0x6204u,0x6504u})p.append(write(a,1));
    p+=QVector<Step>{write(0x0050,rawEnabled?3:0),write(0x403c,rawEnabled?1:0),write(0x413c,rawEnabled?1:0),
        write(0x5004,1),write(0x5104,1),write(0x4004,1),write(0x4104,1),delay(100),check(0x4004,1,1),check(0x4104,1,1)};
    p+=readPlan();execute(p,"start");
}
void Worker::applyWms(const QJsonObject &p){
    if(!ready||busy)return;
    int c=p.value("channel").toInt(-1);double saw=p.value("sawHz").toDouble(-1),sine=p.value("sineHz").toDouble(-1);
    double a=p.value("sawAmplitude").toDouble(-1),b=p.value("sineAmplitude").toDouble(-1),offset=p.value("offset").toDouble(2),phase=p.value("phaseDeg").toDouble(0);
    if(c<0||c>1||!std::isfinite(saw)||!std::isfinite(sine)||!std::isfinite(a)||!std::isfinite(b)||!std::isfinite(offset)||!std::isfinite(phase)||saw<100||saw>1000||sine<1000||sine>100000||a<0||b<0||std::abs(offset)+a+b>(.95+1e-12)||phase<0||phase>=360){emit logMessage(QStringLiteral("WMS 参数超出范围：扫描100～1000Hz，正弦1～100kHz，幅度和偏置总量≤0.95"));return;}
    quint32 w=0x2000+0x100*c,d=0x3000+0x100*c;
    auto q31=[](double x){return quint32(qint32(std::llround(x*2147483648.0)));};
    QVector<Step> plan={write(w+4,0),delay(20),write(d+4,0),delay(20),
        write(d+0x10,0x312),write(d+0x14,0x80000),write(d+0x18,0),write(d+0x1c,0xfffff),
        write(d+0x24,20000000),write(d+0x34,0x40000000),write(d+0x38,0),write(d+4,4),delay(100),check(d+8,0x9e,0x12),
        write(w+0x10,quint32(std::llround(saw*1000))),write(w+0x14,q31(a)),write(w+0x18,q31(offset)),
        write(w+0x1c,quint32(std::llround(sine*1000))),write(w+0x20,q31(b)),write(w+0x24,quint32(std::llround(phase/360*4294967296.0))),
        write(w+0x28,500000),write(w+0x40,2),write(w+4,4),delay(100),check(w+8,0x84,0),check(w+0x2c,0xffffffff,500000),
        write(d+4,1),write(4,1),write(w+4,1),delay(50),check(w+4,1,1),check(d+4,1,1),check(w+0xc,0xffffffff,0),check(d+0xc,0xffffffff,0)};
    plan+=readPlan();execute(plan,QStringLiteral("WMS%1 启动").arg(c));
}
void Worker::applyDlia(const QJsonObject &p){
    const int c=p.value("channel").toInt(-1),ref=p.value("referenceMode").toInt(-1);
    const double hz=p.value("referenceHz").toDouble(-1),p1=p.value("phase1Deg").toDouble(-1),p2=p.value("phase2Deg").toDouble(-1);
    const double rate=p.value("outputHz").toDouble(-1),frag=p.value("fragmentPoints").toDouble(-1);
    if(c<0||c>1||ref<0||ref>1||!std::isfinite(hz)||!std::isfinite(p1)||!std::isfinite(p2)||!std::isfinite(rate)||!std::isfinite(frag)||hz<.001||hz>1000000||p1<0||p1>=360||p2<0||p2>=360||rate<1||rate>125000||rate!=std::floor(rate)||frag<1||frag>256||frag!=std::floor(frag)){
        emit logMessage(QStringLiteral("DLIA 参数超出范围，未写入设备"));return;
    }
    quint32 b=0x5000+0x100*c,a=0x4000+0x100*c,restore=registers.value(b+4)&1;
    const quint32 restoreAdc=registers.value(a+4)&1;
    quint32 mode=2u|quint32(ref)|(p.value("lpfBypass").toBool()?4u:0u);
    auto phase=[](double x){return quint32(std::llround(x/360.0*4294967296.0));};
    // The fanout always feeds DLIA. Pause this capture lane before disabling the
    // consumer, otherwise the 256-sample FIFO overflows during USB/config delays.
    // Do NOT soft-reset ADC0: that would reset the shared two-channel ADC PHY.
    QVector<Step> plan={write(a+4,0),delay(10),write(b+4,0),write(a+4,8),write(b+4,2),write(b+0x10,quint32(std::llround(hz*1000))),
        write(b+0x14,phase(p1)),write(b+0x18,phase(p2)),write(b+0x1c,quint32(rate)),write(b+0x20,mode),write(b+0x40,quint32(frag)),
        write(b+4,4),delay(100),check(b+8,4,0),check(b+0x10,0xffffffff,quint32(std::llround(hz*1000))),
        check(b+0x14,0xffffffff,phase(p1)),check(b+0x18,0xffffffff,phase(p2)),check(b+0x1c,0xffffffff,quint32(rate)),
        check(b+0x20,0xffffffff,mode),check(b+0x40,0xffffffff,quint32(frag)),write(b+4,restore),write(a+4,restoreAdc),check(b+4,1,restore),check(a+4,1,restoreAdc)};
    plan+=readPlan();execute(plan,QStringLiteral("DLIA%1 参数应用").arg(c));
}
void Worker::startReplay(const QString &path){
    if(connected||process){emit logMessage(QStringLiteral("请先断开 USB，再回放历史记录"));return;}
    replayTimer->stop();replay.close();replay.setFileName(path);
    if(!replay.open(QIODevice::ReadOnly)){emit logMessage(replay.errorString());return;}
    parser.reset();decoder.reset();for(int i=0;i<2;i++)decoder.setAdcGain(i,gains[i]);
    replaying=true;ready=false;message=QStringLiteral("历史文件回放（非实时）：%1").arg(QFileInfo(path).fileName());
    replayTimer->start(20);publish();
}
void Worker::action(const QString &name,const QJsonObject &p){
    setupTimers();
    if(busy&&purpose=="refresh"&&name!="refresh"&&name!="disconnect"&&name!="gain"){
        if(deferredActions.size()<16)deferredActions.enqueue(qMakePair(name,p));
        else emit logMessage(QStringLiteral("待执行操作过多，请稍候"));
        return;
    }
    if(name=="gain"){
        int c=p.value("channel").toInt(-1);double g=p.value("gain").toDouble();
        if(c>=0&&c<2&&(g==.5||g==1)){gains[c]=g;decoder.setAdcGain(c,g);emit logMessage(QStringLiteral("ADC%1 电压换算增益设为 %2（须与 S3 一致）").arg(c).arg(g));publish();}return;
    }
    if(name=="disconnect"){disconnectDevice();return;}
    if(name=="replay"){startReplay(p.value("path").toString());return;}
    if(name=="record"){
        recording.close();QString path=p.value("path").toString();
        if(!path.isEmpty()){
            if(!ready||replaying){emit logMessage(QStringLiteral("仅可记录已连接的实时 USB 数据"));return;}
            recording.setFileName(path);
            if(!recording.open(QIODevice::WriteOnly|QIODevice::NewOnly)){emit logMessage(QStringLiteral("不能创建记录文件：%1").arg(recording.errorString()));return;}
        }
        emit logMessage(recording.isOpen()?QStringLiteral("原始数据记录已开始"):QStringLiteral("记录已停止"));publish();return;
    }
    if(name=="connect"){
        if(process||replaying)return;
        parser.reset();decoder.reset();for(int i=0;i<2;i++)decoder.setAdcGain(i,gains[i]);
        registers.clear();errorBuffer.clear();lastFailure.clear();closing=false;recovering=false;adcTouched=false;
        process=new QProcess(this);process->setProcessChannelMode(QProcess::SeparateChannels);
        connect(process,&QProcess::readyReadStandardOutput,this,[this]{consume(process->readAllStandardOutput());});
        connect(process,&QProcess::readyReadStandardError,this,[this]{
            errorBuffer+=process->readAllStandardError();int n;
            while((n=errorBuffer.indexOf('\n'))>=0){QString line=QString::fromUtf8(errorBuffer.left(n)).trimmed();errorBuffer.remove(0,n+1);
                emit logMessage(line);
                if(line.startsWith("READY")&&!connected){
                    const auto portText=line.section("PORT=",1);bool ok=false;int port=portText.toInt(&ok);
                    if(!ok||port<1||port>65535){fail(QStringLiteral("USB 组件未提供有效本机通道"));continue;}
                    commandSocket=new QTcpSocket(this);commandSocket->connectToHost(QHostAddress::LocalHost,quint16(port));
                    if(!commandSocket->waitForConnected(1500)){fail(QStringLiteral("USB 本机通道连接失败"));continue;}
                    commandSocket->write(ipcToken.toLatin1()+'\n');commandSocket->flush();
                    connected=true;QVector<Step> p={check(0x4000,0xffffffff,0x00200101),check(0x4100,0xffffffff,0x00210101),check(0x4018,0xffffffff,0x00011800),check(0x4118,0xffffffff,0x00011800),checkDliaProfile(0x5024),checkDliaProfile(0x5124)};
                    p+=readPlan();execute(p,"connect");
                }else if(line.startsWith("ERROR"))fail(line);
            }
        });
        connect(process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus){
            Q_UNUSED(code);consume(process->readAllStandardOutput());process->deleteLater();process=nullptr;
            timeout->stop();stepTimer->stop();queue.clear();awaiting=0;busy=false;connected=false;ready=false;acquiring=false;recording.close();
            if(commandSocket){commandSocket->abort();commandSocket->deleteLater();commandSocket=nullptr;}
            if(!closing)message=QStringLiteral("USB 已断开；硬件采集状态未确认，WMS/DAC 未主动关闭");
            publish();emit disconnected();
        });
        connect(process,&QProcess::errorOccurred,this,[this](QProcess::ProcessError e){if(e==QProcess::FailedToStart){message=QStringLiteral("无法启动 USB 组件：%1").arg(process->errorString());emit logMessage(message);process->deleteLater();process=nullptr;connected=false;ready=false;busy=false;publish();emit disconnected();}});
        message=QStringLiteral("正在连接 USB…");publish();
        ipcToken=QUuid::createUuid().toString(QUuid::WithoutBraces);
        process->start(QCoreApplication::applicationDirPath()+"/VaporUsbBridge.exe",{"--socket",ipcToken});return;
    }
    if(name=="raw"){
        if(busy){emit logMessage(QStringLiteral("操作进行中，未更改 RAW 设置"));return;}
        rawEnabled=p.value("enabled").toBool();
        if(ready&&acquiring)execute({write(0x0050,rawEnabled?3:0),write(0x403c,rawEnabled?1:0),write(0x413c,rawEnabled?1:0),check(0x403c,1,rawEnabled?1:0),check(0x413c,1,rawEnabled?1:0)},QStringLiteral("RAW 设置"));
        publish();return;
    }
    if(!ready){emit logMessage(QStringLiteral("请先连接并验证 USB"));return;}
    if(busy){emit logMessage(QStringLiteral("操作进行中，请稍候"));return;}
    if(name=="refresh")refresh();
    else if(name=="start")startAcquisition();
    else if(name=="stop")execute(stopPlan(),"stop");
    else if(name=="wms_apply")applyWms(p);
    else if(name=="dlia_apply")applyDlia(p);
    else if(name=="dlia_start"||name=="dlia_stop"){
        int c=p.value("channel").toInt(-1);
        if(c>=0&&c<2){quint32 b=0x5000+c*0x100,a=0x4000+c*0x100;quint32 enable=name=="dlia_start"?1:0;
            QVector<Step> plan;
            if(enable){
                if(!(registers.value(0x2004+c*0x100)&1)){
                    message=QStringLiteral("DLIA%1 未启动：请先启动对应 WMS 扫描，当前 FPGA 需要扫描边界输出完整谐波帧").arg(c+1);
                    emit logMessage(message);publish();return;
                }
                plan={check(a+8,0x12,0x12),write(a+4,0),delay(10),write(b+4,0),write(a+4,8),write(b+4,2),
                    write(b+4,4),delay(100),check(b+8,4,0),write(4,1),write(b+4,1),write(a+4,1),
                    check(a+4,1,1),check(b+4,1,1),check(b+0xc,0xffffffff,0)};
            }else plan={write(b+4,0),check(b+4,1,0)};
            plan+=readPlan();
            execute(plan,QStringLiteral("DLIA%1 %2").arg(c).arg(enable?QStringLiteral("启动"):QStringLiteral("停止")));
        }
    }
    else if(name=="wms_start"){
        int c=p.value("channel").toInt(-1);
        if(c>=0&&c<2){quint32 b=0x2000+c*0x100,d=0x3000+c*0x100;
            QVector<Step> plan={check(d+8,0x12,0x12),write(d+4,1),write(4,1),write(b+4,1),check(b+4,1,1)};
            plan+=readPlan();execute(plan,QStringLiteral("WMS%1 启动").arg(c));}
    }
    else if(name=="wms_stop"){
        int c=p.value("channel").toInt(-1);
        if(c>=0&&c<2){quint32 b=0x2000+c*0x100;QVector<Step> plan={write(b+4,0),check(b+4,1,0)};
            plan+=readPlan();execute(plan,QStringLiteral("WMS%1 停止更新，DAC 保持末值").arg(c));}
    }
}
