import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext

private enum AyuGramSettingsSection: Int32 {
    case saving
    case history
    case media
}

private final class AyuGramSettingsArguments {
    let updateSaveDeleted: (Bool) -> Void
    let updateSaveEdits: (Bool) -> Void
    let updateSaveMedia: (Bool) -> Void
    let updateSaveForBots: (Bool) -> Void
    let updateSaveMyDeleted: (Bool) -> Void
    let updateShowDeletedInChat: (Bool) -> Void
    let updateMaxMediaFileSize: (String) -> Void
    let updateMaxMediaStorage: (String) -> Void
    let openDeletedMessages: () -> Void
    let refresh: () -> Void

    init(
        updateSaveDeleted: @escaping (Bool) -> Void,
        updateSaveEdits: @escaping (Bool) -> Void,
        updateSaveMedia: @escaping (Bool) -> Void,
        updateSaveForBots: @escaping (Bool) -> Void,
        updateSaveMyDeleted: @escaping (Bool) -> Void,
        updateShowDeletedInChat: @escaping (Bool) -> Void,
        updateMaxMediaFileSize: @escaping (String) -> Void,
        updateMaxMediaStorage: @escaping (String) -> Void,
        openDeletedMessages: @escaping () -> Void,
        refresh: @escaping () -> Void
    ) {
        self.updateSaveDeleted = updateSaveDeleted
        self.updateSaveEdits = updateSaveEdits
        self.updateSaveMedia = updateSaveMedia
        self.updateSaveForBots = updateSaveForBots
        self.updateSaveMyDeleted = updateSaveMyDeleted
        self.updateShowDeletedInChat = updateShowDeletedInChat
        self.updateMaxMediaFileSize = updateMaxMediaFileSize
        self.updateMaxMediaStorage = updateMaxMediaStorage
        self.openDeletedMessages = openDeletedMessages
        self.refresh = refresh
    }
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case saveDeleted(Bool)
    case saveEdits(Bool)
    case saveMedia(Bool)
    case saveForBots(Bool)
    case saveMyDeleted(Bool)
    case showDeletedInChat(Bool)
    case deletedMessages(Int)
    case maxMediaFileSize(String)
    case maxMediaStorage(String)
    case mediaUsage(String)

    var section: ItemListSectionId {
        switch self {
        case .saveDeleted, .saveEdits, .saveMedia, .saveForBots, .saveMyDeleted, .showDeletedInChat:
            return AyuGramSettingsSection.saving.rawValue
        case .deletedMessages:
            return AyuGramSettingsSection.history.rawValue
        case .maxMediaFileSize, .maxMediaStorage:
            return AyuGramSettingsSection.media.rawValue
        case .mediaUsage:
            return AyuGramSettingsSection.media.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .saveDeleted:
            return 0
        case .saveEdits:
            return 1
        case .saveMedia:
            return 2
        case .saveForBots:
            return 3
        case .saveMyDeleted:
            return 4
        case .showDeletedInChat:
            return 5
        case .deletedMessages:
            return 6
        case .maxMediaFileSize:
            return 7
        case .maxMediaStorage:
            return 8
        case .mediaUsage:
            return 9
        }
    }

    static func < (lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGramSettingsArguments
        switch self {
        case let .saveDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save deleted messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveDeleted(value)
            })
        case let .saveEdits(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save edited messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveEdits(value)
            })
        case let .saveMedia(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save media", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveMedia(value)
            })
        case let .saveForBots(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save messages in bot chats", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveForBots(value)
            })
        case let .saveMyDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Save my deleted messages", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateSaveMyDeleted(value)
            })
        case let .showDeletedInChat(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Show deleted messages in chat", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.updateShowDeletedInChat(value)
            })
        case let .deletedMessages(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Deleted messages", label: "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
        case let .maxMediaFileSize(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Max attachment size, MB", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "0", type: .number, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateMaxMediaFileSize(updatedText)
            }, shouldUpdateText: { updatedText in
                updatedText.allSatisfy { $0.isNumber }
            }, action: {
                arguments.refresh()
            }, dismissKeyboardOnEnter: true)
        case let .maxMediaStorage(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Max saved media, MB", textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: "0", type: .number, sectionId: self.section, textUpdated: { updatedText in
                arguments.updateMaxMediaStorage(updatedText)
            }, shouldUpdateText: { updatedText in
                updatedText.allSatisfy { $0.isNumber }
            }, action: {
                arguments.refresh()
            }, dismissKeyboardOnEnter: true)
        case let .mediaUsage(value):
            return ItemListTextItem(presentationData: presentationData, text: .plain(value), sectionId: self.section)
        }
    }
}

/// AyuGram settings: the switches that decide what is kept, and the way into the kept messages.
public func ayuGramSettingsController(context: AccountContext) -> ViewController {
    let settings = AyuGramSettings.shared
    // The list has to be rebuilt when a switch changes, so the switches are not read once
    // and cached in the entries.
    let updateTrigger = Promise<Bool>(false)
    var pushImpl: ((ViewController) -> Void)?

    let arguments = AyuGramSettingsArguments(
        updateSaveDeleted: { value in
            settings.saveDeleted = value
            updateTrigger.set(.single(true))
        },
        updateSaveEdits: { value in
            settings.saveEdits = value
            updateTrigger.set(.single(true))
        },
        updateSaveMedia: { value in
            settings.saveMedia = value
            updateTrigger.set(.single(true))
        },
        updateSaveForBots: { value in
            settings.saveForBots = value
            updateTrigger.set(.single(true))
        },
        updateSaveMyDeleted: { value in
            settings.saveMyDeleted = value
            updateTrigger.set(.single(true))
        },
        updateShowDeletedInChat: { value in
            settings.showDeletedInChat = value
            updateTrigger.set(.single(true))
        },
        updateMaxMediaFileSize: { value in
            // The value is written while typing, but the list is only rebuilt when the user
            // confirms — rebuilding on every keystroke would tear the text field down.
            settings.maxMediaFileSizeMB = Int(value) ?? 0
        },
        updateMaxMediaStorage: { value in
            settings.maxMediaStorageMB = Int(value) ?? 0
            // A lowered budget has to take effect now, not at the next copy.
            MessageSavingBridge.enforceAttachmentBudget()
        },
        openDeletedMessages: {
            // The list of chats that have deleted messages; each chat opens its own list.
            pushImpl?(messageSavingDeletedChatsController(context: context))
        },
        refresh: {
            updateTrigger.set(.single(true))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updateTrigger.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        let updatedTheme = presentationData.theme.withModalBlocksBackground()
        presentationData = presentationData.withUpdated(theme: updatedTheme)

        let entries: [AyuGramSettingsEntry] = [
            .saveDeleted(settings.saveDeleted),
            .saveEdits(settings.saveEdits),
            .saveMedia(settings.saveMedia),
            .saveForBots(settings.saveForBots),
            .saveMyDeleted(settings.saveMyDeleted),
            .showDeletedInChat(settings.showDeletedInChat),
            .deletedMessages(MessageSavingStore.recordCount),
            .maxMediaFileSize("\(settings.maxMediaFileSizeMB)"),
            .maxMediaStorage("\(settings.maxMediaStorageMB)"),
            .mediaUsage("Saved media: \(MessageSavingBridge.savedAttachmentsSize / (1024 * 1024)) MB. 0 means no limit.")
        ]

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal

    pushImpl = { [weak controller] viewController in
        controller?.push(viewController)
    }

    return controller
}
