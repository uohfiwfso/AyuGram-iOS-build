import Foundation
import CoreFoundation
import TelegramCore

/// Имя Darwin-уведомления, которым твик AyuGramPushRelay сообщает AyuGram:
/// «в приложении с работающим push пришло уведомление».
///
/// Darwin notification выбрана потому, что единственный канал, который
/// работает между двумя sandbox'ами без общих App Group / Keychain entitlements.
let ayuGramPushSignalName = "com.ayugram.push.signal" as CFString

/// Callback для CFNotificationCenter: глобальная функция нужна для
/// конвертации в C function pointer, поэтому не может быть private.
func ayuGramDarwinSignalCallback(center: CFNotificationCenter?, observer: UnsafeMutableRawPointer?, name: CFNotificationName?, object: UnsafeRawPointer?, userInfo: CFDictionary?) {
    AyuGramPushSignal.shared.handleSignal()
}

/// Слушает сигнал от твика и будит сеть AyuGram, чтобы догнать обновления,
/// пришедшие по push-каналу другого приложения (Swiftgram / Telegram).
public final class AyuGramPushSignal {
    public static let shared = AyuGramPushSignal()

    private var observerToken: Unmanaged<CFNotificationObserver>?
    private var handler: (() -> Void)?

    public func setHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    public func start() {
        guard self.observerToken == nil else {
            return
        }
        self.observerToken = CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            ayuGramDarwinSignalCallback,
            ayuGramPushSignalName,
            nil,
            .deliverImmediately
        )
        Logger.shared.log("AyuGram", "push signal listener started")
    }

    fileprivate func handleSignal() {
        Logger.shared.log("AyuGram", "push signal received")
        self.handler?()
    }
}
