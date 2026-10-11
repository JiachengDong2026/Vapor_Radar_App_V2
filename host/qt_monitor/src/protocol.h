#pragma once
#include <QByteArray>
#include <QJsonObject>
#include <QVector>
#include <memory>

struct VlpFrame {
    quint8 kind = 0;
    quint32 sequence = 0;
    quint16 source = 0, message = 0;
    quint32 flags = 0;
    quint64 ticks = 0;
    quint32 cycle = 0;
    QByteArray payload;
};

class VlpParser {
public:
    QVector<VlpFrame> feed(const QByteArray &bytes);
    // Call only after a real partial-frame timeout or end of recording, never on USB short reads.
    QVector<VlpFrame> expirePartial();
    void reset();
    QJsonObject statistics() const;
    static QByteArray command(quint32 sequence, bool write, quint32 address,
                              const QVector<quint32> &values, quint32 readCount = 1);
private:
    QByteArray buffer_;
    quint64 frames_ = 0, crcErrors_ = 0, framingErrors_ = 0, paddingErrors_ = 0, bytes_ = 0;
};

class DataDecoder {
public:
    DataDecoder();
    ~DataDecoder();
    DataDecoder(const DataDecoder &) = delete;
    DataDecoder &operator=(const DataDecoder &) = delete;
    void accept(const VlpFrame &frame);
    QJsonObject snapshot() const;
    void reset();
    void setAdcGain(int channel, double gain);
    void setScanHz(int channel, double hz);
private:
    struct Impl;
    std::unique_ptr<Impl> d;
};
