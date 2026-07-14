#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qtranslator.h>
#include <qurl.h>

namespace caelestia {

class TranslationManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString language READ language NOTIFY languageChanged)
    Q_PROPERTY(bool translationLoaded READ translationLoaded NOTIFY languageChanged)

public:
    explicit TranslationManager(QObject* parent = nullptr);

    [[nodiscard]] QString language() const;
    [[nodiscard]] bool translationLoaded() const;

    Q_INVOKABLE bool setLanguage(const QString& language, const QUrl& translationDirectory);

signals:
    void languageChanged();

private:
    QTranslator m_translator;
    QString m_language;
    bool m_translationLoaded = false;
};

} // namespace caelestia
