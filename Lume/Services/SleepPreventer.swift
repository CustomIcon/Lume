import Foundation
import AppKit

final class SleepPreventer {
    static let shared = SleepPreventer()
    
    private var activity: NSObjectProtocol?
    private var reason: String?
    
    private init() {}
    func startPreventingSleep(reason: String = "Watching media") {
        print("[Lume] Requesting sleep prevention: \(reason)")
        
        stopPreventingSleep()
        
        self.reason = reason
        self.activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: reason
        )
    }
    
    func stopPreventingSleep() {
        if let activity = activity {
            print("[Lume] Stopping sleep prevention")
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            self.reason = nil
        }
    }
}
