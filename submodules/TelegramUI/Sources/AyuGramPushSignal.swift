import Foundation
import CoreFoundation
import TelegramCore

/// Имя Darwin-уведомления, которым твик AyuGramPushRelay сообщает AyuGram:
/// «в приложении с работающим push пришло уведомление».
///
/// Darwin notification выбрана потому, что это единственный канал, который
/// работает между двумя sandbox'ами без общих App Group / Keychain entitlements.
///
/// Точная сигнатура взята из Swift-оверлея iOS SDK (CoreFoundation):
///   func CFNotificationCenterAddObserver(_ center: CFNotificationCenter!,
///                                        _ observer: UnsafeRawPointer!,
///                                        _ callBack: CFNotificationCallback!,
///                                        _ name: CFString!,
///                                        _ object: UnsafeRawPointer!,
///                                        _ suspensionBehavior: CFNotificationSuspensionBehavior)
let ayuGramPushSignalName = "com.ayugram.push.signal" as CFString

/// Callback-центра уведомлений должен быть `@convention(c)`, иначе C-центр его
/// не примет. Вынесен в отдельную константу (а не в замыкание прямо в вызове),
/// чтобы тип был виден явно и не требовалось контекста захвата.
private let ayuGramPushSignalCallback: CFNotificationCallback = { _, _, _, _, _ in
    AyuGramPushSignal.shared.handleSignal()
}

/// Слушает сигнал от твика и будит сеть AyuGram, чтобы догнать обновления,
/// пришедшие по push-каналу другого приложения (Swiftgram / Telegram).
public final class AyuGramPushSignal {
    public static let shared = AyuGramPushSignal()

    private var isObserving = false
    private var handler: (() -> Void)?

    public func setHandler(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    /// Регистрирует наблюдателя.
    ///
    /// Вызывать только после `Logger.setSharedLogger`: до инициализации
    /// `Logger.shared` уходит в `assertionFailure()` (TelegramCore Log.swift) и
    /// в debug-сборке роняет приложение на старте.
    public func start() {
        guard !self.isObserving else {
            return
        }
        self.isObserving = true

        // Результат вызова — Void в одних SDK и токен наблюдателя в других,
        // причём тип токена в Swift недоступен. withExtendedLifetime поглощает
        // результат в обоих случаях, не называя его тип и не давая warning
        // «result of call ... is unused» (TelegramUI собирается с
        // -warnings-as-errors, такой warning роняет всю сборку).
        withExtendedLifetime(CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            ayuGramPushSignalCallback,
            ayuGramPushSignalName,
            nil,
            .deliverImmediately
        )) {}

        Logger.shared.log("AyuGram", "push signal listener started")
    }

    fileprivate func handleSignal() {
        Logger.shared.log("AyuGram", "push signal received")
        self.handler?()
    }
}
