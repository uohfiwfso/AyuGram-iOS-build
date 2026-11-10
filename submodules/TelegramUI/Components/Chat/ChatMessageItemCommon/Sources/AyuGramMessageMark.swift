import Foundation
import TelegramCore

/// AyuGram: the mark that goes in front of the time in the message footer.
///
/// The broom marks a message that was deleted but kept in the chat, the pencil marks an edited
/// one — the way AyuGram Android draws them. Both marks are configurable in the AyuGram
/// settings; an empty mark means "show nothing".
///
/// The function lives in `ChatMessageItemCommon` because every message content node builds its
/// own footer and all of them need the same answer.
public func ayuGramMessageMark(for message: EngineRawMessage) -> String? {
    if MessageSavingBridge.isDeletedPlaceholder(message: message) {
        return MessageSavingBridge.deletedMark
    }
    let attributes = message.attributes
    for attribute in attributes {
        if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
            let mark = MessageSavingBridge.editedMark
            return mark.isEmpty ? nil : mark
        }
    }
    return nil
}
