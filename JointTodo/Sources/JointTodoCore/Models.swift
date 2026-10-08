import Foundation

public enum TimestampStyle: String, Codable, CaseIterable, Sendable {
    case dateOnly
    case dateAndTime
    case dateTimeAndZone

    public var label: String {
        switch self {
        case .dateOnly: "Date"
        case .dateAndTime: "Date & time"
        case .dateTimeAndZone: "Date, time & zone"
        }
    }

    public func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        switch self {
        case .dateOnly:
            formatter.timeStyle = .none
        case .dateAndTime:
            formatter.timeStyle = .short
        case .dateTimeAndZone:
            formatter.timeStyle = .short
            formatter.timeZone = .current
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm a zzz"
        }
        return formatter.string(from: date)
    }
}

public struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var parentID: UUID?
    public var position: Int
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        parentID: UUID? = nil,
        position: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.parentID = parentID
        self.position = position
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
}

public struct TodoList: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var completedAt: Date?
    public var timestampStyle: TimestampStyle
    public var items: [TaskItem]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        timestampStyle: TimestampStyle = .dateAndTime,
        items: [TaskItem] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.timestampStyle = timestampStyle
        self.items = items
    }

    public var isCompleted: Bool { completedAt != nil }

    public func children(of parentID: UUID?) -> [TaskItem] {
        items
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                lhs.position == rhs.position
                    ? lhs.createdAt < rhs.createdAt
                    : lhs.position < rhs.position
            }
    }

    public mutating func addItem(title: String, parentID: UUID? = nil, now: Date = Date()) -> UUID {
        let nextPosition = children(of: parentID).count
        let item = TaskItem(title: title, parentID: parentID, position: nextPosition, createdAt: now)
        items.append(item)
        completedAt = nil
        return item.id
    }

    public mutating func setItemCompletion(_ itemID: UUID, completed: Bool, now: Date = Date()) {
        setCompletionRecursively(itemID, completed: completed, now: now)
        updateAncestors(startingAt: items.first(where: { $0.id == itemID })?.parentID, now: now)
        refreshCompletion(now: now)
    }

    public mutating func setListCompletion(_ completed: Bool, now: Date = Date()) {
        for index in items.indices {
            items[index].completedAt = completed ? (items[index].completedAt ?? now) : nil
        }
        completedAt = completed ? (completedAt ?? now) : nil
    }

    public mutating func deleteItem(_ itemID: UUID, now: Date = Date()) {
        let descendantIDs = descendants(of: itemID)
        let parentID = items.first(where: { $0.id == itemID })?.parentID
        items.removeAll { $0.id == itemID || descendantIDs.contains($0.id) }
        updateAncestors(startingAt: parentID, now: now)
        refreshCompletion(now: now)
    }

    public mutating func refreshCompletion(now: Date = Date()) {
        let roots = children(of: nil)
        completedAt = !roots.isEmpty && roots.allSatisfy(\.isCompleted)
            ? (completedAt ?? now)
            : nil
    }

    private mutating func setCompletionRecursively(_ itemID: UUID, completed: Bool, now: Date) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].completedAt = completed ? (items[index].completedAt ?? now) : nil
        }
        for child in children(of: itemID) {
            setCompletionRecursively(child.id, completed: completed, now: now)
        }
    }

    private mutating func updateAncestors(startingAt parentID: UUID?, now: Date) {
        guard let parentID,
              let index = items.firstIndex(where: { $0.id == parentID }) else { return }
        let children = children(of: parentID)
        items[index].completedAt = !children.isEmpty && children.allSatisfy(\.isCompleted)
            ? (items[index].completedAt ?? now)
            : nil
        updateAncestors(startingAt: items[index].parentID, now: now)
    }

    private func descendants(of itemID: UUID) -> Set<UUID> {
        children(of: itemID).reduce(into: Set<UUID>()) { result, child in
            result.insert(child.id)
            result.formUnion(descendants(of: child.id))
        }
    }
}

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var lists: [TodoList]

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), lists: [TodoList] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lists = lists
    }
}

public struct TodoLibrary: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var revision: Int
    public var projects: [Project]

    public init(schemaVersion: Int = 1, revision: Int = 0, projects: [Project] = []) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.projects = projects
    }

    public static var starter: TodoLibrary {
        var chores = TodoList(title: "Chores")
        let bathroom = chores.addItem(title: "Clean bathroom")
        _ = chores.addItem(title: "Clean toilet", parentID: bathroom)
        _ = chores.addItem(title: "Clean vanity", parentID: bathroom)
        _ = chores.addItem(title: "Clean kitchen")
        return TodoLibrary(projects: [Project(name: "Home", lists: [chores])])
    }
}
