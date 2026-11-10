import Foundation

/// One entry of the app list: a process number or a piece of a program path.
public enum SpecPattern: Equatable {
    case pid(UInt32)
    case name(String)

    public init(_ text: String) {
        if let pid = UInt32(text) {
            self = .pid(pid)
        } else {
            self = .name(text)
        }
    }

    func matches(_ process: ProcessIdentity) -> Bool {
        switch self {
        case .pid(let pid):
            return process.pid == pid
        case .name(let name):
            guard let path = process.path else { return false }
            return path.contains(name)
        }
    }
}

/// One rule: capture the matching programs, or (leading "!") skip them.
public enum SpecAction: Equatable {
    case include(SpecPattern)
    case exclude(SpecPattern)

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("!") {
            let rest = String(trimmed.dropFirst())
            if rest.isEmpty { return nil }
            self = .exclude(SpecPattern(rest))
        } else {
            self = .include(SpecPattern(trimmed))
        }
    }
}

/// Which program made a connection.
public struct ProcessIdentity: Equatable {
    public var pid: UInt32
    public var path: String?

    public init(pid: UInt32, path: String?) {
        self.pid = pid
        self.path = path
    }
}

/// The app list that decides whether a connection is captured.
///
/// Rules are applied in order. When the first rule is a skip rule, the
/// default is "capture everything"; otherwise the default is "capture
/// nothing". An empty list captures nothing, which is how capture is stopped.
public struct InterceptSpec: Equatable {
    public let actions: [SpecAction]

    public init(actions: [SpecAction]) {
        self.actions = actions
    }

    /// Builds the list from its text form, for example `["curl", "!1234"]`.
    /// Blank entries are ignored.
    public init(parsing entries: [String]) {
        self.actions = entries.compactMap { SpecAction($0) }
    }

    public var entries: [String] {
        actions.map { action in
            switch action {
            case .include(.pid(let pid)): return String(pid)
            case .include(.name(let name)): return name
            case .exclude(.pid(let pid)): return "!\(pid)"
            case .exclude(.name(let name)): return "!\(name)"
            }
        }
    }

    public func shouldIntercept(_ process: ProcessIdentity) -> Bool {
        // A list that starts with a skip rule means "everything except these".
        var intercept = false
        if let first = actions.first, case .exclude = first {
            intercept = true
        }
        for action in actions {
            switch action {
            case .include(let pattern):
                intercept = intercept || pattern.matches(process)
            case .exclude(let pattern):
                intercept = intercept && !pattern.matches(process)
            }
        }
        return intercept
    }
}
