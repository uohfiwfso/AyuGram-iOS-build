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
}

private final class AyuGramSettingsArguments {
    let updateSaveDeleted: (Bool) -> Void
    let updateSaveEdits: (Bool) -> Void
    let updateSaveMedia: (Bool) -> Void
    let updateSaveForBots: (Bool) -> Void
    let updateSaveMyDeleted: (Bool) -> Void
    let openDeletedMessages: () -> Void

    init(
        updateSaveDeleted: @escaping (Bool) -> Void,
        updateSaveEdits: @escaping (Bool) -> Void,
        updateSaveMedia: @escaping (Bool) -> Void,
        updateSaveForBots: @escaping (Bool) -> Void,
        updateSaveMyDeleted: @escaping (Bool) -> Void,
        openDeletedMessages: @escaping () -> Void
    ) {
        self.updateSaveDeleted = updateSaveDeleted
        self.updateSaveEdits = updateSaveEdits
        self.updateSaveMedia = updateSaveMedia
        self.updateSaveForBots = updateSaveForBots
        self.updateSaveMyDeleted = updateSaveMyDeleted
        self.openDeletedMessages = openDeletedMessages
    }
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case saveDeleted(Bool)
    case saveEdits(Bool)
    case saveMedia(Bool)
    case saveForBots(Bool)
    case saveMyDeleted(Bool)
    case deletedMessages(Int)

    var section: ItemListSectionId {
        switch self {
        case .saveDeleted, .saveEdits, .saveMedia, .saveForBots, .saveMyDeleted:
            return AyuGramSettingsSection.saving.rawValue
        case .deletedMessages:
            return AyuGramSettingsSection.history.rawValue
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
        case .deletedMessages:
            return 5
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
        case let .deletedMessages(count):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Deleted messages", label: "\(count)", sectionId: self.section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
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
        openDeletedMessages: {
            // The list of chats that have deleted messages; each chat opens its own list.
            pushImpl?(messageSavingDeletedChatsController(context: context))
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
            .deletedMessages(MessageSavingStore.recordCount)
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
