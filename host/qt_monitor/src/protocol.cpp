#include "protocol.h"
#include <QDateTime>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QMap>
#include <QSet>
#include <QTimeZone>
#include <QtEndian>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <deque>
#include <limits>

namespace {
constexpr int MaxPayload = 8192;
constexpr int MaxWire = MaxPayload + 44;
constexpr qint64 StaleMs = 3000; // Host policy, not a sensor protocol constant.
constexpr double TickHz = 100000000.0;
constexpr double Degrees = 180.0 / 3.14159265358979323846;
quint16 u16(const char *p) { return qFromLittleEndian<quint16>(p); }
quint32 u32(const char *p) { return qFromLittleEndian<quint32>(p); }
quint64 u64(const char *p) { return qFromLittleEndian<quint64>(p); }
qint32 i32(const char *p) { return qFromLittleEndian<qint32>(p); }
qint16 i16(const char *p) { return qFromLittleEndian<qint16>(p); }
double f32(const char *p) { quint32 b=u32(p); float f; std::memcpy(&f,&b,4); return f; }
double f64(const char *p) { quint64 b=u64(p); double f; std::memcpy(&f,&b,8); return f; }
void put16(QByteArray &b, int offset, quint16 v) { qToLittleEndian(v,b.data()+offset); }
void put32(QByteArray &b, int offset, quint32 v) { qToLittleEndian(v,b.data()+offset); }
quint32 crc32(const char *p, qsizetype n) {
    static const auto table=[] { std::array<quint32,256> t{}; for (quint32 i=0;i<256;++i) {
        quint32 x=i; for(int j=0;j<8;++j) x=(x>>1)^((x&1)?0xedb88320u:0); t[i]=x; } return t; }();
    quint32 crc=0xffffffffu;
    for(qsizetype i=0;i<n;++i) crc=(crc>>8)^table[(crc^quint8(p[i]))&255];
    return crc^0xffffffffu;
}
bool headerOk(const char *p) {
    const quint8 kind=quint8(p[6]);
    return !std::memcmp(p,"VLP1",4) && p[4]==1 && p[5]==0 && p[7]==10
        && (kind==1 || kind==2 || kind==0x10 || kind==0x11 || kind==0x12 || kind==0x7f)
        && u32(p+36)<=MaxPayload && u32(p+8)==44+u32(p+36);
}
QString flagQuality(quint32 flags, bool cycle=false) {
    QStringList q;
    if (!(flags&1)) q<<QStringLiteral("时间戳无效");
    if(cycle && !(flags&2)) q<<QStringLiteral("周期标识无效");
    if(flags&8) q<<QStringLiteral("存在丢弃/间断");
    if(flags&16) q<<QStringLiteral("设备异常");
    if(flags&32) q<<QStringLiteral("部分数据（时间位置仅估算）");
    if(flags&64) q<<QStringLiteral("配置变化");
    if(flags&~0x1ffu) q<<QStringLiteral("未知标志位");
    return q.isEmpty()?QStringLiteral("数据新鲜"):q.join(QStringLiteral("；"));
}
struct Point { double x=0,y=0; bool gap=false; };
QJsonArray pointsJson(const std::deque<Point> &p, double scale=1, bool scatter=false) {
    QJsonArray out;
    for(const auto &v:p) {
        if(v.gap) out.append(QJsonValue::Null);
        else { out.append(QJsonArray{v.x,v.y*scale}); if(scatter) out.append(QJsonValue::Null); }
    }
    return out;
}
void appendBounded(std::deque<Point> &p, Point v, size_t max=1200) {
    p.push_back(v); while(p.size()>max) p.pop_front();
}
void addGap(std::deque<Point> &p) { if(!p.empty() && !p.back().gap) appendBounded(p,{0,0,true}); }
struct Bin { bool used=false; Point min,max; };
// Bucket extrema retain the actual sample positions; never interpolate discarded samples.
std::deque<Point> extrema(const QVector<double> &values, quint32 rate, int limit=1200) {
    std::deque<Point> result;
    if(values.size()<=limit) { for(qsizetype i=0;i<values.size();++i) result.push_back({i*1000.0/rate,values[i],false}); return result; }
    QVector<Bin> bins(limit/2);
    for(qsizetype i=0;i<values.size();++i) {
        auto &b=bins[int(qint64(i)*bins.size()/values.size())]; Point p{i*1000.0/rate,values[i],false};
        if(!b.used) { b.used=true; b.min=b.max=p; } else { if(p.y<b.min.y)b.min=p; if(p.y>b.max.y)b.max=p; }
    }
    for(const auto &b:bins) if(b.used) {
        if(b.min.x<b.max.x) {result.push_back(b.min);result.push_back(b.max);}
        else {result.push_back(b.max);if(b.min.x!=b.max.x)result.push_back(b.min);}
    }
    return result;
}
}

QVector<VlpFrame> VlpParser::feed(const QByteArray &bytes) {
    bytes_+=quint64(bytes.size());
    QVector<VlpFrame> frames;
    // Ingest bounded pieces even when callers hand us an entire recording.
    for(qsizetype input=0;input<bytes.size();) {
        const qsizetype take=std::min<qsizetype>(MaxWire,bytes.size()-input);
        buffer_.append(bytes.constData()+input,take); input+=take;
        qsizetype pos=0;
        while(buffer_.size()-pos>=4) {
            const qsizetype found=buffer_.indexOf("VLP1",pos);
            if(found<0) { if(buffer_.size()-pos>3)++framingErrors_; pos=std::max(pos,buffer_.size()-3); break; }
            if(found!=pos) {++framingErrors_;pos=found;}
            if(buffer_.size()-pos<40)break;
            const char *p=buffer_.constData()+pos;
            if(!headerOk(p)) {++framingErrors_;++pos;continue;}
            const quint32 total=u32(p+8), wire=(total+3)&~3u;
            if(buffer_.size()-pos<wire) {
                // Payload may legitimately contain a complete VLP frame. Do not interpret
                // it as a new boundary until CRC fails or the caller expires the partial.
                break;
            }
            if(crc32(p,total-4)!=u32(p+total-4)) {++crcErrors_;++pos;continue;}
            bool padded=true;for(quint32 j=total;j<wire;++j)if(p[j])padded=false;
            if(!padded) {++paddingErrors_;pos+=wire;continue;}
            VlpFrame f;f.kind=quint8(p[6]);f.sequence=u32(p+12);f.source=u16(p+16);f.message=u16(p+18);
            f.flags=u32(p+20);f.ticks=u64(p+24);f.cycle=u32(p+32);f.payload=QByteArray(p+40,u32(p+36));
            frames.push_back(std::move(f));++frames_;pos+=wire;
        }
        if(pos)buffer_.remove(0,pos);
    }
    return frames;
}
QVector<VlpFrame> VlpParser::expirePartial() {
    if(buffer_.isEmpty())return {};
    ++framingErrors_;
    QByteArray remaining=buffer_.mid(1);buffer_.clear();
    auto recovered=feed(remaining);bytes_-=quint64(remaining.size());return recovered;
}
void VlpParser::reset() {buffer_.clear();frames_=crcErrors_=framingErrors_=paddingErrors_=bytes_=0;}
QJsonObject VlpParser::statistics() const {
    return {{"frames",double(frames_)},{"crcErrors",double(crcErrors_)},{"framingErrors",double(framingErrors_)},
        {"paddingErrors",double(paddingErrors_)},{"bytes",double(bytes_)},{"bufferedBytes",double(buffer_.size())}};
}
QByteArray VlpParser::command(quint32 sequence,bool write,quint32 address,const QVector<quint32>&values,quint32 readCount) {
    const quint32 count=write?quint32(values.size()):readCount;
    if(!count || count>(write?1011u:1021u) || (address&3) || quint64(address)+quint64(count-1)*4>0xffffffffu)return {};
    QByteArray b(52+(write?4*int(count):0),char(0));
    std::memcpy(b.data(),"VLP1",4);b[4]=1;b[6]=1;b[7]=10;
    put32(b,8,quint32(b.size()));put32(b,12,sequence);put16(b,16,1);put16(b,18,write?3:2);
    put32(b,36,quint32(b.size()-44));put32(b,40,address);put16(b,44,quint16(count));
    for(int i=0;write && i<values.size();++i)put32(b,48+4*i,values[i]);
    put32(b,int(b.size()-4),crc32(b.constData(),b.size()-4));return b;
}

struct DataDecoder::Impl {
    struct Sensor {
        QString name,label,unit,issue;
        quint16 source=0;
        QJsonObject fields;
        QMap<QString,qint64> fieldTime;
        quint64 count=0,ticks=0,invalid=0;
        quint64 recordCount=0,invalidSamples=0;
        quint64 flaggedCount=0;
        quint32 seenFlags=0;
        quint32 flags=0;
        qint64 last=-1;
        bool measurementValid=false,trendAllowed=true;
        std::deque<Point> trend;
        qint64 trendBin=-1;
        Bin bin;
    };
    struct Fragment { quint32 first=0,size=0; QByteArray data; };
    struct Group {
        quint32 cycle=0,flags=0,rate=0,total=0,format=0,width=0;
        quint64 ticks=0;
        int bits=0,schema=0,count=0;
        qint64 receivedAt=0;
        QMap<int,Fragment> fragments;
        quint32 receivedPoints=0;
    };
    struct Channel {
        QVector<Group> groups;
        QVector<QPair<quint32,quint64>> completed;
        std::deque<Point> first,second,peaks;
        quint64 count=0,cycles=0,ticks=0,incomplete=0,malformed=0,duplicates=0;
        quint64 partialCycles=0,flaggedCycles=0;
        quint32 seenFlags=0;
        quint32 flags=0,cycle=0;
        quint32 rate=0,format=0,pointCount=0;
        quint32 latestCycle=0,latestFlags=0;
        quint64 latestTicks=0;
        qint64 last=-1;
        double gain=.5,scanHz=100,minimum=0,maximum=0,codeMin=0,codeMax=0;
        bool haveRange=false;
        bool haveWholeScan=false,displayPartial=false;
        QString issue;
    };
    QElapsedTimer timer;
    std::array<Sensor,6> sensors;
    std::array<Channel,2> adc,dlia;
    QByteArray calibration;
    quint64 origin=0;
    bool haveOrigin=false;
    quint16 filter=0,systemStatus=0;
    qint64 statusAt=-1,utcAt=-1,positionAt=-1;
    quint64 statusTicks=0;
    quint32 utcSec=0,utcMicro=0;
    quint64 decodeErrors=0;
    Impl() {
        timer.start();
        const char *names[]={"PTB210","EPSILON","BMP390","SHT45","TFA1500-L","AI8"};
        const int sources[]={0x40,0x42,0x43,0x44,0x45,0x46};
        for(int i=0;i<6;++i){sensors[i].name=QString::fromLatin1(names[i]);sensors[i].source=quint16(sources[i]);}
    }
    double seconds(quint64 ticks) {if(!haveOrigin){origin=ticks;haveOrigin=true;}return (double(ticks)-double(origin))/TickHz;}
    void field(Sensor &s,const QString &name,QJsonValue value,qint64 now) {s.fields[name]=value;s.fieldTime[name]=now;}
    void flushTrendBin(Sensor &s) {
        if(s.bin.used) {
            if(s.bin.min.x<=s.bin.max.x) {
                appendBounded(s.trend,s.bin.min);
                if(s.bin.min.x!=s.bin.max.x)appendBounded(s.trend,s.bin.max);
            } else {appendBounded(s.trend,s.bin.max);appendBounded(s.trend,s.bin.min);}
        }
        s.bin={};s.trendBin=-1;
    }
    void breakTrend(Sensor &s) {flushTrendBin(s);addGap(s.trend);}
    void sensorError(Sensor &s,const QString &issue) {s.issue=issue;s.measurementValid=false;++s.invalid;++decodeErrors;breakTrend(s);}
    void trend(Sensor &s,double x,double y,QString label,QString unit) {
        if(!s.trendAllowed || !std::isfinite(y))return;
        s.label=label;s.unit=unit;
        // 100 ms buckets, two extrema each: at most ~60 seconds / 1200 points.
        qint64 key=qint64(std::floor(x*10));Point p{x,y,false};
        if(!s.bin.used || key!=s.trendBin) {
            flushTrendBin(s);
            s.trendBin=key;s.bin={true,p,p};
        } else {if(y<s.bin.min.y)s.bin.min=p;if(y>s.bin.max.y)s.bin.max=p;}
    }
    void streams(const VlpFrame &f,bool raw);
    void sensor(const VlpFrame &f,Sensor &s);
    bool epsilon(const VlpFrame &f,Sensor &s,qint64 now);
    QJsonObject snapshot() const;
};

void DataDecoder::Impl::streams(const VlpFrame &f,bool raw) {
    const int ch=int(f.source-(raw?0x20:0x30));auto &c=raw?adc[ch]:dlia[ch];
    const qint64 now=timer.elapsed();const char *p=f.payload.constData();const int n=int(f.payload.size());
    auto fail=[&](const QString &why){++c.malformed;++decodeErrors;c.issue=why;};
    if(n<20){fail(QStringLiteral("数据头截断"));return;}
    Group g;g.schema=u16(p);g.bits=raw?u16(p+2):0;g.rate=u32(p+4);g.total=u32(p+8);
    g.cycle=f.cycle;g.ticks=f.ticks;g.flags=f.flags;g.receivedAt=now;
    int head=32,index=0;quint32 first=0,size=0,reserved=0;
    if(raw) {
        g.format=u32(p+12);g.width=4;
        if(g.schema==1){head=20;g.count=1;size=g.total;reserved=u32(p+16);}
        else if(g.schema==2 && n>=32){index=u16(p+16);g.count=u16(p+18);first=u32(p+20);size=u32(p+24);reserved=u32(p+28);}
        else {fail(QStringLiteral("不支持的 RAW schema"));return;}
        if(g.format>1 || g.bits<1 || g.bits>32){fail(QStringLiteral("RAW 位宽/格式无效"));return;}
    } else {
        if(g.schema!=2 || n<32){fail(QStringLiteral("不支持的 DLIA schema"));return;}
        g.format=u16(p+2);index=u16(p+12);g.count=u16(p+14);first=u32(p+16);size=u32(p+20);g.width=u32(p+24);reserved=u32(p+28);
        if(g.format>2 || g.width!=quint32((g.format+1)*8)){fail(QStringLiteral("DLIA 格式/点宽无效"));return;}
    }
    if(!g.rate || !g.total || !size || !g.count || index>=g.count || g.count>4096 ||
        g.total>1048576 || quint64(g.total)*g.width>4*1024*1024 || quint64(first)+size>g.total ||
        quint64(head)+quint64(size)*g.width!=quint64(n) || reserved || (f.flags&3)!=3) {
        fail(QStringLiteral("分片范围/长度/有效标志错误"));return;
    }
    if(c.completed.contains(qMakePair(g.cycle,g.ticks))){++c.duplicates;fail(QStringLiteral("重复已完成周期，忽略"));return;}
    // Retain four in-flight cycles per stream, each <=4 MiB. Old gaps cannot accumulate memory.
    for(int j=c.groups.size()-1;j>=0;--j)if(now-c.groups[j].receivedAt>StaleMs){c.groups.removeAt(j);++c.incomplete;c.issue=QStringLiteral("分片超时/缺片");}
    int found=-1;
    for(int j=0;j<c.groups.size();++j)if(c.groups[j].cycle==g.cycle && c.groups[j].ticks==g.ticks){found=j;break;}
    if(found<0){if(c.groups.size()==4){c.groups.removeFirst();++c.incomplete;c.issue=QStringLiteral("缺片，已丢弃未完成周期");}c.groups.push_back(g);found=c.groups.size()-1;}
    auto &a=c.groups[found];
    if(a.schema!=g.schema || a.bits!=g.bits || a.rate!=g.rate || a.total!=g.total || a.format!=g.format ||
       a.width!=g.width || a.count!=g.count || a.flags!=g.flags) {c.groups.removeAt(found);fail(QStringLiteral("同周期分片元数据/flags不一致"));return;}
    if(a.fragments.contains(index)){++c.duplicates;c.groups.removeAt(found);fail(QStringLiteral("重复分片，周期作废"));return;}
    for(auto it=a.fragments.cbegin();it!=a.fragments.cend();++it)if(first<it->first+it->size && it->first<first+size){c.groups.removeAt(found);fail(QStringLiteral("分片范围重叠"));return;}
    a.fragments.insert(index,{first,size,f.payload.mid(head)});a.receivedPoints+=size;
    if(a.fragments.size()!=a.count)return;
    quint32 cursor=0;
    for(const auto &part:a.fragments){if(part.first!=cursor){c.groups.removeAt(found);fail(QStringLiteral("片号顺序/样本范围存在缺口"));return;}cursor+=part.size;}
    if(cursor!=a.total){c.groups.removeAt(found);fail(QStringLiteral("样本未达到声明总数"));return;}
    // Do not replace a newer visible cycle when an older interleaved cycle completes late.
    const bool newest=c.last<0 || a.ticks>=c.latestTicks;
    QVector<double> v1,v2;v1.reserve(a.total);if(!raw)v2.reserve(a.total);
    double peak=0,localCodeMin=std::numeric_limits<double>::infinity(),localCodeMax=-std::numeric_limits<double>::infinity();
    double localMin=std::numeric_limits<double>::infinity(),localMax=-std::numeric_limits<double>::infinity();
    for(const auto &part:a.fragments)for(quint32 j=0;j<part.size;++j){
        const char *v=part.data.constData()+j*a.width;
        if(raw){
            const double value=a.format==0?double(i32(v)):double(u32(v));
            const double low=a.format==0?-std::ldexp(1.0,a.bits-1):0;
            const double high=std::ldexp(1.0,a.format==0?a.bits-1:a.bits)-1;
            if(value<low || value>high){c.groups.removeAt(found);fail(QStringLiteral("ADC 原码超出声明位宽"));return;}
            v1.push_back(value/std::ldexp(1.0,a.format==0?a.bits-1:a.bits)*5.0*(ch==0?1:-1));
            localCodeMin=std::min(localCodeMin,value);localCodeMax=std::max(localCodeMax,value);
            localMin=std::min(localMin,v1.back());localMax=std::max(localMax,v1.back());
        }else{
            double h1=0,h2=0;
            if(a.format==0){h1=i32(v);h2=i32(v+4);}
            else if(a.format==1){h1=std::min(2147483647.0,std::floor(std::hypot(double(i32(v)),double(i32(v+4)))));h2=std::min(2147483647.0,std::floor(std::hypot(double(i32(v+8)),double(i32(v+12)))));}
            else {h1=i32(v+16);h2=i32(v+20);}
            if(h1<0 || h2<0){c.groups.removeAt(found);fail(QStringLiteral("DLIA 幅值为负"));return;}
            v1.push_back(h1);v2.push_back(h2);peak=std::max(peak,h2);
        }
    }
    c.count+=a.total;++c.cycles;
    c.seenFlags|=a.flags;if(a.flags&32)++c.partialCycles;if(a.flags&0x38)++c.flaggedCycles;
    if(raw){
        if(!c.haveRange){c.codeMin=localCodeMin;c.codeMax=localCodeMax;c.minimum=localMin;c.maximum=localMax;c.haveRange=true;}
        else{c.codeMin=std::min(c.codeMin,localCodeMin);c.codeMax=std::max(c.codeMax,localCodeMax);c.minimum=std::min(c.minimum,localMin);c.maximum=std::max(c.maximum,localMax);}
    }
    c.completed.push_back(qMakePair(a.cycle,a.ticks));if(c.completed.size()>16)c.completed.removeFirst();
    if(newest){
        const bool wholeScan=!(a.flags&0x38) && std::abs(double(a.total)-double(a.rate)/c.scanHz)<=1;
        c.latestCycle=a.cycle;c.latestFlags=a.flags;c.latestTicks=a.ticks;
        if(!raw){
            if(c.last>=0 && (a.cycle!=c.cycle+1 || a.ticks<c.ticks || !wholeScan))addGap(c.peaks);
            if(wholeScan)appendBounded(c.peaks,{seconds(a.ticks),peak,false});
            else c.issue=QStringLiteral("短周期/部分或异常数据不生成完整扫描峰值");
        }
        if(wholeScan || !c.haveWholeScan){
            c.first=extrema(v1,a.rate,wholeScan?1200:600);if(!raw)c.second=extrema(v2,a.rate,wholeScan?1200:600);
            c.last=now;c.cycle=a.cycle;c.ticks=a.ticks;c.flags=a.flags;c.rate=a.rate;c.format=a.format;c.pointCount=a.total;c.displayPartial=!wholeScan;
            if(wholeScan)c.haveWholeScan=true;
        }else c.issue=QStringLiteral("最新周期为部分/短周期或异常，曲线保留最近完整扫描；计数和范围包含已重组数据");
    }
    c.groups.removeAt(found);
}

namespace {
struct Tlv {int type=0;QByteArray bytes;double number=0;};
bool parseTlv(const QByteArray &p,int schema,QMap<int,Tlv> &out) {
    if(p.size()<4 || u16(p.constData())!=schema)return false;
    int cursor=4;const int count=u16(p.constData()+2);
    for(int i=0;i<count;++i){
        if(cursor+4>p.size())return false;
        const char *h=p.constData()+cursor;int tag=u16(h),type=quint8(h[2]),len=quint8(h[3]);cursor+=4;
        if(cursor+len>p.size() || out.contains(tag))return false;
        Tlv v;v.type=type;v.bytes=p.mid(cursor,len);const char *b=v.bytes.constData();
        int expected=0;
        if(tag==1 || tag==2 || tag==4 || tag==0x11 || tag==0x13)expected=3;
        if(tag==0x10 || tag==0x12 || tag==0x14 || tag==0x15)expected=7;
        if(schema==2 && tag>=0x460 && tag<=0x467)expected=tag<=0x462?7:3;
        if(expected && (type!=expected || len!=4))return false;
        switch(type){
        case 1:case 13:if(len!=1)return false;v.number=quint8(b[0]);break;
        case 2:if(len!=2)return false;v.number=u16(b);break;
        case 3:if(len!=4)return false;v.number=u32(b);break;
        case 4:if(len!=8)return false;v.number=double(u64(b));break;
        case 5:if(len!=1)return false;v.number=qint8(b[0]);break;
        case 6:if(len!=2)return false;v.number=i16(b);break;
        case 7:if(len!=4)return false;v.number=i32(b);break;
        case 8:if(len!=8)return false;v.number=double(qFromLittleEndian<qint64>(b));break;
        case 9:if(len!=4)return false;v.number=f32(b);break;
        case 10:if(len!=8)return false;v.number=f64(b);break;
        default:break; // Unknown tag/type is safely skipped by its declared length.
        }
        if(!std::isfinite(v.number))return false;
        cursor+=len;int aligned=(cursor+3)&~3;if(aligned>p.size())return false;
        while(cursor<aligned)if(p[cursor++])return false;
        out.insert(tag,v);
    }
    return cursor==p.size();
}
std::pair<double,double> bmp(const QByteArray &c,quint32 p,quint32 t) {
    const char *b=c.constData();
    double t1=u16(b)*256.0,t2=std::ldexp(double(u16(b+2)),-30),t3=std::ldexp(double(qint8(b[4])),-48);
    double p1=std::ldexp(i16(b+5)-16384.0,-20),p2=std::ldexp(i16(b+7)-16384.0,-29);
    double p3=std::ldexp(double(qint8(b[9])),-32),p4=std::ldexp(double(qint8(b[10])),-37);
    double p5=u16(b+11)*8.0,p6=u16(b+13)/64.0,p7=qint8(b[15])/256.0,p8=qint8(b[16])/32768.0;
    double p9=std::ldexp(double(i16(b+17)),-48),p10=std::ldexp(double(qint8(b[19])),-48),p11=std::ldexp(double(qint8(b[20])),-65);
    double dt=t-t1,temperature=dt*t2+dt*dt*t3,tt=temperature*temperature,ttt=tt*temperature,pressure=p;
    return {p5+p6*temperature+p7*tt+p8*ttt+pressure*(p1+p2*temperature+p3*tt+p4*ttt)+pressure*pressure*(p9+p10*temperature)+pressure*pressure*pressure*p11,temperature};
}
}

void DataDecoder::Impl::sensor(const VlpFrame &f,Sensor &s) {
    const qint64 now=timer.elapsed();
    ++s.recordCount;
    s.trendAllowed=(f.flags&1) && !(f.flags&0x20);
    if(s.last>=0 && f.ticks<s.ticks){breakTrend(s);s.fields={};s.fieldTime.clear();if(s.source==0x43)calibration.clear();if(s.source==0x42)statusAt=-1;}
    // DEVICE_ERROR alone is a quality annotation, not proof that this sample is
    // absent: PTB sticky errors, SHT heater, and AI8 global alarms still carry data.
    // Flush the current bucket before every real discontinuity so no sample is lost.
    if(!s.trendAllowed || (s.last>=0 && (now-s.last>StaleMs || f.flags&0x28 ||
        ((s.flags&1) && f.ticks>=s.ticks && f.ticks-s.ticks>quint64(StaleMs)*100000))))breakTrend(s);
    if(f.source==0x42){if(!epsilon(f,s,now))return;}
    else {
        QMap<int,Tlv> v;if(!parseTlv(f.payload,f.source==0x46?2:1,v)){sensorError(s,QStringLiteral("TLV schema/类型/长度/padding错误"));return;}
        QList<int> required;
        if(f.source==0x40)required={0x12};
        else if(f.source==0x44)required={0x10,0x11,1};
        else if(f.source==0x45)required={0x13};
        else if(f.source==0x46)required={0x460,0x461,0x462,0x463,0x464,0x465,0x466,0x467,1,2,4};
        for(int tag:required)if(!v.contains(tag)){sensorError(s,QStringLiteral("传感器必需字段缺失"));return;}
        QStringList ai8Issues;
        if(f.source==0x46) {
            const quint32 status=quint32(v[1].number),host=quint32(v[0x466].number),alarm=quint32(v[0x464].number);
            const quint32 transport=(status>>1)&15,exception=(status>>5)&255;
            const bool communicationValid=(status&1) && transport==0 && exception==0;
            field(s,QStringLiteral("设备状态"),double(status),now);
            field(s,QStringLiteral("状态组合原码 (HOST/CONTROL/ALARM)"),v[2].number,now);
            field(s,QStringLiteral("通信状态"),communicationValid?QStringLiteral("正常（完整轮询）"):QStringLiteral("无效（保留历史测量）"),now);
            field(s,QStringLiteral("通信错误码"),double(transport),now);
            field(s,QStringLiteral("Modbus 异常码"),double(exception),now);
            if(communicationValid) {
                field(s,QStringLiteral("HOST 系统故障"),(host&0x100)?QStringLiteral("是"):QStringLiteral("否"),now);
                field(s,QStringLiteral("HOST 全局报警"),(host&0x200)?QStringLiteral("是"):QStringLiteral("否"),now);
            }
            if(!(status&1))ai8Issues<<QStringLiteral("AI8 离线");
            if(transport)ai8Issues<<QStringLiteral("AI8 通信错误 %1").arg(transport);
            if(exception)ai8Issues<<QStringLiteral("AI8 Modbus 异常 %1").arg(exception);
            if(host&0x100)ai8Issues<<QStringLiteral("AI8 系统故障（HOST bit8）");
            if(host&0x200)ai8Issues<<QStringLiteral("AI8 全局报警（HOST bit9）");
            if(alarm)ai8Issues<<QStringLiteral("AI8 通道报警（ALARM=0x%1）").arg(alarm,0,16);
            if(!communicationValid) {
                // RTL emits failed poll records with the previous complete PV/SP/SV.
                // Keep diagnostics, but do not turn these cached values into new samples.
                for(int tag:{0x463,0x464,0x465,0x466}) {
                    const QString key=tag==0x463?QStringLiteral("失败记录 OP 原码"):tag==0x464?QStringLiteral("失败记录 ALARM"):tag==0x465?QStringLiteral("失败记录 CONTROL"):QStringLiteral("失败记录 HOST");
                    field(s,key,v[tag].number,now);
                }
                s.issue=ai8Issues.join(QStringLiteral("；"))+QStringLiteral("；本条不更新温度或趋势");
                s.measurementValid=false;s.flags=f.flags;s.seenFlags|=f.flags;
                if(f.flags&0x38)++s.flaggedCount;
                ++s.invalidSamples;breakTrend(s);return;
            }
            for(const QString &key:{QStringLiteral("失败记录 OP 原码"),QStringLiteral("失败记录 ALARM"),QStringLiteral("失败记录 CONTROL"),QStringLiteral("失败记录 HOST")}) {
                s.fields.remove(key);s.fieldTime.remove(key);
            }
        }
        if(f.source==0x43){
            for(int tag:{0x100,0x101,0x102})if(v.contains(tag)){
                const auto &x=v[tag];if((tag==0x100 && (x.type!=11 || x.bytes.size()!=21)) ||
                    (tag!=0x100 && (x.type!=3 || x.bytes.size()!=4 || x.number>=16777216))){sensorError(s,QStringLiteral("BMP 标定/原码格式错误"));return;}
            }
            if(v.contains(0x100)){calibration=v[0x100].bytes;field(s,QStringLiteral("标定字节"),QString::fromLatin1(calibration.toHex()),now);}
            if(!v.contains(0x101) && !v.contains(0x102)){s.issue=QStringLiteral("仅收到标定元数据，等待测量");return;}
            if(v.contains(0x101))field(s,QStringLiteral("压力原码"),v[0x101].number,now);
            if(v.contains(0x102))field(s,QStringLiteral("温度原码"),v[0x102].number,now);
            if(calibration.size()==21 && v.contains(0x102)){
                auto result=bmp(calibration,quint32(v.value(0x101).number),quint32(v[0x102].number));
                field(s,QStringLiteral("温度 (℃)"),result.second,now);
                if(v.contains(0x101)){field(s,QStringLiteral("压力 (hPa)"),result.first/100,now);trend(s,seconds(f.ticks),result.first/100,QStringLiteral("压力"),QStringLiteral("hPa"));}
                s.issue.clear();
            }else{s.issue=QStringLiteral("缺少本会话标定或同条温度原码，补偿不可用");s.fields.remove(QStringLiteral("压力 (hPa)"));s.fields.remove(QStringLiteral("温度 (℃)"));}
        }else{
            s.issue.clear();
            struct Item{int tag;const char *name;double divisor;};
            const Item items[]={{1,"设备状态",1},{2,"设备错误",1},{4,"样本计数",1},{0x10,"温度 (℃)",1000},
                {0x11,"相对湿度 (%RH)",1000},{0x12,"压力 (hPa)",100000},{0x13,"距离 (mm)",1},
                {0x14,"目标温度 (℃)",1000000},{0x15,"实际温度 (℃)",1000000},
                {0x460,"PV 实际温度 (℃)",10},{0x461,"SP 目标温度 (℃)",10},{0x462,"SV 温度 (℃)",10},
                {0x463,"OP 原码",1},{0x464,"ALARM 报警",1},{0x465,"CONTROL",1},{0x466,"HOST 状态",1},{0x467,"设定结果原码",1}};
            for(const auto &it:items)if(v.contains(it.tag) && !(f.source==0x46 && it.tag==2))field(s,QString::fromUtf8(it.name),v[it.tag].number/it.divisor,now);
            if(f.source!=0x46 && v.contains(2) && v[2].number!=0)s.issue=QStringLiteral("设备错误位非零");
            if(f.source==0x46)s.issue=ai8Issues.join(QStringLiteral("；"));
            if(f.source==0x44 && v.value(1).number!=0)s.issue=QStringLiteral("SHT45 加热测量");
            int tag=f.source==0x40?0x12:f.source==0x44?0x10:f.source==0x45?0x13:0x460;
            if(v.contains(tag)){double divisor=tag==0x12?100000:tag==0x10?1000:tag==0x460?10:1;
                trend(s,seconds(f.ticks),v[tag].number/divisor,tag==0x12?QStringLiteral("压力"):tag==0x13?QStringLiteral("距离"):QStringLiteral("温度"),
                      tag==0x12?QStringLiteral("hPa"):tag==0x13?QStringLiteral("mm"):QStringLiteral("℃"));}
        }
    }
    ++s.count;s.measurementValid=true;s.last=now;s.flags=f.flags;s.ticks=f.ticks;s.seenFlags|=f.flags;if(f.flags&0x38)++s.flaggedCount;
}

bool DataDecoder::Impl::epsilon(const VlpFrame &f,Sensor &s,qint64 now) {
    const QByteArray &raw=f.payload;const auto n=raw.size();
    auto bad=[&](const QString &why){sensorError(s,why);return false;};
    if(n<8 || quint8(raw[0])!=0xfc || quint8(raw[n-1])!=0xfd || n!=quint8(raw[2])+8)return bad(QStringLiteral("FDILink 包络/长度错误"));
    quint8 c8=0;for(int i=0;i<4;++i){c8^=quint8(raw[i]);for(int j=0;j<8;++j)c8=(c8>>1)^((c8&1)?0x8c:0);}
    quint16 c16=0;for(int i=7;i<n-1;++i){c16^=quint16(quint8(raw[i]))<<8;for(int j=0;j<8;++j)c16=quint16((c16<<1)^((c16&0x8000)?0x1021:0));}
    if(c8!=quint8(raw[4]) || c16!=((quint16(quint8(raw[5]))<<8)|quint8(raw[6])))return bad(QStringLiteral("FDILink 内层 CRC 错误"));
    int id=quint8(raw[1]),len=quint8(raw[2]);const char *p=raw.constData()+7;
    const QMap<int,int> lengths={{0x40,56},{0x41,48},{0x42,72},{0x50,102},{0x51,8},{0x53,4},{0x59,74},{0x5a,9},{0x5c,32},{0x5d,24},{0x5f,12},{0x60,12}};
    if(lengths.contains(id) && lengths[id]!=len)return bad(QStringLiteral("FDILink 已知消息长度错误"));
    // Parse into a temporary map so malformed floating-point data cannot partially update a sample.
    QJsonObject fields;bool finite=true;
    auto num=[&](const QString &key,double value){if(!std::isfinite(value))finite=false;else fields[key]=value;};
    auto triple=[&](int offset,const QStringList &names,double scale=1){for(int i=0;i<3;++i)num(names[i],f32(p+offset+4*i)*scale);};
    auto attitude=[&](int offset){triple(offset,{QStringLiteral("横滚 (°)"),QStringLiteral("俯仰 (°)"),QStringLiteral("航向 (°)")},Degrees);};
    auto position=[&](int offset,const QString &prefix){double lat=f64(p+offset),lon=f64(p+offset+8);if(std::abs(lat)>3.14159265358979323846/2 || std::abs(lon)>3.14159265358979323846)finite=false;
        num(prefix+QStringLiteral("纬度 (°，原始)"),lat*Degrees);num(prefix+QStringLiteral("经度 (°，原始)"),lon*Degrees);num(prefix+QStringLiteral("高度 (m，基准待核)"),f64(p+offset+16));};
    auto velocity=[&](int offset,const QString &prefix){triple(offset,{prefix+QStringLiteral("北速度 (m/s)"),prefix+QStringLiteral("东速度 (m/s)"),prefix+QStringLiteral("下速度 (m/s)")});};
    if(id==0x41){attitude(12);triple(0,{QStringLiteral("横滚角速度 (rad/s)"),QStringLiteral("俯仰角速度 (rad/s)"),QStringLiteral("航向角速度 (rad/s)")});for(int i=0;i<4;++i)num(QStringLiteral("四元数 Q%1").arg(i+1),f32(p+24+4*i));fields[QStringLiteral("设备时间 (µs，非UTC)")]=QString::number(qFromLittleEndian<qint64>(p+40));}
    else if(id==0x40){triple(0,{QStringLiteral("IMU 角速度X (rad/s)"),QStringLiteral("IMU 角速度Y (rad/s)"),QStringLiteral("IMU 角速度Z (rad/s)")});triple(12,{QStringLiteral("IMU 加速度X (m/s²)"),QStringLiteral("IMU 加速度Y (m/s²)"),QStringLiteral("IMU 加速度Z (m/s²)")});num(QStringLiteral("IMU 温度 (℃)"),f32(p+36));num(QStringLiteral("IMU 压力 (Pa)"),f32(p+40));}
    else if(id==0x42){triple(0,{QStringLiteral("机体速度X (m/s)"),QStringLiteral("机体速度Y (m/s)"),QStringLiteral("机体速度Z (m/s)")});triple(12,{QStringLiteral("机体加速度X (m/s²)"),QStringLiteral("机体加速度Y (m/s²)"),QStringLiteral("机体加速度Z (m/s²)")});triple(24,{QStringLiteral("局部北位置 (m)"),QStringLiteral("局部东位置 (m)"),QStringLiteral("局部下位置 (m，非海拔)")});velocity(36,QStringLiteral("NED "));triple(48,{QStringLiteral("NED 北加速度 (m/s²)"),QStringLiteral("NED 东加速度 (m/s²)"),QStringLiteral("NED 下加速度 (m/s²)")});num(QStringLiteral("气压高度 (m)"),f32(p+60));fields[QStringLiteral("INS 设备时间 (µs，非UTC)")]=QString::number(qFromLittleEndian<qint64>(p+64));}
    else if(id==0x50){position(14,QStringLiteral("融合 "));velocity(38,QStringLiteral("融合 "));attitude(66);triple(90,{QStringLiteral("纬度标准差 (m)"),QStringLiteral("经度标准差 (m)"),QStringLiteral("高度标准差 (m)")});}
    else if(id==0x59){position(8,QStringLiteral("原始GNSS "));velocity(32,QStringLiteral("原始GNSS "));num(QStringLiteral("GNSS 航迹角 (°)"),f32(p+56));num(QStringLiteral("GNSS Geo_sep (m)"),f32(p+60));num(QStringLiteral("GNSS 差分龄期 (s)"),f32(p+64));quint16 status=u16(p+72);fields[QStringLiteral("原始GNSS 状态")]=status;fields[QStringLiteral("原始GNSS fix")]=status&15;fields[QStringLiteral("原始GNSS 速度有效")]=(status&16)?QStringLiteral("是"):QStringLiteral("否");fields[QStringLiteral("原始GNSS 时间有效")]=(status&32 && u32(p)>=946684800 && u32(p+4)<1000000)?QStringLiteral("是"):QStringLiteral("否");fields[QStringLiteral("原始GNSS 航向有效")]=(status&256)?QStringLiteral("是"):QStringLiteral("否");}
    else if(id==0x5a){num(QStringLiteral("HDOP"),f32(p));num(QStringLiteral("VDOP"),f32(p+4));fields[QStringLiteral("GNSS 卫星数")]=quint8(p[8]);}
    else if(id==0x5c){position(0,QStringLiteral("独立位置 "));num(QStringLiteral("水平精度 (m)"),f32(p+24));num(QStringLiteral("垂直精度 (m)"),f32(p+28));}
    else if(id==0x5d){num(QStringLiteral("ECEF X (m)"),f64(p));num(QStringLiteral("ECEF Y (m)"),f64(p+8));num(QStringLiteral("ECEF Z (m)"),f64(p+16));}
    else if(id==0x5f)velocity(0,QStringLiteral("独立NED "));
    else if(id==0x60)triple(0,{QStringLiteral("独立机体速度X (m/s)"),QStringLiteral("独立机体速度Y (m/s)"),QStringLiteral("独立机体速度Z (m/s)")});
    if(!finite)return bad(QStringLiteral("FDILink 含 NaN/Inf 或经纬度越界"));
    if(id==0x50 || id==0x53){systemStatus=u16(p);filter=u16(p+2);statusAt=now;statusTicks=f.ticks;
        fields[QStringLiteral("系统状态")]=systemStatus;fields[QStringLiteral("滤波状态")]=filter;
        fields[QStringLiteral("姿态初始化")]=(filter&1)?QStringLiteral("是"):QStringLiteral("否");fields[QStringLiteral("导航初始化")]=(filter&2)?QStringLiteral("是"):QStringLiteral("否");
        fields[QStringLiteral("航向初始化")]=(filter&4)?QStringLiteral("是"):QStringLiteral("否");fields[QStringLiteral("UTC 初始化")]=(filter&8)?QStringLiteral("是"):QStringLiteral("否");fields[QStringLiteral("GNSS fix")]=(filter>>4)&15;
        if(id==0x50)fields[QStringLiteral("滤波更新状态")]=u16(p+4);
    }
    if(id==0x50 || id==0x51){const int off=id==0x50?6:0;utcSec=u32(p+off);utcMicro=u32(p+off+4);utcAt=now;fields[QStringLiteral("UTC 秒原码")]=double(utcSec);fields[QStringLiteral("UTC 微秒原码")]=double(utcMicro);}
    if(id==0x50 || id==0x42 || id==0x5c || id==0x5d || id==0x5f || id==0x60)positionAt=now;
    for(auto it=fields.constBegin();it!=fields.constEnd();++it)field(s,it.key(),it.value(),now);
    field(s,QStringLiteral("最近内部消息"),QStringLiteral("0x%1").arg(id,2,16,QChar('0')),now);
    if(fields.contains(QStringLiteral("横滚 (°)")))trend(s,seconds(f.ticks),fields[QStringLiteral("横滚 (°)")].toDouble(),QStringLiteral("横滚"),QStringLiteral("°"));
    s.issue.clear();return true;
}

QJsonObject DataDecoder::Impl::snapshot() const {
    const qint64 now=timer.elapsed();QJsonArray sensorArray,adcArray,dliaArray;
    for(const auto &s:sensors){
        const bool stale=s.last<0 || now-s.last>StaleMs;
        QString quality=s.last<0?QStringLiteral("未收到有效数据"):stale?QStringLiteral("已过期（保留历史值）"):
            !s.measurementValid?QStringLiteral("测量未更新（保留历史值）"):flagQuality(s.flags);
        if(!s.issue.isEmpty())quality+=QStringLiteral("；")+s.issue;
        QJsonObject fields;
        for(auto it=s.fields.constBegin();it!=s.fields.constEnd();++it){const bool old=now-s.fieldTime.value(it.key(),-StaleMs-1)>StaleMs;
            const bool held=s.source==0x46 && !s.measurementValid &&
                (it.key().contains(QStringLiteral("温度")) || it.key()==QStringLiteral("OP 原码") || it.key().startsWith(QStringLiteral("HOST ")) ||
                 it.key()==QStringLiteral("ALARM 报警") || it.key()==QStringLiteral("CONTROL"));
            fields[it.key()+(old?QStringLiteral(" [历史/过期]"):held?QStringLiteral(" [历史/无效记录未更新]"):QString())]=it.value();}
        if(s.source==0x42){
            const bool statusFresh=statusAt>=0 && now-statusAt<=StaleMs && s.ticks>=statusTicks && s.ticks-statusTicks<=quint64(StaleMs)*100000;
            const bool nav=statusFresh && (filter&2) && !(systemStatus&0x003f) && positionAt>=0 && now-positionAt<=StaleMs;
            const bool utc=statusFresh && (filter&8) && utcAt>=0 && now-utcAt<=StaleMs && utcSec>=946684800 && utcMicro<1000000;
            fields[QStringLiteral("导航数据有效性")]=nav?QStringLiteral("已初始化；各字段仍须检查时效"):statusFresh?QStringLiteral("无效/未初始化"):QStringLiteral("状态未知/过期");
            fields[QStringLiteral("UTC 有效性")]=utc?QStringLiteral("有效"):QStringLiteral("未有效/状态过期");
            if(utc)fields[QStringLiteral("UTC")]=QDateTime::fromSecsSinceEpoch(utcSec,QTimeZone::UTC).toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))+QStringLiteral(".%1Z").arg(utcMicro,6,10,QChar('0'));
            quality+=!statusFresh?QStringLiteral("；导航状态未知/过期"):!(filter&8) || ((filter>>4)&15)<2?QStringLiteral("；GNSS/UTC未有效"):QString();
            if(statusFresh && systemStatus)quality+=QStringLiteral("；EPS 系统报警");
        }
        auto plot=s.trend;if(s.bin.used){if(s.bin.min.x<=s.bin.max.x){appendBounded(plot,s.bin.min);if(s.bin.max.x!=s.bin.min.x)appendBounded(plot,s.bin.max);}else{appendBounded(plot,s.bin.max);appendBounded(plot,s.bin.min);}}
        sensorArray.append(QJsonObject{{"name",s.name},{"source",s.source},{"fields",fields},{"quality",quality},{"flags",double(s.flags)},
            {"ticks",double(s.ticks)},{"count",double(s.count)},{"trend",pointsJson(plot)},{"trendLabel",s.label},{"trendUnit",s.unit},
            {"ageMs",s.last<0?QJsonValue():QJsonValue(double(now-s.last))},{"stale",stale},{"invalidRecords",double(s.invalid)},
            {"seenFlags",double(s.seenFlags)},{"flaggedCount",double(s.flaggedCount)},
            {"recordCount",double(s.recordCount)},{"invalidSamples",double(s.invalidSamples)},{"sampleValid",s.measurementValid && !stale}});
    }
    auto channelSnapshot=[&](const Channel &c,int channel,bool raw){
        bool stale=c.last<0 || now-c.last>StaleMs;QString quality=c.last<0?QStringLiteral("未收到完整周期"):stale?QStringLiteral("已过期（保留历史周期）"):flagQuality(c.flags,true);
        if(!c.issue.isEmpty())quality+=QStringLiteral("；历史：")+c.issue;
        if(c.displayPartial)quality+=QStringLiteral("；尚无完整扫描，显示部分周期散点");
        if(c.partialCycles)quality+=QStringLiteral("；累计部分周期 %1").arg(c.partialCycles);
        quint64 pending=0,expired=0;for(const auto &g:c.groups){++pending;if(now-g.receivedAt>StaleMs)++expired;}
        if(expired)quality+=QStringLiteral("；分片超时/缺片");
        QJsonObject o{{"channel",channel},{"count",double(c.count)},{"cycles",double(c.cycles)},{"cycle",double(c.cycle)},{"flags",double(c.flags)},
            {"quality",quality},{"ageMs",c.last<0?QJsonValue():QJsonValue(double(now-c.last))},{"stale",stale},{"pendingCycles",double(pending)},
            {"incompleteCycles",double(c.incomplete+expired)},{"malformedFrames",double(c.malformed)},{"duplicateFragments",double(c.duplicates)},{"ticks",double(c.ticks)},
            {"partialCycles",double(c.partialCycles)},{"flaggedCycles",double(c.flaggedCycles)},{"seenFlags",double(c.seenFlags)},
            {"displayFullCycle",c.last>=0 && !c.displayPartial},{"latestReceivedCycle",double(c.latestCycle)},{"latestReceivedFlags",double(c.latestFlags)},
            {"latestReceivedTicks",double(c.latestTicks)},{"rateHz",c.last>=0?QJsonValue(double(c.rate)):QJsonValue()},
            {"format",c.last>=0?QJsonValue(double(c.format)):QJsonValue()},{"pointsPerCycle",double(c.pointCount)}};
        if(raw){o["gain"]=c.gain;o["minV"]=c.haveRange?QJsonValue(c.minimum/c.gain):QJsonValue();o["maxV"]=c.haveRange?QJsonValue(c.maximum/c.gain):QJsonValue();
            o["codeMin"]=c.haveRange?QJsonValue(c.codeMin):QJsonValue();o["codeMax"]=c.haveRange?QJsonValue(c.codeMax):QJsonValue();o["points"]=pointsJson(c.first,1/c.gain,c.displayPartial);}
        else {o["h1"]=pointsJson(c.first,1,c.displayPartial);o["h2"]=pointsJson(c.second,1,c.displayPartial);o["peaks"]=pointsJson(c.peaks);}
        return o;
    };
    for(int ch=0;ch<2;++ch){adcArray.append(channelSnapshot(adc[ch],ch,true));dliaArray.append(channelSnapshot(dlia[ch],ch,false));}
    return {{"sensors",sensorArray},{"adc",adcArray},{"dlia",dliaArray},{"decodeErrors",double(decodeErrors)},{"freshnessTimeoutMs",double(StaleMs)}};
}
DataDecoder::DataDecoder():d(std::make_unique<Impl>()){}
DataDecoder::~DataDecoder()=default;
void DataDecoder::accept(const VlpFrame &f){
    if(f.kind!=0x10)return;
    if(f.message==0x1000 && (f.source==0x20 || f.source==0x21))d->streams(f,true);
    else if(f.message==0x1001 && (f.source==0x30 || f.source==0x31))d->streams(f,false);
    else for(auto &s:d->sensors)if(s.source==f.source && f.message==(f.source==0x42?0x1200:0x1100)){d->sensor(f,s);break;}
}
QJsonObject DataDecoder::snapshot()const{return d->snapshot();}
void DataDecoder::reset(){auto gains=std::array<double,2>{d->adc[0].gain,d->adc[1].gain};auto scans=std::array<double,2>{d->dlia[0].scanHz,d->dlia[1].scanHz};d=std::make_unique<Impl>();for(int i=0;i<2;++i){d->adc[i].gain=gains[i];d->adc[i].scanHz=d->dlia[i].scanHz=scans[i];}}
void DataDecoder::setAdcGain(int channel,double gain){if(channel>=0 && channel<2 && std::isfinite(gain) && gain>0)d->adc[channel].gain=gain;}
void DataDecoder::setScanHz(int channel,double hz){if(channel>=0 && channel<2 && std::isfinite(hz) && hz>0)d->adc[channel].scanHz=d->dlia[channel].scanHz=hz;}
