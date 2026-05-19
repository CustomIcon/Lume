import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable
final class DownloadManager: NSObject {
    private var modelContext: ModelContext?
    private var sessionAndDelegate: (URLSession, DownloadDelegate)?
    
    private(set) var activeDownloads: [String: DownloadProgress] = [:]
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    
    struct DownloadProgress: Identifiable {
        let id: String
        let name: String
        var progress: Double
        var isPaused: Bool = false
        var isCompleted: Bool = false
        var error: Error? = nil
    }

    override init() {
        super.init()
    }
    
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let delegate = DownloadDelegate(manager: self)
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
        self.sessionAndDelegate = (session, delegate)
        
        try? FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
    }
    
    var downloadsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }
    
    func download(_ item: BaseItemDto, from apiClient: JellyfinAPIClient) async {
        guard let itemId = item.id else { return }
        if isDownloaded(itemId) { return }
        
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        let existingItem = try? modelContext?.fetch(descriptor).first
        
        if existingItem == nil {
            let serverId = await apiClient.getBaseURL()
            let downloadedItem = DownloadedItem(
                itemId: itemId,
                serverId: serverId,
                name: item.displayName,
                type: item.type ?? "Unknown",
                collectionType: item.collectionType
            )
            downloadedItem.seriesName = item.seriesName
            downloadedItem.albumName = item.album
            downloadedItem.artistName = item.artists?.joined(separator: ", ")
            downloadedItem.seriesId = item.seriesId
            downloadedItem.seasonId = item.seasonId
            
            modelContext?.insert(downloadedItem)
            try? modelContext?.save()
            
            Task {
                await downloadPosterImage(for: item, apiClient: apiClient)
                if item.type == "Episode", let seriesId = item.seriesId {
                    await downloadSeriesPosterImage(seriesId: seriesId, apiClient: apiClient)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.activeDownloads[itemId] = DownloadProgress(id: itemId, name: item.displayName, progress: existingItem?.progress ?? 0)
        }
        
        guard let session = sessionAndDelegate?.0 else { return }
        let task: URLSessionDownloadTask
        
        if let resumeData = existingItem?.resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            guard let downloadURL = await apiClient.downloadURL(itemId: itemId) else {
                updateStatus(itemId: itemId, status: "failed")
                return
            }
            task = session.downloadTask(with: downloadURL)
        }
        
        task.taskDescription = itemId
        activeTasks[itemId] = task
        task.resume()
    }
    
    private func downloadPosterImage(for item: BaseItemDto, apiClient: JellyfinAPIClient) async {
        guard let itemId = item.id else { return }
        guard let imageURL = await apiClient.imageURL(itemId: itemId, imageType: "Primary", maxWidth: 400, tag: item.imageTags?["Primary"]) else { return }
        
        do {
            let (data, _) = try await URLSession.lume.data(from: imageURL)
            let fileName = "poster_\(itemId).jpg"
            let destination = downloadsFolder.appendingPathComponent(fileName)
            try data.write(to: destination)
            
            let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
            if let downloaded = try? modelContext?.fetch(descriptor).first {
                downloaded.localImagePath = fileName
                try? modelContext?.save()
            }
        } catch {}
    }
    
    private func downloadSeriesPosterImage(seriesId: String, apiClient: JellyfinAPIClient) async {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.seriesId == seriesId && $0.localSeriesImagePath != nil })
        let items = try? modelContext?.fetch(descriptor)
        if !(items?.isEmpty ?? true) { return }
        
        guard let imageURL = await apiClient.imageURL(itemId: seriesId, imageType: "Primary", maxWidth: 400) else { return }
        
        do {
            let (data, _) = try await URLSession.lume.data(from: imageURL)
            let fileName = "series_poster_\(seriesId).jpg"
            let destination = downloadsFolder.appendingPathComponent(fileName)
            try data.write(to: destination)
            
            let allBySeries = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.seriesId == seriesId })
            if let all = try? modelContext?.fetch(allBySeries) {
                for it in all {
                    it.localSeriesImagePath = fileName
                }
                try? modelContext?.save()
            }
        } catch {}
    }
    
    func pauseDownload(itemId: String) {
        guard let task = activeTasks[itemId] else { return }
        task.cancel { [weak self] resumeDataOrNil in
            guard let self = self, let resumeData = resumeDataOrNil else { return }
            DispatchQueue.main.async {
                self.activeDownloads[itemId]?.isPaused = true
                self.activeTasks.removeValue(forKey: itemId)
            }
            let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
            if let item = try? self.modelContext?.fetch(descriptor).first {
                item.resumeData = resumeData
                item.status = "paused"
                try? self.modelContext?.save()
            }
        }
    }
    
    func resumeDownload(itemId: String, from apiClient: JellyfinAPIClient) async {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        if let item = try? modelContext?.fetch(descriptor).first {
            let dto = BaseItemDto(name: item.name, id: item.itemId, collectionType: item.collectionType, type: item.type)
            await download(dto, from: apiClient)
        }
    }
    
    func deleteDownload(itemId: String) {
        activeTasks[itemId]?.cancel()
        activeTasks.removeValue(forKey: itemId)
        activeDownloads.removeValue(forKey: itemId)
        
        if let localUrl = getLocalURL(for: itemId) {
            try? FileManager.default.removeItem(at: localUrl)
        }
        
        if let imagePath = getLocalImagePath(for: itemId) {
            try? FileManager.default.removeItem(at: imagePath)
        }
        
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        if let item = try? modelContext?.fetch(descriptor).first {
            modelContext?.delete(item)
            try? modelContext?.save()
        }
    }
    
    func isDownloaded(_ itemId: String) -> Bool {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId && $0.status == "completed" })
        let items = try? modelContext?.fetch(descriptor)
        return !(items?.isEmpty ?? true)
    }
    
    func getLocalURL(for itemId: String) -> URL? {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId && $0.status == "completed" })
        guard let item = try? modelContext?.fetch(descriptor).first else { return nil }
        let fileName = URL(fileURLWithPath: item.localUrl).lastPathComponent
        return downloadsFolder.appendingPathComponent(fileName)
    }
    
    func getLocalImagePath(for itemId: String) -> URL? {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        guard let item = try? modelContext?.fetch(descriptor).first, let path = item.localImagePath else { return nil }
        return downloadsFolder.appendingPathComponent(path)
    }
    
    func getLocalSeriesImagePath(for seriesId: String) -> URL? {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.seriesId == seriesId && $0.localSeriesImagePath != nil })
        guard let item = try? modelContext?.fetch(descriptor).first, let path = item.localSeriesImagePath else { return nil }
        return downloadsFolder.appendingPathComponent(path)
    }

    // MARK: - Internal Update Methods
    
    fileprivate func updateProgress(itemId: String, progress: Double) {
        activeDownloads[itemId]?.progress = progress
    }
    
    fileprivate func handleCompletion(itemId: String, location: URL) {
        guard let modelContext = modelContext else { return }
        let fileName = "\(itemId)_\(location.lastPathComponent)"
        let destination = downloadsFolder.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
            if let item = try? modelContext.fetch(descriptor).first {
                item.status = "completed"
                item.localUrl = fileName
                item.progress = 1.0
                item.resumeData = nil 
                try? modelContext.save()
            }
            DispatchQueue.main.async {
                self.activeDownloads[itemId]?.isCompleted = true
                self.activeDownloads[itemId]?.progress = 1.0
                self.activeTasks.removeValue(forKey: itemId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.activeDownloads.removeValue(forKey: itemId)
                }
            }
        } catch {
            updateStatus(itemId: itemId, status: "failed")
        }
    }
    
    fileprivate func updateStatus(itemId: String, status: String) {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        if let item = try? modelContext?.fetch(descriptor).first {
            item.status = status
            try? modelContext?.save()
        }
        if status == "failed" {
            activeDownloads[itemId]?.error = NSError(domain: "DownloadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
        }
    }
}

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let manager: DownloadManager
    init(manager: DownloadManager) {
        self.manager = manager
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let itemId = downloadTask.taskDescription else { return }
        manager.handleCompletion(itemId: itemId, location: location)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let itemId = downloadTask.taskDescription else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        manager.updateProgress(itemId: itemId, progress: progress)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, let itemId = task.taskDescription {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            manager.updateStatus(itemId: itemId, status: "failed")
        }
    }
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if LumeSessionDelegate.shared.ignoreSSLErrors,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
