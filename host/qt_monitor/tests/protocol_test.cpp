#include "protocol.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTextStream>
#include <QThread>
#include <QtEndian>
#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>

namespace {
int checks=0;
void check(bool condition,const char *message){++checks;if(!condition)throw std::runtime_error(message);}
void near(double actual,double expected,double tolerance,const char *message){check(std::abs(actual-expected)<=tolerance,message);}
void w16(QByteArray &b,int offset,quint16 n){qToLittleEndian(n,b.data()+offset);}
void w32(QByteArray &b,int offset,quint32 n){qToLittleEndian(n,b.data()+offset);}
void w64(QByteArray &b,int offset,quint64 n){qToLittleEndian(n,b.data()+offset);}
void wf32(QByteArray &b,int offset,float f){quint32 n;std::memcpy(&n,&f,4);w32(b,offset,n);}
void wf64(QByteArray &b,int offset,double f){quint64 n;std::memcpy(&n,&f,8);w64(b,offset,n);}
quint32 crc(const QByteArray &b){quint32 c=0xffffffff;for(auto x:b){c^=quint8(x);for(int i=0;i<8;++i)c=(c>>1)^((c&1)?0xedb88320:0);}return c^0xffffffff;}
QByteArray wire(const VlpFrame &f){QByteArray b(40,0);std::memcpy(b.data(),"VLP1",4);b[4]=1;b[6]=char(f.kind);b[7]=10;w32(b,8,44+f.payload.size());w32(b,12,f.sequence);w16(b,16,f.source);w16(b,18,f.message);w32(b,20,f.flags);w64(b,24,f.ticks);w32(b,32,f.cycle);w32(b,36,f.payload.size());b+=f.payload;quint32 c=crc(b);int pos=b.size();b.resize(pos+4);w32(b,pos,c);while(b.size()%4)b+=char(0);return b;}
VlpFrame raw(int ch,int index,int parts,int first,int total,QVector<qint32> values,quint32 cycle=1,quint32 flags=3){
    VlpFrame f;f.kind=0x10;f.source=0x20+ch;f.message=0x1000;f.sequence=index;f.flags=flags;f.ticks=quint64(cycle)*1000000;f.cycle=cycle;f.payload=QByteArray(32+4*values.size(),0);
    w16(f.payload,0,2);w16(f.payload,2,24);w32(f.payload,4,1000000);w32(f.payload,8,total);w16(f.payload,16,index);w16(f.payload,18,parts);w32(f.payload,20,first);w32(f.payload,24,values.size());
    for(int i=0;i<values.size();++i)w32(f.payload,32+4*i,quint32(values[i]));
    return f;
}
VlpFrame dlia(int index,int parts,int first,int total,int size,quint32 cycle=1,quint32 flags=3,int format=0){
    VlpFrame f;f.kind=0x10;f.source=0x30;f.message=0x1001;f.flags=flags;f.cycle=cycle;f.ticks=quint64(cycle)*1000000;int width=(format+1)*8;f.payload=QByteArray(32+size*width,0);
    w16(f.payload,0,2);w16(f.payload,2,format);w32(f.payload,4,10000);w32(f.payload,8,total);w16(f.payload,12,index);w16(f.payload,14,parts);w32(f.payload,16,first);w32(f.payload,20,size);w32(f.payload,24,width);
    for(int i=0;i<size;++i){int at=32+i*width;if(format==0){w32(f.payload,at,100+first+i);w32(f.payload,at+4,200+first+i);}else{w32(f.payload,at,3);w32(f.payload,at+4,4);w32(f.payload,at+8,5);w32(f.payload,at+12,12);if(format==2){w32(f.payload,at+16,5);w32(f.payload,at+20,13);}}}return f;
}
struct Tag {quint16 tag;quint8 type;QByteArray value;};
QByteArray word(quint32 n){QByteArray b(4,0);w32(b,0,n);return b;}
VlpFrame tlv(int source,QList<Tag> tags,quint32 flags=1){VlpFrame f;f.kind=0x10;f.source=source;f.message=0x1100;f.flags=flags;f.ticks=10000000;f.payload=QByteArray(4,0);w16(f.payload,0,source==0x46?2:1);w16(f.payload,2,tags.size());for(const auto &t:tags){int at=f.payload.size();f.payload.resize(at+4);w16(f.payload,at,t.tag);f.payload[at+2]=char(t.type);f.payload[at+3]=char(t.value.size());f.payload+=t.value;while(f.payload.size()%4)f.payload+=char(0);}return f;}
VlpFrame epsilon(int id,QByteArray payload,quint64 ticks=10000000){VlpFrame f;f.kind=0x10;f.source=0x42;f.message=0x1200;f.flags=1;f.ticks=ticks;QByteArray b(7,0);b[0]=char(0xfc);b[1]=char(id);b[2]=char(payload.size());quint8 c8=0;for(int i=0;i<4;++i){c8^=quint8(b[i]);for(int j=0;j<8;++j)c8=(c8>>1)^((c8&1)?0x8c:0);}b[4]=char(c8);quint16 c16=0;for(auto x:payload){c16^=quint16(quint8(x))<<8;for(int j=0;j<8;++j)c16=quint16((c16<<1)^((c16&0x8000)?0x1021:0));}b[5]=char(c16>>8);b[6]=char(c16);b+=payload;b+=char(0xfd);f.payload=b;return f;}
QJsonObject channel(const DataDecoder &d,const char *name,int channel=0){return d.snapshot()[name].toArray()[channel].toObject();}
QJsonObject sensor(const DataDecoder &d,int index){return d.snapshot()["sensors"].toArray()[index].toObject();}
QVector<double> trendValues(const QJsonObject &s){QVector<double> result;for(const auto &p:s["trend"].toArray())if(p.isArray())result.push_back(p.toArray()[1].toDouble());return result;}
int trendGaps(const QJsonObject &s){int result=0;for(const auto &p:s["trend"].toArray())if(p.isNull())++result;return result;}
VlpFrame ai8Sample(quint32 number,qint32 pv,quint32 host=0x200,quint32 alarm=0,quint32 control=3,quint32 status=1){
    auto frame=tlv(0x46,{{0x460,7,word(quint32(pv))},{0x461,7,word(400)},{0x462,7,word(350)},
        {0x463,3,word(7)},{0x464,3,word(alarm)},{0x465,3,word(control)},{0x466,3,word(host)},
        {0x467,3,word(0)},{1,3,word(status)},{2,3,word((host<<16)|(control<<8)|alarm)},{4,3,word(number)}},
        1|((host&0x300)||alarm||status!=1?16:0));
    frame.ticks=quint64(number)*100000000;return frame;
}
void framingTests(){
    VlpParser parser;
    auto read=VlpParser::command(2,false,0,{},5);
    check(read.toHex()==QByteArray("564c50310100010a34000000020000000100020000000000000000000000000000000000080000000000000005000000c688b7db"),"READ golden frame differs");
    auto write=VlpParser::command(3,true,0x6004,{1});auto all=read+write;
    for(int chunk=1;chunk<=int(all.size());++chunk){parser.reset();QVector<VlpFrame> got;for(int at=0;at<all.size();at+=chunk)got+=parser.feed(all.mid(at,chunk));check(got.size()==2 && got[1].message==3,"arbitrary USB fragmentation changed frames");check(parser.statistics()["bufferedBytes"].toInt()==0,"complete stream retained bytes");}
    auto bad=read;bad[40]^=1;parser.reset();auto got=parser.feed(QByteArray("junk")+bad+write);check(got.size()==1 && got[0].message==3,"CRC corruption updated/corrupted following frame");check(parser.statistics()["crcErrors"].toInt()==1,"CRC mismatch not counted");
    auto damaged=read;w32(damaged,8,8044);w32(damaged,36,8000);parser.reset();got=parser.feed(damaged+write);check(got.isEmpty(),"incomplete plausible length guessed before timeout");got=parser.expirePartial();check(got.size()==1 && got[0].message==3,"timed-out corrupt length hides valid frame");
    VlpFrame outer;outer.kind=0x10;outer.payload=read+QByteArray(500,'X');auto embedded=wire(outer);parser.reset();got=parser.feed(embedded.left(40+read.size()));check(got.isEmpty(),"embedded VLP payload misparsed as frame");got=parser.feed(embedded.mid(40+read.size()));check(got.size()==1 && got[0].payload==outer.payload,"arbitrary fragmentation of embedded frame payload failed");
    VlpFrame odd;odd.kind=2;odd.payload="a";auto padded=wire(odd);padded[padded.size()-1]=1;parser.reset();got=parser.feed(padded+read);check(got.size()==1 && parser.statistics()["paddingErrors"].toInt()==1,"bad padding accepted");
    parser.reset();parser.feed(QByteArray(2*1024*1024,'X'));check(parser.statistics()["bufferedBytes"].toInt()<=3,"unframed parser memory unbounded");
    check(VlpParser::command(1,false,1,{}).isEmpty(),"unaligned command accepted");check(VlpParser::command(1,false,0,{},1022).isEmpty(),"oversized command accepted");
}
void fragmentTests(){
    DataDecoder decoder;
    check(channel(decoder,"adc")["minV"].isNull() && channel(decoder,"adc")["points"].toArray().isEmpty(),"missing data became zero");
    auto a=raw(0,0,2,0,4,{8388607,-8388608});auto b=raw(0,1,2,2,4,{100,-100});decoder.accept(b);check(channel(decoder,"adc")["count"].toInt()==0,"incomplete cycle emitted");decoder.accept(a);
    auto out=channel(decoder,"adc");check(out["count"].toInt()==4 && out["cycles"].toInt()==1,"out of order cycle not assembled");near(out["minV"].toDouble(),-10,1e-12,"signed full scale conversion");near(out["maxV"].toDouble(),8388607*10.0/8388608,1e-12,"positive conversion");
    decoder.accept(a);decoder.accept(b);check(channel(decoder,"adc")["count"].toInt()==4,"duplicate complete cycle double counted");
    decoder.accept(raw(1,0,1,0,2,{8388607,-8388608}));out=channel(decoder,"adc",1);near(out["maxV"].toDouble(),10,1e-12,"CON16 inversion");decoder.setAdcGain(1,1);near(channel(decoder,"adc",1)["maxV"].toDouble(),5,1e-12,"gain change not applied to history");
    decoder.reset();for(int cycle=1;cycle<=7;++cycle)decoder.accept(raw(0,0,2,0,4,{1,2},cycle));out=channel(decoder,"adc");check(out["count"].toInt()==0 && out["pendingCycles"].toInt()<=4 && out["incompleteCycles"].toInt()>=3,"missing fragments unbounded or emitted");
    decoder.reset();decoder.accept(a);decoder.accept(a);decoder.accept(b);check(channel(decoder,"adc")["count"].toInt()==0,"duplicate fragment cycle emitted");
    decoder.reset();decoder.accept(a);auto overlap=b;w32(overlap.payload,20,1);decoder.accept(overlap);check(channel(decoder,"adc")["count"].toInt()==0,"overlap accepted");
    decoder.reset();decoder.accept(a);auto inconsistent=b;inconsistent.flags|=32;decoder.accept(inconsistent);check(channel(decoder,"adc")["count"].toInt()==0,"inconsistent flags accepted");
    decoder.reset();decoder.accept(raw(0,0,1,0,2,{8388608,1}));check(channel(decoder,"adc")["count"].toInt()==0 && channel(decoder,"adc")["minV"].isNull(),"invalid width polluted ranges");
    decoder.reset();QVector<qint32> values(10000,10);values[523]=7654321;values[7203]=-7654321;
    for(int part=0;part<10;++part)decoder.accept(raw(0,part,10,part*1000,10000,values.mid(part*1000,1000)));
    out=channel(decoder,"adc");auto points=out["points"].toArray();check(points.size()<=1200,"RAW plot exceeds bound");double lo=1e30,hi=-1e30;for(const auto &v:points){double y=v.toArray()[1].toDouble();lo=std::min(lo,y);hi=std::max(hi,y);}near(lo,-7654321*10.0/8388608,1e-10,"min downsampling lost impulse");near(hi,7654321*10.0/8388608,1e-10,"max downsampling lost impulse");
    decoder.reset();decoder.accept(dlia(1,2,50,100,50));decoder.accept(dlia(0,2,0,100,50));out=channel(decoder,"dlia");check(out["count"].toInt()==100 && out["peaks"].toArray().size()==1,"DLIA complete scan assembly");near(out["peaks"].toArray()[0].toArray()[1].toDouble(),299,0,"DLIA peak not digital amplitude");
    decoder.accept(dlia(0,1,0,50,50,2));check(channel(decoder,"dlia")["peaks"].toArray().last().isNull(),"short cycle peak falsely represented full scan");
    decoder.accept(dlia(0,1,0,100,100,3,35));out=channel(decoder,"dlia");check(out["cycle"].toInt()==1 && out["latestReceivedCycle"].toInt()==3 && out["displayFullCycle"].toBool(),"partial tail replaced full scan plot");
    decoder.reset();decoder.accept(dlia(0,1,0,100,100,3,35));check(channel(decoder,"dlia")["h1"].toArray()[1].isNull(),"partial-only cycle unknown gaps connected");
    decoder.reset();decoder.setScanHz(0,1000);decoder.accept(dlia(0,1,0,10,10,1,3,1));out=channel(decoder,"dlia");check(out["peaks"].toArray().size()==1,"scan readback rate not applied");near(out["h1"].toArray()[0].toArray()[1].toDouble(),5,0,"IQ amplitude conversion");near(out["h2"].toArray()[0].toArray()[1].toDouble(),13,0,"IQ second harmonic conversion");
}
void sensorTests(){
    DataDecoder decoder;
    auto ptb=tlv(0x40,{{0x12,7,word(101459000)},{0x999,77,QByteArray("abc")}});decoder.accept(ptb);near(sensor(decoder,0)["fields"].toObject()[QStringLiteral("压力 (hPa)")].toDouble(),1014.59,1e-10,"PTB mPa scaling / unknown TLV skip");
    auto broken=ptb;broken.payload[6]=3;decoder.accept(broken);check(sensor(decoder,0)["count"].toInt()==1,"wrong known TLV type accepted");
    decoder.accept(tlv(0x44,{{0x10,7,word(quint32(-5000))},{0x11,3,word(50123)},{1,3,word(1)}},17));auto s=sensor(decoder,3);near(s["fields"].toObject()[QStringLiteral("温度 (℃)")].toDouble(),-5,0,"SHT signed temperature");check(s["quality"].toString().contains(QStringLiteral("加热")),"SHT heater quality hidden");
    auto cal=QByteArray::fromHex("986d4c4bf9fd1c4d1706019349005a03fa800f08f5");decoder.accept(tlv(0x43,{{0x100,11,cal}}));check(sensor(decoder,2)["count"].toInt()==0,"calibration counted as pressure sample");decoder.accept(tlv(0x43,{{0x101,3,word(6462464)},{0x102,3,word(8499712)}}));s=sensor(decoder,2);auto fields=s["fields"].toObject();near(fields[QStringLiteral("温度 (℃)")].toDouble(),23.606603474356234,1e-8,"BMP temperature golden");near(fields[QStringLiteral("压力 (hPa)")].toDouble(),1015.2405066707481,1e-6,"BMP pressure golden");
    decoder.accept(tlv(0x45,{{0x13,3,word(12345)}}));near(sensor(decoder,4)["fields"].toObject()[QStringLiteral("距离 (mm)")].toDouble(),12345,0,"TFA multiplied already-scaled distance");
    QList<Tag> ai={{0x460,7,word(quint32(-123))},{0x461,7,word(400)},{0x462,7,word(350)},{0x463,3,word(7)},{0x464,3,word(0x20)},{0x465,3,word(0)},{0x466,3,word(0x200)},{0x467,3,word(0)},{1,3,word(1)},{2,3,word(0x02000020)},{4,3,word(1)}};
    decoder.accept(tlv(0x46,ai,17));s=sensor(decoder,5);near(s["fields"].toObject()[QStringLiteral("PV 实际温度 (℃)")].toDouble(),-12.3,1e-10,"AI8 signed scaling");check(s["quality"].toString().contains(QStringLiteral("报警")),"AI8 alarm falsely healthy");
    QByteArray ahrs(48,0);wf32(ahrs,12,float(3.14159265358979323846/2));wf32(ahrs,16,-.25f);wf32(ahrs,20,.5f);wf32(ahrs,24,1);decoder.accept(epsilon(0x41,ahrs));s=sensor(decoder,1);near(s["fields"].toObject()[QStringLiteral("横滚 (°)")].toDouble(),90,1e-5,"EPS AHRS offset/radians");check(s["fields"].toObject()[QStringLiteral("导航数据有效性")].toString().contains(QStringLiteral("未知")),"attitude inferred navigation valid");
    QByteArray nav(102,0);w16(nav,2,0x3f);w16(nav,4,0xc);w32(nav,6,1700000000);w32(nav,10,123456);wf64(nav,14,.5);wf64(nav,22,-1.25);wf64(nav,30,32.1);wf32(nav,38,1.2f);decoder.accept(epsilon(0x50,nav));s=sensor(decoder,1);fields=s["fields"].toObject();near(fields[QStringLiteral("融合 纬度 (°，原始)")].toDouble(),.5*180/3.14159265358979323846,1e-12,"EPS latitude F64 scaling/order");near(fields[QStringLiteral("融合 经度 (°，原始)")].toDouble(),-1.25*180/3.14159265358979323846,1e-12,"EPS longitude signed double");check(fields[QStringLiteral("UTC 有效性")].toString()==QStringLiteral("有效"),"EPS initialized UTC not accepted");
    auto bad=epsilon(0x41,ahrs);bad.payload[10]^=1;decoder.accept(bad);check(sensor(decoder,1)["count"].toInt()==2,"inner CRC corrupt frame updated values");
    wf32(ahrs,12,std::numeric_limits<float>::quiet_NaN());decoder.accept(epsilon(0x41,ahrs));check(sensor(decoder,1)["count"].toInt()==2,"NaN AHRS accepted");
    QThread::msleep(3100);s=sensor(decoder,1);check(s["stale"].toBool() && s["quality"].toString().contains(QStringLiteral("过期")),"host monotonic freshness did not expire");check(s["fields"].toObject()[QStringLiteral("UTC 有效性")].toString()!=QStringLiteral("有效"),"stale UTC remains valid");
    wf32(ahrs,12,0);decoder.accept(epsilon(0x41,ahrs));s=sensor(decoder,1);check(!s["stale"].toBool(),"fresh AHRS not recognized");check(s["fields"].toObject()[QStringLiteral("导航数据有效性")].toString().contains(QStringLiteral("过期")),"fresh attitude wrongly refreshed old navigation status");
    decoder.reset();decoder.accept(tlv(0x43,{{0x101,3,word(6462464)},{0x102,3,word(8499712)}}));check(!sensor(decoder,2)["fields"].toObject().contains(QStringLiteral("压力 (hPa)")),"calibration leaked across session reset");
}
void sensorTrendTests(){
    DataDecoder decoder;
    for(int i=1;i<=5;++i)decoder.accept(ai8Sample(i,200+i));
    auto s=sensor(decoder,5);auto values=trendValues(s);
    check(s["count"].toInt()==5 && values.size()==5,"AI8 flagged one-Hz samples collapsed to one point");
    near(values.first(),20.1,1e-12,"first flagged AI8 sample discarded");near(values.last(),20.5,1e-12,"last flagged AI8 sample discarded");
    check(trendGaps(s)==0,"global alarm alone invented gaps between valid samples");
    check(s["quality"].toString().contains(QStringLiteral("全局报警")) && s["fields"].toObject()[QStringLiteral("通信状态")].toString().contains(QStringLiteral("正常")),"global alarm confused with communication failure");
    check(s["flags"].toInt()==17 && s["flaggedCount"].toInt()==5,"AI8 flagged samples silently normalized");
    auto ticks=s["ticks"].toDouble();auto age=s["ageMs"].toDouble();
    QThread::msleep(20);
    decoder.accept(ai8Sample(6,999,0x200,0,3,2));s=sensor(decoder,5);
    check(s["count"].toInt()==5 && s["invalidSamples"].toInt()==1 && s["recordCount"].toInt()==6,"failed poll counted as fresh measurement");
    check(s["ticks"].toDouble()==ticks && s["ageMs"].toDouble()>=age+15 && !s["sampleValid"].toBool(),"failed poll refreshed measurement time/validity");
    check(trendValues(s).size()==5 && trendGaps(s)==1,"failed cached PV appended to trend or lost previous bucket");
    near(s["fields"].toObject()[QStringLiteral("PV 实际温度 (℃) [历史/无效记录未更新]")].toDouble(),20.5,1e-12,"failed poll overwrote cached good temperature");
    decoder.accept(ai8Sample(7,998,0x200,0,3,5)); // Online set but transport error=2.
    decoder.accept(ai8Sample(8,997,0x200,0,3,(7<<5)|1)); // Online set but Modbus exception=7.
    s=sensor(decoder,5);check(s["count"].toInt()==5 && s["invalidSamples"].toInt()==3,"online bit masked transport/exception errors");
    decoder.accept(ai8Sample(9,209));s=sensor(decoder,5);
    check(s["sampleValid"].toBool() && trendValues(s).size()==6 && trendGaps(s)==1,"recovery lost history or bridged failed interval");
    near(trendValues(s).last(),20.9,1e-12,"recovery measurement missing");
    decoder.reset();decoder.accept(ai8Sample(1,220,0,0,3));s=sensor(decoder,5);
    check(s["quality"].toString()==QStringLiteral("数据新鲜"),"normal CONTROL bits interpreted as DEVICE_ERROR fault");
    near(s["fields"].toObject()[QStringLiteral("状态组合原码 (HOST/CONTROL/ALARM)")].toDouble(),0x300,0,"packed AI8 status was removed instead of interpreted");
    decoder.accept(ai8Sample(2,221,0,0x20,3));check(sensor(decoder,5)["quality"].toString().contains(QStringLiteral("通道报警")),"real channel alarm hidden");
    decoder.accept(ai8Sample(3,222,0x100,0,3));check(sensor(decoder,5)["quality"].toString().contains(QStringLiteral("系统故障")),"real HOST system fault hidden");
    check(trendValues(sensor(decoder,5)).size()==3,"healthy and alarm samples not preserved together");
    decoder.reset();
    auto first=tlv(0x40,{{0x12,7,word(100000000)}},17);first.ticks=100000000;
    auto second=first;second.ticks+=5000000;w32(second.payload,8,100100000);second.flags=25;
    decoder.accept(first);decoder.accept(second);s=sensor(decoder,0);
    check(trendValues(s).size()==2 && trendGaps(s)==1,"overflow lost unflushed sample in the same bin");
    near(trendValues(s).first(),1000,0,"overflow reordered history");near(trendValues(s).last(),1001,0,"overflow lost current point");
    auto malformed=second;malformed.payload[6]=3;decoder.accept(malformed);s=sensor(decoder,0);
    check(trendValues(s).size()==2 && s["invalidRecords"].toInt()==1,"malformed sample lost last bucket or invented point");
    auto recovery=first;recovery.ticks=106000000;w32(recovery.payload,8,100200000);decoder.accept(recovery);s=sensor(decoder,0);
    check(trendValues(s).size()==3 && trendGaps(s)==2,"same-bin recovery after format error lost point/gap");
    auto late=recovery;late.ticks+=400000000;decoder.accept(late);
    check(trendValues(sensor(decoder,0)).size()==4 && trendGaps(sensor(decoder,0))==3,"recording timestamp gap silently connected");
    auto untimed=late;untimed.ticks+=100000000;untimed.flags=0;decoder.accept(untimed);
    check(trendValues(sensor(decoder,0)).size()==4,"invalid FPGA timestamp entered ordinary time curve");
    decoder.reset();for(int i=1;i<=1500;++i)decoder.accept(ai8Sample(i,200+i%5));s=sensor(decoder,5);
    check(s["count"].toInt()==1500 && s["trend"].toArray().size()<=1200 && trendValues(s).size()>1100,"long alarm history unbounded or erased");
}
void dliaRateFormatTests(){
    for(int format=0;format<3;++format)for(int rate:{6000,25000,125000}){
        DataDecoder decoder;const int total=rate/100,parts=(total+249)/250;
        for(int index=parts-1;index>=0;--index){int first=index*250,size=std::min(250,total-first);auto f=dlia(index,parts,first,total,size,1,3,format);w32(f.payload,4,rate);
            if(format==2)for(int i=0;i<size;++i){w32(f.payload,32+i*24,100);w32(f.payload,36+i*24,200);} // Provided H fields must win over I/Q.
            decoder.accept(f);
        }
        auto s=channel(decoder,"dlia");check(s["count"].toInt()==total && s["displayFullCycle"].toBool(),"variable-rate DLIA reassembly/full-cycle classification failed");
        check(s["rateHz"].toInt()==rate && s["format"].toInt()==format && s["pointsPerCycle"].toInt()==total,"reported DLIA format/rate lost");
        check(s["h1"].toArray().size()<=1200 && s["h2"].toArray().size()<=1200,"high-rate DLIA plots exceed bounds");
        near(s["peaks"].toArray()[0].toArray()[1].toDouble(),format==0?199+total:13,0,"DLIA format amplitude interpretation changed");
        if(total<=1200)near(s["h1"].toArray().last().toArray()[0].toDouble(),(total-1)*1000.0/rate,1e-12,"DLIA time axis uses requested/hardcoded rate");
    }
}
void captureTest(const QString &path){
    QFile file(path);check(file.open(QIODevice::ReadOnly),"cannot open replay capture");
    VlpParser parser;DataDecoder decoder;QElapsedTimer timer;timer.start();quint64 frameCount=0;QMap<int,int> sensorFlags;
    // Variable read sizes exercise boundaries unrelated to VLP frame lengths.
    const int chunks[]={1,7,511,16381,65536};int chunk=0;
    while(!file.atEnd()){auto frames=parser.feed(file.read(chunks[chunk++%5]));for(const auto &f:frames){++frameCount;decoder.accept(f);if(f.kind==0x10 && f.flags&16)sensorFlags[f.source]++;}}
    const qint64 elapsed=timer.elapsed();auto stats=parser.statistics();auto snapshot=decoder.snapshot();
    check(frameCount==93466,"real capture frame count mismatch");check(stats["crcErrors"].toInt()==0 && stats["framingErrors"].toInt()==0 && stats["paddingErrors"].toInt()==0,"real capture CRC/framing/padding mismatch");check(stats["bufferedBytes"].toInt()==0,"capture trailing bytes");check(snapshot["decodeErrors"].toInt()==0,"real capture decode errors");
    auto a0=channel(decoder,"adc",0),a1=channel(decoder,"adc",1);check(a0["count"].toInt()==302994 && a1["count"].toInt()==303876,"real RAW point count mismatch");
    check(a0["partialCycles"].toInt()==1 && a1["partialCycles"].toInt()==1,"real partial RAW history disappeared");
    check(a0["displayFullCycle"].toBool() && a1["displayFullCycle"].toBool(),"real RAW full scan plot replaced by trailing partial");check(a0["points"].toArray().last().toArray()[0].toDouble()>9 && a1["points"].toArray().last().toArray()[0].toDouble()>9,"real RAW full scan duration cropped");
    near(a0["codeMin"].toDouble(),1071651,0,"real ADC0 minimum");near(a0["codeMax"].toDouble(),2826286,0,"real ADC0 maximum");near(a1["codeMin"].toDouble(),1721769,0,"real ADC1 minimum");near(a1["codeMax"].toDouble(),4277755,0,"real ADC1 maximum");
    near(a0["minV"].toDouble(),1.2775075435638428,1e-12,"real CON15 lower volts");near(a0["maxV"].toDouble(),3.3691954612731934,1e-12,"real CON15 upper volts");near(a1["minV"].toDouble(),-5.0994813442230225,1e-12,"real CON16 lower volts");near(a1["maxV"].toDouble(),-2.052508592605591,1e-12,"real CON16 upper volts");
    check(channel(decoder,"dlia",0)["count"].toInt()==403645 && channel(decoder,"dlia",1)["count"].toInt()==403653,"real DLIA points mismatch");check(channel(decoder,"dlia",0)["cycles"].toInt()==4038 && channel(decoder,"dlia",1)["cycles"].toInt()==4038,"real DLIA cycle counts");
    const int expected[]={1,36836,50,50,41768,46};auto sensors=snapshot["sensors"].toArray();for(int i=0;i<6;++i){check(sensors[i].toObject()["count"].toInt()==expected[i],"real sensor count mismatch");check(sensors[i].toObject()["trend"].toArray().size()<=1200,"sensor trend exceeds bound");}
    check(sensorFlags[0x40]==1 && sensorFlags[0x46]==46,"real sensor flags lost");check(sensors[0].toObject()["quality"].toString().contains(QStringLiteral("异常")),"real PTB flagged sample marked healthy");check(sensors[5].toObject()["quality"].toString().contains(QStringLiteral("报警")),"real AI8 alarm marked healthy");check(sensors[1].toObject()["fields"].toObject()[QStringLiteral("UTC 有效性")].toString()!=QStringLiteral("有效"),"indoor real EPS UTC incorrectly valid");
    check(trendValues(sensors[0].toObject()).size()==1,"single real PTB record fabricated additional samples");
    check(trendValues(sensors[5].toObject()).size()==46,"real AI8 valid-but-flagged history still collapses to a dot");
    QTextStream(stdout)<<"CAPTURE_PASS frames="<<frameCount<<" bytes="<<file.size()<<" elapsed_ms="<<elapsed<<" MiB_per_second="<<(file.size()/1048576.0/std::max(.001,elapsed/1000.0))<<"\n";
    if(qEnvironmentVariableIsSet("VAPOR_TEST_SNAPSHOT")){QFile output(qEnvironmentVariable("VAPOR_TEST_SNAPSHOT"));if(output.open(QIODevice::WriteOnly))output.write(QJsonDocument(snapshot).toJson());}
}
}
int main(int argc,char **argv){QCoreApplication app(argc,argv);try{framingTests();fragmentTests();sensorTests();sensorTrendTests();dliaRateFormatTests();if(app.arguments().size()>1){QString path=app.arguments()[1];check(QFile::exists(path),"Requested capture file does not exist");captureTest(path);}else QTextStream(stdout)<<"CAPTURE_SKIPPED no capture path supplied\n";QTextStream(stdout)<<"PROTOCOL_TEST_PASS checks="<<checks<<"\n";return 0;}catch(const std::exception &e){QTextStream(stderr)<<"PROTOCOL_TEST_FAIL after "<<checks<<" checks: "<<e.what()<<"\n";return 1;}}
