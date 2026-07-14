#include "networkusage.hpp"

#include "../Internal/circularbuffer.hpp"

#include <chrono>
#include <cmath>
#include <qfile.h>

namespace {

constexpr qreal kKib = 1024.0;
constexpr qreal kMib = kKib * 1024.0;
constexpr qreal kGib = kMib * 1024.0;

qint64 monotonicMilliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

} // namespace

namespace caelestia::services {

NetworkUsage::NetworkUsage(QObject* parent)
    : TickingService(parent)
    , m_downloadBuffer(new internal::CircularBuffer(this))
    , m_uploadBuffer(new internal::CircularBuffer(this)) {
    m_downloadBuffer->setCapacity(kHistoryLength + 1);
    m_uploadBuffer->setCapacity(kHistoryLength + 1);
}

qreal NetworkUsage::downloadSpeed() const {
    return m_downloadSpeed;
}

qreal NetworkUsage::uploadSpeed() const {
    return m_uploadSpeed;
}

qreal NetworkUsage::downloadTotal() const {
    return m_downloadTotal;
}

qreal NetworkUsage::uploadTotal() const {
    return m_uploadTotal;
}

internal::CircularBuffer* NetworkUsage::downloadBuffer() const {
    return m_downloadBuffer;
}

internal::CircularBuffer* NetworkUsage::uploadBuffer() const {
    return m_uploadBuffer;
}

int NetworkUsage::historyLength() const {
    return kHistoryLength;
}

usagefmt::FormatResult NetworkUsage::formatBytes(qreal bytes) const {
    return format(bytes, true);
}

usagefmt::FormatResult NetworkUsage::formatBytesTotal(qreal bytes) const {
    return format(bytes, false);
}

void NetworkUsage::tick() {
    const auto counters = readCounters();
    if (!counters.valid) {
        return;
    }

    const qint64 now = monotonicMilliseconds();
    if (!m_initialized) {
        m_previousRx = counters.rx;
        m_previousTx = counters.tx;
        m_previousTimestamp = now;
        m_initialized = true;
        return;
    }

    const qreal seconds = static_cast<qreal>(now - m_previousTimestamp) / 1000.0;
    if (seconds <= 0.0) {
        return;
    }

    // Interfaces may disappear while the shell is running. Treat a decreasing
    // aggregate as a reset instead of reporting a near-2^64 traffic spike.
    const quint64 rxDelta = counters.rx >= m_previousRx ? counters.rx - m_previousRx : 0;
    const quint64 txDelta = counters.tx >= m_previousTx ? counters.tx - m_previousTx : 0;
    const qreal newDownloadSpeed = static_cast<qreal>(rxDelta) / seconds;
    const qreal newUploadSpeed = static_cast<qreal>(txDelta) / seconds;

    if (std::abs(newDownloadSpeed - m_downloadSpeed) > 0.01) {
        m_downloadSpeed = newDownloadSpeed;
        emit downloadSpeedChanged();
    }
    if (std::abs(newUploadSpeed - m_uploadSpeed) > 0.01) {
        m_uploadSpeed = newUploadSpeed;
        emit uploadSpeedChanged();
    }

    m_downloadBuffer->push(newDownloadSpeed);
    m_uploadBuffer->push(newUploadSpeed);

    if (rxDelta > 0) {
        m_downloadTotal += static_cast<qreal>(rxDelta);
        emit downloadTotalChanged();
    }
    if (txDelta > 0) {
        m_uploadTotal += static_cast<qreal>(txDelta);
        emit uploadTotalChanged();
    }

    m_previousRx = counters.rx;
    m_previousTx = counters.tx;
    m_previousTimestamp = now;
}

NetworkUsage::Counters NetworkUsage::readCounters() {
    QFile file(QStringLiteral("/proc/net/dev"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }

    // procfs files report a size of zero, so QFile::atEnd() is already true
    // before their first read. Read the virtual file in one operation instead.
    const QList<QByteArray> lines = file.readAll().split('\n');

    Counters counters;
    for (const QByteArray& rawLine : lines) {
        const QByteArray line = rawLine.simplified();
        const qsizetype colon = line.indexOf(':');
        if (colon < 0 || line.first(colon).trimmed() == "lo") {
            continue;
        }

        const QList<QByteArray> fields = line.sliced(colon + 1).simplified().split(' ');
        if (fields.size() < 9) {
            continue;
        }

        bool rxOk = false;
        bool txOk = false;
        const quint64 rx = fields.at(0).toULongLong(&rxOk);
        const quint64 tx = fields.at(8).toULongLong(&txOk);
        if (rxOk && txOk) {
            counters.rx += rx;
            counters.tx += tx;
            counters.valid = true;
        }
    }
    return counters;
}

usagefmt::FormatResult NetworkUsage::format(qreal bytes, bool perSecond) {
    if (!std::isfinite(bytes) || bytes < 0.0) {
        bytes = 0.0;
    }

    qreal divisor = 1.0;
    QString unit = QStringLiteral("B");
    if (bytes >= kGib) {
        divisor = kGib;
        unit = QStringLiteral("GB");
    } else if (bytes >= kMib) {
        divisor = kMib;
        unit = QStringLiteral("MB");
    } else if (bytes >= kKib) {
        divisor = kKib;
        unit = QStringLiteral("KB");
    }
    if (perSecond) {
        unit += QStringLiteral("/s");
    }
    return { bytes / divisor, bytes, unit };
}

} // namespace caelestia::services
