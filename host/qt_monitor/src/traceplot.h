#pragma once

#include <QWidget>
#include <QJsonArray>
#include <QColor>

class TracePlot : public QWidget {
public:
    explicit TracePlot(QWidget *parent = nullptr);
    void setSeries(const QJsonArray &a, const QJsonArray &b = QJsonArray());
    void setPrimaryColor(const QColor &color);
    void setLabels(const QString &x, const QString &y, const QString &legend = QString());
    void setHistoryWindow(double seconds);
    void fitAxes();
    QRectF plotRect() const;
    double minimumY() const { return m_minY; }
    double maximumY() const { return m_maxY; }
    double minimumX() const { return m_minX; }
    double maximumX() const { return m_maxX; }
    bool axesInitialized() const { return m_initialized; }
protected:
    void paintEvent(QPaintEvent *) override;
    void wheelEvent(QWheelEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
private:
    bool bounds(double &minX, double &maxX, double &minY, double &maxY) const;
    double newestX() const;
    bool setYRange(double low, double high);
    QJsonArray m_a, m_b;
    QColor m_primaryColor = QColor("#087f8c");
    QString m_x = QStringLiteral("时间 / s"), m_y, m_legend;
    double m_minX = 0, m_maxX = 1, m_minY = 0, m_maxY = 1;
    double m_historySeconds = 0;
    bool m_initialized = false, m_dragging = false;
    double m_dragY = 0, m_dragMin = 0, m_dragMax = 1;
};
