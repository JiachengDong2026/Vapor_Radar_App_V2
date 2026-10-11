#include "traceplot.h"
#include <QPainter>
#include <QPainterPath>
#include <QWheelEvent>
#include <QMouseEvent>
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
bool pointValue(const QJsonValue &entry, double &x, double &y) {
    const auto xy = entry.toArray();
    if (xy.size() < 2 || !xy[0].isDouble() || !xy[1].isDouble()) return false;
    x = xy[0].toDouble(); y = xy[1].toDouble();
    return std::isfinite(x) && std::isfinite(y);
}
QString tick(double value, double span) {
    // More digits when zoomed into a small fluctuation on a large baseline.
    const int digits = std::clamp(int(std::ceil(std::log10(std::max(1., std::abs(value)) /
                                      std::max(1e-12, span / 4)))) + 2, 4, 12);
    return QString::number(value, 'g', digits);
}
}

TracePlot::TracePlot(QWidget *parent) : QWidget(parent) {
    setMinimumHeight(125);
    setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    setToolTip(QStringLiteral("坐标固定，不随数据自动缩放。\n滚轮向上放大纵轴，向下缩小（以鼠标位置为中心）。\n按住左键上下拖动平移纵轴；双击重新适配当前数据。"));
}
QRectF TracePlot::plotRect() const {
    return QRectF(78, 25, std::max(12, width() - 94), std::max(12, height() - 62));
}
void TracePlot::setSeries(const QJsonArray &a, const QJsonArray &b) {
    if (m_a == a && m_b == b) return;
    m_a = a; m_b = b;
    if (!m_initialized) fitAxes();
    update();
}
void TracePlot::setPrimaryColor(const QColor &color) { m_primaryColor = color; update(); }
void TracePlot::setLabels(const QString &x, const QString &y, const QString &legend) {
    if (m_x == x && m_y == y && m_legend == legend) return;
    m_x = x; m_y = y; m_legend = legend; update();
}
void TracePlot::setHistoryWindow(double seconds) {
    if (!std::isfinite(seconds) || seconds <= 0) return;
    m_historySeconds = seconds; m_minX = -seconds; m_maxX = 0;
    update();
}
double TracePlot::newestX() const {
    double last = -std::numeric_limits<double>::infinity();
    for (const auto *series : {&m_a, &m_b}) for (const auto &entry : *series) {
        double x, y;
        if (pointValue(entry, x, y)) last = std::max(last, x);
    }
    return std::isfinite(last) ? last : 0;
}
bool TracePlot::bounds(double &minX, double &maxX, double &minY, double &maxY) const {
    minX = minY = std::numeric_limits<double>::infinity();
    maxX = maxY = -minX;
    const double last = newestX();
    for (const auto *series : {&m_a, &m_b}) for (const auto &entry : *series) {
        double x, y;
        if (!pointValue(entry, x, y)) continue;
        if (m_historySeconds > 0 && x < last - m_historySeconds) continue;
        minX = std::min(minX, x); maxX = std::max(maxX, x);
        minY = std::min(minY, y); maxY = std::max(maxY, y);
    }
    return std::isfinite(minX);
}
bool TracePlot::setYRange(double low, double high) {
    const double span = high - low;
    const double minSpan = std::max(1e-9, std::max(std::abs(low), std::abs(high)) * 1e-12);
    if (!std::isfinite(low) || !std::isfinite(high) || !std::isfinite(span) ||
        span < minSpan || span > 1e15) return false;
    m_minY = low; m_maxY = high;
    update();
    return true;
}
void TracePlot::fitAxes() {
    double minX, maxX, minY, maxY;
    if (!bounds(minX, maxX, minY, maxY)) return;
    double padding = maxY == minY ? std::max(.001, std::abs(minY) * .05) : (maxY - minY) * .08;
    // The first history batch may contain only a few milliseconds of noise.
    // Give it headroom once; explicit double-click fitting stays tight.
    if (m_historySeconds > 0 && !m_initialized)
        padding = std::max(padding, std::max(std::abs(minY), std::abs(maxY)) * .01);
    if (!setYRange(minY - padding, maxY + padding)) return;
    m_minX = m_historySeconds > 0 ? -m_historySeconds : minX;
    m_maxX = m_historySeconds > 0 ? 0 : (maxX > minX ? maxX : minX + 1);
    m_initialized = true;
    m_dragging = false; unsetCursor();
    update();
}
void TracePlot::wheelEvent(QWheelEvent *event) {
    if (!m_initialized || !plotRect().contains(event->position())) { event->ignore(); return; }
    const double steps = event->angleDelta().y() != 0 ? event->angleDelta().y() / 120. : event->pixelDelta().y() / 40.;
    if (steps == 0) { event->ignore(); return; }
    const double ratio = std::clamp((plotRect().bottom() - event->position().y()) / plotRect().height(), 0., 1.);
    const double span = m_maxY - m_minY;
    const double anchor = m_minY + ratio * span;
    const double newSpan = span * std::pow(1.25, -std::clamp(steps, -20., 20.));
    setYRange(anchor - ratio * newSpan, anchor + (1 - ratio) * newSpan);
    event->accept();
}
void TracePlot::mouseDoubleClickEvent(QMouseEvent *event) {
    if (event->button() == Qt::LeftButton && plotRect().contains(event->position())) { fitAxes(); event->accept(); }
    else QWidget::mouseDoubleClickEvent(event);
}
void TracePlot::mousePressEvent(QMouseEvent *event) {
    if (m_initialized && event->button() == Qt::LeftButton && plotRect().contains(event->position())) {
        m_dragging = true; m_dragY = event->position().y(); m_dragMin = m_minY; m_dragMax = m_maxY;
        setCursor(Qt::ClosedHandCursor); event->accept();
    } else QWidget::mousePressEvent(event);
}
void TracePlot::mouseMoveEvent(QMouseEvent *event) {
    if (m_dragging) {
        const double offset = (event->position().y() - m_dragY) / plotRect().height() * (m_dragMax - m_dragMin);
        setYRange(m_dragMin + offset, m_dragMax + offset); event->accept();
    } else QWidget::mouseMoveEvent(event);
}
void TracePlot::mouseReleaseEvent(QMouseEvent *event) {
    if (m_dragging && event->button() == Qt::LeftButton) { m_dragging = false; unsetCursor(); event->accept(); }
    else QWidget::mouseReleaseEvent(event);
}

void TracePlot::paintEvent(QPaintEvent *) {
    QPainter p(this); p.setRenderHint(QPainter::Antialiasing); p.fillRect(rect(), Qt::white);
    const QRectF graph = plotRect();
    QFont f = font(); f.setPointSize(8); p.setFont(f);
    p.setPen(QColor("#677b89"));
    p.drawText(QRectF(5, 1, width() - 10, 20), Qt::AlignLeft, m_y);
    p.drawText(QRectF(5, 1, width() - 10, 20), Qt::AlignRight, m_legend);
    for (int i = 0; i <= 4; ++i) {
        const double y = graph.top() + graph.height() * i / 4;
        p.setPen(QColor("#e7edf1")); p.drawLine(QPointF(graph.left(), y), QPointF(graph.right(), y));
        p.setPen(QColor("#677b89"));
        p.drawText(QRectF(0, y - 8, 72, 16), Qt::AlignRight | Qt::AlignVCenter,
                   tick(m_maxY - (m_maxY - m_minY) * i / 4, m_maxY - m_minY));
    }
    p.setPen(QColor("#c8d4dc")); p.drawRect(graph);
    p.setPen(QColor("#677b89"));
    p.drawText(QRectF(graph.left() - 5, graph.bottom() + 3, 90, 16), Qt::AlignLeft, tick(m_minX, m_maxX-m_minX));
    p.drawText(QRectF(graph.right() - 90, graph.bottom() + 3, 90, 16), Qt::AlignRight, tick(m_maxX, m_maxX-m_minX));
    p.drawText(QRectF(graph.left(), height() - 18, graph.width(), 16), Qt::AlignCenter,
               m_historySeconds > 0 ? QStringLiteral("距最新数据 / s") : m_x);
    bool hasData = false, outside = false;
    const double origin = m_historySeconds > 0 ? newestX() : 0;
    auto draw = [&](const QJsonArray &points, QColor color) {
        QPainterPath path;
        bool active = false, hasGap = false;
        QVector<QPointF> singles;
        for (const auto &entry : points) {
            double x, y;
            if (!pointValue(entry, x, y)) { active = false; hasGap = true; continue; }
            x -= origin;
            if (x >= m_minX && x <= m_maxX) {
                hasData = true;
                outside |= y < m_minY || y > m_maxY;
            }
            const QPointF point(graph.left() + (x - m_minX) / (m_maxX - m_minX) * graph.width(),
                                graph.bottom() - (y - m_minY) / (m_maxY - m_minY) * graph.height());
            if (active) path.lineTo(point); else path.moveTo(point);
            active = true; singles.push_back(point);
        }
        p.save(); p.setClipRect(graph.adjusted(-1, -1, 1, 1));
        p.setPen(QPen(color, 1.7)); p.drawPath(path);
        if (singles.size() <= 40 || hasGap) { p.setBrush(color); for (const auto &point : singles) p.drawEllipse(point, 1.8, 1.8); }
        p.restore();
    };
    if (m_initialized) { draw(m_a, m_primaryColor); draw(m_b, QColor("#d77825")); }
    if (!hasData) {
        p.setPen(QColor("#8a9aa5")); p.drawText(graph, Qt::AlignCenter, QStringLiteral("等待有效数据"));
    } else if (outside) {
        const QRectF notice(graph.left() + 3, graph.top() + 3, graph.width() - 6, 20);
        p.fillRect(notice, QColor(255,255,255,220)); p.setPen(QColor("#a15f10"));
        p.drawText(notice, Qt::AlignCenter, QStringLiteral("超出纵轴 · 双击适配"));
    }
}
