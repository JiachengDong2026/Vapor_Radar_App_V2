#include "traceplot.h"
#include <QApplication>
#include <QWheelEvent>
#include <QMouseEvent>
#include <QTextStream>
#include <stdexcept>
#include <cmath>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    int checks = 0;
    auto check = [&](bool ok, const char *why) { ++checks; if (!ok) throw std::runtime_error(why); };
    auto near = [](double a, double b) { return std::abs(a-b) < 1e-6; };
    auto wheel = [&](TracePlot &p, int delta, QPointF point) {
        QWheelEvent e(point, p.mapToGlobal(point.toPoint()), QPoint(), QPoint(0,delta),
                      Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QApplication::sendEvent(&p, &e);
        return e.isAccepted();
    };
    try {
        TracePlot p, other;
        p.resize(500,300); other.resize(500,300);
        p.setSeries({QJsonArray{0, QJsonValue()}, QJsonArray{1, QJsonValue()}});
        check(!p.axesInitialized(), "Invalid samples initialized axes");
        p.setSeries({QJsonArray{0,49000}, QJsonArray{10,51000}});
        check(p.axesInitialized(), "First valid samples did not initialize");
        const double low=p.minimumY(), high=p.maximumY();
        check(low<49000 && high>51000, "Fit clipped data");
        other.setSeries({QJsonArray{0,0},QJsonArray{10,1000000}});
        const double otherHigh=other.maximumY();
        for (int i=0; i<100; ++i) p.setSeries({QJsonArray{0,10+i}, QJsonArray{20,2000000+i}});
        check(p.minimumY()==low && p.maximumY()==high, "Live refresh changed fixed Y");
        check(p.minimumX()==0 && p.maximumX()==10, "Live refresh changed fixed wave X");
        const QPointF anchor(p.plotRect().center().x(),p.plotRect().top()+p.plotRect().height()*.25);
        const double anchorValue=low+.75*(high-low);
        check(wheel(p,120,anchor), "Wheel not accepted");
        check(near(p.maximumY()-p.minimumY(),(high-low)*.8), "Wheel up did not zoom Y");
        check(near(p.minimumY()+.75*(p.maximumY()-p.minimumY()),anchorValue), "Pointer anchor moved");
        check(p.maximumX()==10, "Wheel changed X");
        check(other.maximumY()==otherHigh, "Wheel changed independent chart");
        const double zoomLow=p.minimumY(), zoomHigh=p.maximumY();
        p.setSeries({QJsonArray{0,50000},QJsonArray{10,50010}});
        check(p.minimumY()==zoomLow && p.maximumY()==zoomHigh, "Update reset manual zoom");
        check(!wheel(p,120,QPointF(2,2)), "Wheel outside plot was consumed");
        check(p.minimumY()==zoomLow, "Wheel outside plot changed Y");
        wheel(p,-120,anchor);
        check(near(p.minimumY(),low) && near(p.maximumY(),high), "Wheel inverse failed");
        QMouseEvent dbl(QEvent::MouseButtonDblClick,anchor,p.mapToGlobal(anchor.toPoint()),Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);
        QApplication::sendEvent(&p,&dbl);
        check(p.minimumY()<50000 && p.maximumY()>50010 && p.maximumY()-p.minimumY()<20, "Double click did not refit");
        const double fittedLow=p.minimumY(), fittedHigh=p.maximumY();
        QMouseEvent down(QEvent::MouseButtonPress,anchor,p.mapToGlobal(anchor.toPoint()),Qt::LeftButton,Qt::LeftButton,Qt::NoModifier);
        QApplication::sendEvent(&p,&down);
        QPointF dest=anchor+QPointF(0,30);
        QMouseEvent move(QEvent::MouseMove,dest,p.mapToGlobal(dest.toPoint()),Qt::NoButton,Qt::LeftButton,Qt::NoModifier);
        QApplication::sendEvent(&p,&move);
        check(p.minimumY()>fittedLow && near(p.maximumY()-p.minimumY(),fittedHigh-fittedLow),"Pan changed span or failed");
        QMouseEvent up(QEvent::MouseButtonRelease,dest,p.mapToGlobal(dest.toPoint()),Qt::LeftButton,Qt::NoButton,Qt::NoModifier);
        QApplication::sendEvent(&p,&up);
        for(int i=0;i<500;++i) wheel(p,120,anchor);
        check(std::isfinite(p.minimumY()) && p.maximumY()>p.minimumY(),"Repeated zoom collapsed range");
        for(int i=0;i<1000;++i) wheel(p,-120,anchor);
        check(std::isfinite(p.maximumY()) && p.maximumY()-p.minimumY()<=1e15,"Repeated zoom overflow");
        TracePlot history; history.resize(500,300); history.setHistoryWindow(10);
        history.setSeries({QJsonArray{10,1000000},QJsonArray{90,50000},QJsonArray{100,50100}});
        check(history.minimumX()==-10 && history.maximumX()==0, "History X not fixed relative window");
        check(history.maximumY()<51000, "Fit included hidden history");
        const double histLow=history.minimumY(), histHigh=history.maximumY();
        history.setSeries({QJsonArray{190,51000},QJsonArray{200,51200}});
        check(history.minimumX()==-10 && history.maximumX()==0 && history.minimumY()==histLow && history.maximumY()==histHigh, "History update changed axes");
        history.setSeries({});
        check(history.minimumY()==histLow && history.maximumY()==histHigh, "Empty snapshot reset axes");
        TracePlot flat; flat.resize(500,300); QJsonArray flatSeries; flatSeries.append(QJsonArray{0,0}); flat.setSeries(flatSeries);
        check(flat.minimumY()<0 && flat.maximumY()>0, "Zero flat line invalid range");
        flat.grab().save("plot_flat.png");
        p.setSeries({QJsonArray{0,50000},QJsonArray{5,QJsonValue()},QJsonArray{10,50100}}); p.fitAxes();
        p.grab().save("plot_gaps.png");
        QTextStream(stdout)<<"PLOT_TEST_PASS checks="<<checks<<"\n";
        return 0;
    } catch(const std::exception &e) { QTextStream(stderr)<<"PLOT_TEST_FAIL checks="<<checks<<" "<<e.what()<<"\n"; return 1; }
}
