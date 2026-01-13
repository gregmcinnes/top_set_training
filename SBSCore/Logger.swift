import Foundation
import os.log

/// Centralized logging utility that only logs in DEBUG builds
public enum Logger {
    
    // MARK: - OS Log Categories
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.gregorymcinnes.topsettraining"
    
    private static let generalLog = OSLog(subsystem: subsystem, category: "general")
    private static let storeLog = OSLog(subsystem: subsystem, category: "store")
    private static let activityLog = OSLog(subsystem: subsystem, category: "liveActivity")
    private static let programLog = OSLog(subsystem: subsystem, category: "program")
    private static let uiLog = OSLog(subsystem: subsystem, category: "ui")
    private static let healthKitLog = OSLog(subsystem: subsystem, category: "healthKit")
    
    // MARK: - Log Categories
    
    public enum Category {
        case general
        case store
        case liveActivity
        case program
        case ui
        case healthKit
        
        var osLog: OSLog {
            switch self {
            case .general: return Logger.generalLog
            case .store: return Logger.storeLog
            case .liveActivity: return Logger.activityLog
            case .program: return Logger.programLog
            case .ui: return Logger.uiLog
            case .healthKit: return Logger.healthKitLog
            }
        }
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a debug message (only in DEBUG builds)
    public static func debug(_ message: String, category: Category = .general) {
        #if DEBUG
        os_log(.debug, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    /// Log an info message (only in DEBUG builds)
    public static func info(_ message: String, category: Category = .general) {
        #if DEBUG
        os_log(.info, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    /// Log a warning message (only in DEBUG builds)
    public static func warning(_ message: String, category: Category = .general) {
        #if DEBUG
        os_log(.default, log: category.osLog, "⚠️ %{public}@", message)
        #endif
    }
    
    /// Log an error message (always logs, even in release)
    public static func error(_ message: String, category: Category = .general) {
        os_log(.error, log: category.osLog, "❌ %{public}@", message)
    }
}


