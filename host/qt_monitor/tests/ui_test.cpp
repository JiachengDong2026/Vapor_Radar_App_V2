#include <QApplication>
#include <QPushButton>
#include <QDoubleSpinBox>
#include <QSpinBox>
#include <QLabel>
#include <QTimer>
#include <QMessageBox>
#include <cmath>
#include <QJsonObject>
#include <QTextStream>
#include <stdexcept>
#include "mainwindow.h"
#include "dlia_profile.h"

static_assert(supportedDliaProfile(0x00020101u), "Original AD4630 profile must connect");
static_assert(supportedDliaProfile(0x00040101u), "Fourth-order AD4630 profile must connect");
static_assert(!supportedDliaProfile(0x00040102u), "Legacy 12.5 MS/s profile must be rejected");
static_assert(!supportedDliaProfile(0u), "Uninitialized profile must be rejected");
static_assert(!supportedDliaProfile(0x00050101u), "Unknown profile must be rejected");

int main(int argc,char **argv){
    QApplication app(argc,argv);MainWindow w;int checks=0;
    auto check=[&](bool ok,const char *why){++checks;if(!ok)throw std::runtime_error(why);};
    auto button=[&](const char*n){auto*p=w.findChild<QPushButton*>(n);if(!p)throw std::runtime_error(n);return p;};
    QJsonObject regs;
    for(int ch=0;ch<2;ch++){
        quint32 b=0x2000+ch*0x100;
        for(quint32 o:{4u,0x10u,0x14u,0x18u,0x1cu,0x20u,0x24u})regs[QString::number(b+o,16)]=0;
        regs[QString::number(b+0x10,16)]=100000;regs[QString::number(b+0x1c,16)]=20000000;
        b=0x5000+ch*0x100;
        for(quint32 o:{4u,0x10u,0x14u,0x18u,0x1cu,0x20u,0x24u,0x40u,0x4cu,0x50u})regs[QString::number(b+o,16)]=0;
        regs[QString::number(b+0x10,16)]=20000000;regs[QString::number(b+0x1c,16)]=10000;
        regs[QString::number(b+0x20,16)]=2;regs[QString::number(b+0x40,16)]=256;
    }
    QJsonObject state{{"connected",true},{"ready",true},{"acquiring",false},{"busy",false},{"registers",regs}};
    try{
        w.updateState(state);
        regs["5024"]=0x00040101;
        regs["5124"]=0x00020101;
        state["registers"]=regs;w.updateState(state);
        auto *profile0=w.findChild<QLabel*>("dlia0Readback");
        auto *profile1=w.findChild<QLabel*>("dlia1Readback");
        check(profile0&&profile0->text().contains(QStringLiteral("四阶，1 kHz / 1 MS/s")),"Fourth-order profile label missing");
        check(profile1&&profile1->text().contains(QStringLiteral("二阶，1 kHz / 1 MS/s")),"Original profile label missing");
        check(button("startAcquisition")->isEnabled(),"Stopped WMS blocked acquisition");
        state["acquiring"]=true;w.updateState(state);
        for(auto name:{"wms0Apply","wms0Start","wms0Stop","wms1Apply","wms1Start","wms1Stop","dlia0Apply","dlia0Start","dlia0Stop","dlia1Apply","dlia1Start","dlia1Stop"})check(button(name)->isEnabled(),"Acquisition blocked independent action");
        auto *freq=w.findChild<QDoubleSpinBox*>("dlia0ReferenceHz");
        check(freq&&freq->value()==20000,"Initial device parameters not loaded");
        freq->setValue(21000);for(int i=0;i<30;i++){w.updateState(state);check(freq->value()==21000,"Refresh overwrote edited value");check(button("dlia0Apply")->isEnabled(),"Background state disabled action");}
        QString action;QJsonObject data;QObject::connect(&w,&MainWindow::requestAction,[&](QString a,QJsonObject p){action=a;data=p;});
        button("dlia0Apply")->click();check(action=="dlia_apply"&&data["channel"].toInt()==0&&data["referenceHz"].toDouble()==21000,"DLIA apply payload incorrect");
        action.clear();button("dlia0Load")->click();check(freq->value()==20000&&action.isEmpty(),"Load unexpectedly wrote hardware or failed");
        button("wms1Start")->click();check(action=="wms_start"&&data["channel"].toInt()==1,"WMS channel dispatch incorrect");
        // Voltage presentation must preserve the normalized hardware command on both channels.
        for(int ch=0;ch<2;ch++){
            auto box=[&](const char *suffix){return w.findChild<QDoubleSpinBox*>(QString("wms%1%2").arg(ch).arg(suffix));};
            auto *a=box("SawAmplitude"), *b=box("SineAmplitude"), *o=box("Offset");
            auto *apply=w.findChild<QPushButton*>(QString("wms%1Apply").arg(ch));
            auto *load=w.findChild<QPushButton*>(QString("wms%1Load").arg(ch));
            check(a&&b&&o&&apply&&load,"Missing WMS voltage controls");
            check(a->suffix()==" V"&&b->suffix()==" V"&&o->suffix()==" V","Missing voltage units");
            a->setValue(0.5);b->setValue(0.1);o->setValue(-1.25);action.clear();apply->click();
            check(action=="wms_apply"&&data["channel"].toInt()==ch,"Voltage apply dispatched wrong channel");
            check(std::abs(data["sawAmplitude"].toDouble()-.05)<1e-12&&std::abs(data["sineAmplitude"].toDouble()-.01)<1e-12&&std::abs(data["offset"].toDouble()+.125)<1e-12,"Voltage request changed physical output by wrong scale");
            const quint32 base=0x2000+ch*0x100;
            regs[QString::number(base+0x14,16)]=double(0x10000000u); // 1.25 V
            regs[QString::number(base+0x20,16)]=double(0x08000000u); // 0.625 V
            regs[QString::number(base+0x18,16)]=double(0xf0000000u); // -1.25 V
            state["registers"]=regs;action.clear();w.updateState(state);
            check(a->value()==.5,"Background refresh overwrote voltage edit");
            load->click();
            check(a->value()==1.25&&b->value()==.625&&o->value()==-1.25&&action.isEmpty(),"Voltage readback sign/scale wrong or load emitted a command");
            auto *readback=w.findChild<QLabel*>(QString("wms%1Readback").arg(ch));
            check(readback&&readback->text().contains("1.25 V")&&readback->text().contains("0.625 V")&&readback->text().contains("-1.25 V"),"Voltage summary readback incorrect");
            a->setValue(9);b->setValue(.5);o->setValue(0);action.clear();apply->click();
            check(action=="wms_apply","Exact 9.5 V boundary rejected");
            b->setValue(.6);action.clear();bool warning=false;
            QTimer::singleShot(0,[&]{for(auto *widget:QApplication::topLevelWidgets())if(auto *msg=qobject_cast<QMessageBox*>(widget)){warning=msg->text().contains("9.5 V");msg->accept();}});
            apply->click();check(action.isEmpty()&&warning,"Over-range voltage was sent or wrong warning units");
        }
        state["busy"]=true;w.updateState(state);check(!button("dlia0Apply")->isEnabled()&&!button("wms0Apply")->isEnabled(),"Foreground action not serialized");
        QTextStream(stdout)<<"UI_TEST_PASS checks="<<checks<<"\n";return 0;
    }catch(const std::exception&e){QTextStream(stderr)<<"UI_TEST_FAIL checks="<<checks<<" "<<e.what()<<"\n";return 1;}
}
