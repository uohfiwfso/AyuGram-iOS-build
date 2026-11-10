import Foundation
import Postbox
import SwiftSignalKit

/// AyuGram Android parity: copy attachments into a durable folder outside the Telegram cache
/// (`Download/AyuGram/Saved Attachments` on Android → Application Support here).
enum MessageSavingAttachments {
    /// `scheduleCopy`/`existingCopyPath` are documented to do only "path arithmetic plus a
    /// directory listing" on the caller's thread — which is sometimes a Postbox transaction
    /// thread (see `MessageSavingBridge.preserveMediaIfNeeded`). A `createDirectory` mkdir/stat
    /// syscall on every single access broke that invariant: a bulk delete of hundreds of
    /// messages meant hundreds of redundant mkdir calls under the database lock. Swift
    /// initializes a `static let` at most once (thread-safely), so this creates the directory a
    /// single time per process and every later access is a plain property read.
    private static let cachedDirectoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var root = base.appendingPathComponent("MessageSaving", isDirectory: true)
        let dir = root.appendingPathComponent("Saved Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Saved deleted messages and copies of secret/view-once media must not go into iCloud or
        // computer backups in plaintext; Telegram's own data root is excluded the same way.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        return dir
    }()

    static var directoryURL: URL {
        return cachedDirectoryURL
    }

    /// Largest attachment that may be saved, in bytes. 0 means "no limit".
    ///
    /// Read live from the settings, so lowering the limit takes effect on the next message
    /// instead of on the next launch.
    static var maxFileSize: Int64 {
        return MessageSavingBridge.settings.with { $0.maxMediaFileSize }
    }

    /// Total size the saved attachments may occupy, in bytes. 0 means "no limit".
    static var maxTotalSize: Int64 {
        return MessageSavingBridge.settings.with { $0.maxMediaStorage }
    }

    /// Size of a file on disk, in bytes. 0 when it cannot be determined.
    private static func fileSize(atPath path: String) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return 0
        }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Total size of the saved attachments, in bytes.
    static func totalSize() -> Int64 {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Drop the oldest saved attachments until the folder fits into the configured budget.
    ///
    /// The records in the store stay — only the file copies go, so "View Deleted" still lists the
    /// message, just without its attachment. The file that was just written is never dropped.
    static func enforceStorageBudget(keeping protectedPath: String?) {
        let budget = maxTotalSize
        guard budget > 0 else { return }
        ioQueue.async {
            let fileManager = FileManager.default
            guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                return
            }
            var entries: [(url: URL, size: Int64, date: Date)] = []
            var total: Int64 = 0
            for url in urls {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                entries.append((url, size, values?.contentModificationDate ?? .distantPast))
                total += size
            }
            guard total > budget else { return }
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                if total <= budget {
                    break
                }
                if let protectedPath, entry.url.path == protectedPath {
                    continue
                }
                try? fileManager.removeItem(at: entry.url)
                total -= entry.size
            }
            MessageSavingBridge.log("attachments: trimmed the saved attachments folder to \(total / (1024 * 1024)) MB")
        }
    }

    /// Stable across launches, unlike String.hashValue which is per-process seeded.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Each account has its own MediaBox directory, so this scopes filenames per account
    /// without having to thread accountPeerId through every delete path.
    private static func accountScope(mediaBox: MediaBox) -> String {
        return String(stableHash(mediaBox.basePath), radix: 36)
    }

    private static func baseName(peerId: Int64, namespace: Int32, messageId: Int32, mediaBox: MediaBox) -> String {
        return "\(accountScope(mediaBox: mediaBox))_\(peerId)_\(namespace)_\(messageId)"
    }

    /// Pre-account-scoping name. Still read so previously saved files keep working.
    private static func legacyBaseName(peerId: Int64, namespace: Int32, messageId: Int32) -> String {
        return "\(peerId)_\(namespace)_\(messageId)"
    }

    private static let knownExtensions: [String] = [
        "jpg", "jpeg", "png", "webp", "heic", "gif", "mp4", "mov", "m4v", "webm",
        "mp3", "m4a", "ogg", "opus", "pdf", "bin", "tgs", "tgv", "mkv", "avi",
        "doc", "docx", "xls", "xlsx", "zip", "rar", "7z", "txt"
    ]

    private static func firstFile(withBase base: String, in directory: URL) -> String? {
        // Probe known extensions with fileExists — O(1) per probe. Avoid listing the whole
        // Saved Attachments directory on every delete/TTL (that becomes O(n) filesystem work
        // inside Postbox transactions once the folder grows).
        for ext in knownExtensions {
            let path = directory.appendingPathComponent("\(base).\(ext)").path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// A durable copy already on disk for this message, whatever extension it was saved with.
    /// Id-based so it also works after a restart, when only a stored record (not a Message) is
    /// at hand.
    static func existingCopyPath(peerId: Int64, namespace: Int32, messageId: Int32, mediaBox: MediaBox) -> String? {
        let directory = self.directoryURL
        if let path = firstFile(withBase: baseName(peerId: peerId, namespace: namespace, messageId: messageId, mediaBox: mediaBox), in: directory) {
            return path
        }
        return firstFile(withBase: legacyBaseName(peerId: peerId, namespace: namespace, messageId: messageId), in: directory)
    }

    static func existingCopyPath(message: Message, mediaBox: MediaBox) -> String? {
        return existingCopyPath(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id, mediaBox: mediaBox)
    }

    static let ioQueue = DispatchQueue(label: "MessageSaving.IO", qos: .utility)

    /// Same as `copyIfAvailable`, but the byte copy runs off the caller's thread and the
    /// destination path is returned immediately. Use this from inside a Postbox transaction:
    /// copying a large video synchronously there holds the database lock for the whole of the
    /// file I/O, which stalls every other transaction behind it.
    /// Resolving the source and destination is only path arithmetic plus a directory listing,
    /// so it stays on the caller's thread and the returned path is still deterministic.
    static func scheduleCopy(message: Message, mediaBox: MediaBox) -> String? {
        if let existing = existingCopyPath(message: message, mediaBox: mediaBox) {
            return existing
        }
        guard let source = sourcePath(message: message, mediaBox: mediaBox) else {
            return nil
        }
        let dest = destinationURL(message: message, source: source, mediaBox: mediaBox)
        ioQueue.async {
            if FileManager.default.fileExists(atPath: dest.path) {
                return
            }
            try? FileManager.default.copyItem(atPath: source, toPath: dest.path)
            enforceStorageBudget(keeping: dest.path)
        }
        return dest.path
    }

    private static func destinationURL(message: Message, source: String, mediaBox: MediaBox) -> URL {
        let ext: String
        let sourceExtension = (source as NSString).pathExtension
        if !sourceExtension.isEmpty {
            ext = sourceExtension
        } else {
            ext = "bin"
        }
        let base = baseName(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, messageId: message.id.id, mediaBox: mediaBox)
        return directoryURL.appendingPathComponent("\(base).\(ext)")
    }

    /// Copy the best available local media file for `message`. Returns the destination path, or nil.
    static func copyIfAvailable(message: Message, mediaBox: MediaBox) -> String? {
        // Check the durable copy BEFORE asking MediaBox for a source: once the Telegram cache is
        // cleared, completedResourcePath returns nil even though our own saved file is still
        // there, which used to make an already-saved attachment look missing.
        if let existing = existingCopyPath(message: message, mediaBox: mediaBox) {
            return existing
        }
        guard let source = sourcePath(message: message, mediaBox: mediaBox) else {
            return nil
        }
        let dest = destinationURL(message: message, source: source, mediaBox: mediaBox)
        do {
            try FileManager.default.copyItem(atPath: source, toPath: dest.path)
            enforceStorageBudget(keeping: dest.path)
            return dest.path
        } catch {
            // Lost a race with a concurrent copy of the same message — that is still success.
            if FileManager.default.fileExists(atPath: dest.path) {
                return dest.path
            }
            return nil
        }
    }

    private static func sourcePath(message: Message, mediaBox: MediaBox) -> String? {
        // A file bigger than the configured limit is not worth keeping: it would eat the whole
        // storage budget on its own. 0 disables the limit.
        let limit = maxFileSize
        for media in message.effectiveMedia {
            if let image = media as? TelegramMediaImage {
                let reps = image.representations.sorted { ($0.dimensions.width * $0.dimensions.height) > ($1.dimensions.width * $1.dimensions.height) }
                for rep in reps {
                    if let path = mediaBox.completedResourcePath(rep.resource) {
                        if limit <= 0 || fileSize(atPath: path) <= limit {
                            return path
                        }
                    }
                }
            } else if let file = media as? TelegramMediaFile {
                if let path = mediaBox.completedResourcePath(file.resource, pathExtension: file.fileName.flatMap { ($0 as NSString).pathExtension }) {
                    if limit <= 0 || fileSize(atPath: path) <= limit {
                        return path
                    }
                }
                if let path = mediaBox.completedResourcePath(file.resource) {
                    if limit <= 0 || fileSize(atPath: path) <= limit {
                        return path
                    }
                }
                for rep in file.previewRepresentations {
                    if let path = mediaBox.completedResourcePath(rep.resource) {
                        if limit <= 0 || fileSize(atPath: path) <= limit {
                            return path
                        }
                    }
                }
            }
        }
        return nil
    }

    /// The single most-relevant (media, resource) pair for a proactive download — the same one
    /// `sourcePath` looks for locally (largest photo representation, or the file's main resource).
    private static func fetchableResource(message: Message) -> (media: Media, resource: TelegramMediaResource, contentType: MediaResourceUserContentType)? {
        for media in message.effectiveMedia {
            if let image = media as? TelegramMediaImage {
                let reps = image.representations.sorted { ($0.dimensions.width * $0.dimensions.height) > ($1.dimensions.width * $1.dimensions.height) }
                if let best = reps.first {
                    return (image, best.resource, .image)
                }
            } else if let file = media as? TelegramMediaFile {
                return (file, file.resource, MediaResourceUserContentType(file: file))
            }
        }
        return nil
    }

    /// Ceiling on what a proactive preserve will pull down on its own.
    ///
    /// This fetch is speculative: it downloads media the user has not opened, on whatever
    /// network happens to be up, to keep a copy in case the message is deleted. Unbounded,
    /// that is how a client ends up having pulled gigabytes of video over cellular for
    /// messages nobody looked at. Above the ceiling the preserve still happens — it just
    /// waits for the file to arrive some other way (the user opening it, auto-download)
    /// instead of paying for it up front.
    ///
    /// The ceiling is the user's "max attachment size" setting; 0 means no limit.
    static var proactiveFetchSizeLimit: Int64 {
        return maxFileSize
    }

    /// AyuGram Android parity: actively pull a not-yet-local resource instead of only waiting
    /// for whatever else happens to be downloading it. Fire-and-forget: the returned disposable
    /// is only so a caller can tear the fetch down once the preserve either succeeds or gives up
    /// — cancelling it early is harmless, the file simply never finishes downloading.
    static func startFetch(message: Message, mediaBox: MediaBox) -> Disposable? {
        guard existingCopyPath(message: message, mediaBox: mediaBox) == nil else {
            return nil
        }
        guard let (media, resource, contentType) = fetchableResource(message: message) else {
            return nil
        }
        if let size = resource.size, size > proactiveFetchSizeLimit {
            MessageSavingBridge.log("preserve: skipped proactive fetch for \(message.id.id) (\(size / (1024 * 1024)) MB over the \(proactiveFetchSizeLimit / (1024 * 1024)) MB ceiling)")
            return nil
        }
        guard mediaBox.completedResourcePath(resource) == nil else {
            // Already fully cached — copyIfAvailable will pick it up on the next retry.
            return nil
        }
        let reference = AnyMediaReference.message(message: MessageReference(message), media: media).resourceReference(resource)
        return fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(message.id.peerId), userContentType: contentType, reference: reference).start()
    }
}
