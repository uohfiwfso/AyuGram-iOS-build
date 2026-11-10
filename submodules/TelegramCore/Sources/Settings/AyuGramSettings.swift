import Foundation

/// AyuGram feature switches.
///
/// These live in the app's own `UserDefaults` so that the core (which intercepts messages)
/// and the settings UI always read the same values — there is no second copy to fall out of
/// sync, and the switches take effect on the next message instead of on the next launch.
public final class AyuGramSettings {
    public static let shared = AyuGramSettings()

    private enum Key {
        static let saveDeleted = "ayugram.saveDeleted"
        static let saveEdits = "ayugram.saveEdits"
        static let saveForBots = "ayugram.saveForBots"
        static let saveMedia = "ayugram.saveMedia"
        static let proactiveSaveMedia = "ayugram.proactiveSaveMedia"
        static let saveMyDeleted = "ayugram.saveMyDeleted"
        static let deletedMark = "ayugram.deletedMark"
        static let editedMark = "ayugram.editedMark"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let value = defaults.object(forKey: key) as? Bool else {
            return defaultValue
        }
        return value
    }

    private func string(_ key: String, default defaultValue: String) -> String {
        guard let value = defaults.string(forKey: key) else {
            return defaultValue
        }
        return value
    }

    /// Keep a copy of messages that are deleted on the server (anti-recall).
    public var saveDeleted: Bool {
        get { self.bool(Key.saveDeleted, default: false) }
        set { self.defaults.set(newValue, forKey: Key.saveDeleted) }
    }

    /// Keep a copy of the previous text of edited messages.
    public var saveEdits: Bool {
        get { self.bool(Key.saveEdits, default: false) }
        set { self.defaults.set(newValue, forKey: Key.saveEdits) }
    }

    /// Bots edit and delete their messages constantly — keep them out of the store by default.
    public var saveForBots: Bool {
        get { self.bool(Key.saveForBots, default: false) }
        set { self.defaults.set(newValue, forKey: Key.saveForBots) }
    }

    /// Copy the attachments of saved messages into the app's own storage.
    public var saveMedia: Bool {
        get { self.bool(Key.saveMedia, default: false) }
        set { self.defaults.set(newValue, forKey: Key.saveMedia) }
    }

    /// Download the attachments of a message before the server expires them.
    public var proactiveSaveMedia: Bool {
        get { self.bool(Key.proactiveSaveMedia, default: false) }
        set { self.defaults.set(newValue, forKey: Key.proactiveSaveMedia) }
    }

    /// Keep the messages you deleted yourself as well.
    public var saveMyDeleted: Bool {
        get { self.bool(Key.saveMyDeleted, default: false) }
        set { self.defaults.set(newValue, forKey: Key.saveMyDeleted) }
    }

    /// The mark shown in front of a message that was deleted.
    public var deletedMark: String {
        get { self.string(Key.deletedMark, default: MessageSavingBridge.defaultDeletedMark) }
        set { self.defaults.set(newValue, forKey: Key.deletedMark) }
    }

    /// The mark shown in front of a message that was edited.
    public var editedMark: String {
        get { self.string(Key.editedMark, default: "") }
        set { self.defaults.set(newValue, forKey: Key.editedMark) }
    }

    /// The settings the message interceptor works with.
    public var messageSavingSettings: MessageSavingBridgeSettings {
        return MessageSavingBridgeSettings(
            saveDeleted: self.saveDeleted,
            saveEdits: self.saveEdits,
            saveForBots: self.saveForBots,
            saveMedia: self.saveMedia,
            proactiveSaveMedia: self.proactiveSaveMedia,
            deletedMark: self.deletedMark,
            editedMark: self.editedMark,
            saveMyDeleted: self.saveMyDeleted
        )
    }
}
