import Foundation
import Postbox

/// Marks a message that was deleted but kept in the chat as an AyuGram-style placeholder.
///
/// The message itself stays in Postbox — same id, same position in the chat, same author, same
/// attachments. Only the presentation changes: the UI draws such a message faded and puts the
/// "deleted" mark next to the timestamp, the way AyuGram Android does.
///
/// The attribute is the marker itself: it travels with the message through the database, so the
/// UI can tell a placeholder from an ordinary message without guessing from the text.
public class AyuGramDeletedMessageAttribute: MessageAttribute {
    public init() {}

    required public init(decoder: PostboxDecoder) {}

    public func encode(_ encoder: PostboxEncoder) {}
}
