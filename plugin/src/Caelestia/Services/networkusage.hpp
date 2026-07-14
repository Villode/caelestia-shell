#pragma once

#include "tickingservice.hpp"
#include "usagefmt.hpp"
#include "../Internal/circularbuffer.hpp"

#include <qqmlintegration.h>

namespace caelestia::services {

class NetworkUsage : public TickingService {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(qreal downloadSpeed READ downloadSpeed NOTIFY downloadSpeedChanged)
    Q_PROPERTY(qreal uploadSpeed READ uploadSpeed NOTIFY uploadSpeedChanged)
    Q_PROPERTY(qreal downloadTotal READ downloadTotal NOTIFY downloadTotalChanged)
    Q_PROPERTY(qreal uploadTotal READ uploadTotal NOTIFY uploadTotalChanged)
    Q_PROPERTY(caelestia::internal::CircularBuffer* downloadBuffer READ downloadBuffer CONSTANT)
    Q_PROPERTY(caelestia::internal::CircularBuffer* uploadBuffer READ uploadBuffer CONSTANT)
    Q_PROPERTY(int historyLength READ historyLength CONSTANT)

public:
    explicit NetworkUsage(QObject* parent = nullptr);

    [[nodiscard]] qreal downloadSpeed() const;
    [[nodiscard]] qreal uploadSpeed() const;
    [[nodiscard]] qreal downloadTotal() const;
    [[nodiscard]] qreal uploadTotal() const;
    [[nodiscard]] caelestia::internal::CircularBuffer* downloadBuffer() const;
    [[nodiscard]] caelestia::internal::CircularBuffer* uploadBuffer() const;
    [[nodiscard]] int historyLength() const;

    Q_INVOKABLE [[nodiscard]] usagefmt::FormatResult formatBytes(qreal bytes) const;
    Q_INVOKABLE [[nodiscard]] usagefmt::FormatResult formatBytesTotal(qreal bytes) const;

signals:
    void downloadSpeedChanged();
    void uploadSpeedChanged();
    void downloadTotalChanged();
    void uploadTotalChanged();

protected:
    void tick() override;

private:
    struct Counters {
        quint64 rx = 0;
        quint64 tx = 0;
        bool valid = false;
    };

    [[nodiscard]] static Counters readCounters();
    [[nodiscard]] static usagefmt::FormatResult format(qreal bytes, bool perSecond);

    static constexpr int kHistoryLength = 30;

    caelestia::internal::CircularBuffer* m_downloadBuffer;
    caelestia::internal::CircularBuffer* m_uploadBuffer;
    qreal m_downloadSpeed = 0.0;
    qreal m_uploadSpeed = 0.0;
    qreal m_downloadTotal = 0.0;
    qreal m_uploadTotal = 0.0;
    quint64 m_previousRx = 0;
    quint64 m_previousTx = 0;
    qint64 m_previousTimestamp = 0;
    bool m_initialized = false;
};

} // namespace caelestia::services
