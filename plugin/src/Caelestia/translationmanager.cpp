#include "translationmanager.hpp"

#include <qcoreapplication.h>
#include <qdir.h>
#include <qlocale.h>
#include <qqmlengine.h>

namespace caelestia {

TranslationManager::TranslationManager(QObject* parent)
    : QObject(parent) {}

QString TranslationManager::language() const {
    return m_language;
}

bool TranslationManager::translationLoaded() const {
    return m_translationLoaded;
}

bool TranslationManager::setLanguage(const QString& language, const QUrl& translationDirectory) {
    QString resolved = language;
    if (resolved.isEmpty() || resolved == QStringLiteral("system"))
        resolved = QLocale::system().name();
    resolved.replace(u'-', u'_');

    QCoreApplication::removeTranslator(&m_translator);
    m_translationLoaded = false;

    const auto directory = translationDirectory.isLocalFile() ? translationDirectory.toLocalFile()
                                                               : translationDirectory.toString();
    const auto file = QDir(directory).filePath(QStringLiteral("qml_%1.qm").arg(resolved));
    if (m_translator.load(file)) {
        m_translationLoaded = QCoreApplication::installTranslator(&m_translator);
    } else {
        const auto baseLanguage = resolved.section(u'_', 0, 0);
        const auto fallback = QDir(directory).filePath(QStringLiteral("qml_%1.qm").arg(baseLanguage));
        if (m_translator.load(fallback))
            m_translationLoaded = QCoreApplication::installTranslator(&m_translator);
    }

    m_language = resolved;
    if (auto* engine = qmlEngine(this)) {
        engine->setUiLanguage(resolved);
        engine->retranslate();
    }
    emit languageChanged();
    return m_translationLoaded;
}

} // namespace caelestia
