import Foundation
import JointTodoCore

private let cliVersion = "0.4.0"

private func usage() -> Never {
    print("""
    JointTodo CLI \(cliVersion)

    Usage:
      jointodo [--data-file <path>] path
      jointodo [--data-file <path>] show [--json]

      jointodo [--data-file <path>] project-add <name>
      jointodo [--data-file <path>] project-rename <project-name-or-id> <new-name>
      jointodo [--data-file <path>] project-delete <project-name-or-id> [project-name-or-id ...]
      jointodo [--data-file <path>] project-move <project-name-or-id> <position>

      jointodo [--data-file <path>] list-add <project-name-or-id> <title>
      jointodo [--data-file <path>] list-rename <list-name-or-id> <new-title>
      jointodo [--data-file <path>] list-delete <list-name-or-id> [list-name-or-id ...]
      jointodo [--data-file <path>] list-move <list-name-or-id> <position>
      jointodo [--data-file <path>] list-complete <list-name-or-id>
      jointodo [--data-file <path>] list-uncomplete <list-name-or-id>
      jointodo [--data-file <path>] list-timestamp <list-name-or-id> <date|datetime|timezone>

      jointodo [--data-file <path>] item-add <list-name-or-id> <title> [--parent <item-name-or-id>]
      jointodo [--data-file <path>] item-rename <list-name-or-id> <item-name-or-id> <new-title>
      jointodo [--data-file <path>] item-delete <list-name-or-id> <item-name-or-id> [item-name-or-id ...]
      jointodo [--data-file <path>] item-move <list-name-or-id> <item-name-or-id> <position> [--parent <item-name-or-id|root>]
      jointodo [--data-file <path>] item-complete <list-name-or-id> <item-name-or-id>
      jointodo [--data-file <path>] item-uncomplete <list-name-or-id> <item-name-or-id>

    Compatibility aliases:
      complete   = item-complete
      uncomplete = item-uncomplete

    Environment:
      JOINTODO_DATA_FILE overrides the default ~/Documents/JointTodo/jointodo.json.
      --data-file takes precedence over JOINTODO_DATA_FILE.

    Agent workflow:
      1. jointodo path
      2. jointodo show --json
      3. Mutate using IDs from the JSON whenever names may be ambiguous.
      4. jointodo show --json to verify the resulting state.
    """)
    exit(2)
}

private func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("\(message)\n", stderr)
    exit(code)
}

private func cleaned(_ parts: ArraySlice<String>) -> String {
    parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var dataURL = JointTodoPaths.defaultDataFile()

if let flagIndex = arguments.firstIndex(of: "--data-file") {
    guard arguments.indices.contains(flagIndex + 1) else { usage() }
    dataURL = URL(fileURLWithPath: arguments[flagIndex + 1]).standardizedFileURL
    arguments.removeSubrange(flagIndex...flagIndex + 1)
}

if arguments == ["--version"] || arguments == ["version"] {
    print(cliVersion)
    exit(0)
}

guard let command = arguments.first else { usage() }
let dataFileExisted = FileManager.default.fileExists(atPath: dataURL.path)
var library: TodoLibrary

do {
    library = try TodoPersistence.load(from: dataURL)
} catch {
    fail("Could not read \(dataURL.path): \(error)")
}

if !dataFileExisted {
    do {
        try TodoPersistence.save(library, to: dataURL)
    } catch {
        fail("Could not initialize \(dataURL.path): \(error)")
    }
}

@MainActor
func save() {
    library.revision += 1
    do {
        try TodoPersistence.save(library, to: dataURL)
    } catch {
        fail("Could not save: \(error)")
    }
}

@MainActor
func locateProject(_ reference: String) -> Int? {
    if let id = UUID(uuidString: reference) {
        return library.projects.firstIndex { $0.id == id }
    }
    let matches = library.projects.indices.filter {
        library.projects[$0].name.caseInsensitiveCompare(reference) == .orderedSame
    }
    guard matches.count <= 1 else {
        fail("Project name is ambiguous; use its ID: \(reference)")
    }
    return matches.first
}

@MainActor
func requireProject(_ reference: String) -> Int {
    guard let index = locateProject(reference) else {
        fail("No project found: \(reference)")
    }
    return index
}

@MainActor
func locateList(_ reference: String) -> (Int, Int)? {
    let requestedID = UUID(uuidString: reference)
    var matches: [(Int, Int)] = []
    for projectIndex in library.projects.indices {
        for listIndex in library.projects[projectIndex].lists.indices {
            let list = library.projects[projectIndex].lists[listIndex]
            if list.id == requestedID ||
                (requestedID == nil && list.title.caseInsensitiveCompare(reference) == .orderedSame) {
                matches.append((projectIndex, listIndex))
            }
        }
    }
    guard matches.count <= 1 else {
        fail("List name is ambiguous; use its ID: \(reference)")
    }
    return matches.first
}

@MainActor
func requireList(_ reference: String) -> (Int, Int) {
    guard let location = locateList(reference) else {
        fail("No list found: \(reference)")
    }
    return location
}

func locateItem(_ reference: String, in list: TodoList) -> UUID? {
    if let id = UUID(uuidString: reference), list.items.contains(where: { $0.id == id }) {
        return id
    }
    let matches = list.items.filter { $0.title.caseInsensitiveCompare(reference) == .orderedSame }
    guard matches.count <= 1 else {
        fail("Item name is ambiguous within list \(list.title); use its ID: \(reference)")
    }
    return matches.first?.id
}

func requireItem(_ reference: String, in list: TodoList) -> UUID {
    guard let id = locateItem(reference, in: list) else {
        fail("No item found in list \(list.title): \(reference)")
    }
    return id
}

func printJSON(_ value: some Encodable) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
    } catch {
        fail("Could not encode JSON: \(error)")
    }
}

func requirePosition(_ value: String, maximum: Int) -> Int {
    guard let position = Int(value), position >= 1, position <= maximum else {
        fail("Position must be between 1 and \(maximum): \(value)")
    }
    return position
}

func printItems(in list: TodoList, parentID: UUID? = nil, depth: Int = 0) {
    for item in list.children(of: parentID) {
        let indent = String(repeating: "  ", count: depth + 2)
        let branch = depth == 0 ? "" : "↳ "
        print("\(indent)\(branch)\(item.isCompleted ? "✓" : "○") \(item.title) [\(item.id.uuidString)]")
        printItems(in: list, parentID: item.id, depth: depth + 1)
    }
}

switch command {
case "path":
    guard arguments.count == 1 else { usage() }
    print(dataURL.path)

case "show":
    if arguments.dropFirst().contains("--json") {
        printJSON(library)
        break
    }
    guard arguments.count == 1 else { usage() }
    for project in library.projects {
        print("\(project.name) [\(project.id.uuidString)]")
        for list in project.lists {
            print("  \(list.isCompleted ? "✓" : "○") \(list.title) [\(list.id.uuidString)]")
            printItems(in: list)
        }
    }

case "project-add":
    let name = cleaned(arguments.dropFirst())
    guard !name.isEmpty else { usage() }
    let project = Project(name: name)
    library.projects.append(project)
    save()
    print("created\tproject\t\(project.id.uuidString)\t\(project.name)")

case "project-rename":
    guard arguments.count >= 3 else { usage() }
    let index = requireProject(arguments[1])
    let name = cleaned(arguments.dropFirst(2))
    guard !name.isEmpty else { usage() }
    library.projects[index].name = name
    let id = library.projects[index].id
    save()
    print("renamed\tproject\t\(id.uuidString)\t\(name)")

case "project-delete":
    guard arguments.count >= 2 else { usage() }
    var projectIDs = Set<UUID>()
    for reference in arguments.dropFirst() {
        projectIDs.insert(library.projects[requireProject(reference)].id)
    }
    let deleted = library.projects.filter { projectIDs.contains($0.id) }
    library.projects.removeAll { projectIDs.contains($0.id) }
    save()
    for project in deleted {
        print("deleted\tproject\t\(project.id.uuidString)\t\(project.name)")
    }

case "project-move":
    guard arguments.count == 3 else { usage() }
    let sourceIndex = requireProject(arguments[1])
    let destination = requirePosition(arguments[2], maximum: library.projects.count) - 1
    let project = library.projects.remove(at: sourceIndex)
    library.projects.insert(project, at: destination)
    save()
    print("moved\tproject\t\(project.id.uuidString)\tposition=\(destination + 1)")

case "list-add":
    guard arguments.count >= 3 else { usage() }
    let projectIndex = requireProject(arguments[1])
    let title = cleaned(arguments.dropFirst(2))
    guard !title.isEmpty else { usage() }
    let list = TodoList(title: title)
    library.projects[projectIndex].lists.append(list)
    save()
    print("created\tlist\t\(list.id.uuidString)\t\(list.title)")

case "list-rename":
    guard arguments.count >= 3 else { usage() }
    let location = requireList(arguments[1])
    let title = cleaned(arguments.dropFirst(2))
    guard !title.isEmpty else { usage() }
    library.projects[location.0].lists[location.1].title = title
    let id = library.projects[location.0].lists[location.1].id
    save()
    print("renamed\tlist\t\(id.uuidString)\t\(title)")

case "list-delete":
    guard arguments.count >= 2 else { usage() }
    var listIDs = Set<UUID>()
    var deleted: [TodoList] = []
    for reference in arguments.dropFirst() {
        let location = requireList(reference)
        let list = library.projects[location.0].lists[location.1]
        if listIDs.insert(list.id).inserted { deleted.append(list) }
    }
    for projectIndex in library.projects.indices {
        library.projects[projectIndex].lists.removeAll { listIDs.contains($0.id) }
    }
    save()
    for list in deleted {
        print("deleted\tlist\t\(list.id.uuidString)\t\(list.title)")
    }

case "list-move":
    guard arguments.count == 3 else { usage() }
    let location = requireList(arguments[1])
    let maximum = library.projects[location.0].lists.count
    let destination = requirePosition(arguments[2], maximum: maximum) - 1
    let list = library.projects[location.0].lists.remove(at: location.1)
    library.projects[location.0].lists.insert(list, at: destination)
    save()
    print("moved\tlist\t\(list.id.uuidString)\tposition=\(destination + 1)")

case "list-complete", "list-uncomplete":
    guard arguments.count == 2 else { usage() }
    let location = requireList(arguments[1])
    let completed = command == "list-complete"
    library.projects[location.0].lists[location.1].setListCompletion(completed)
    let list = library.projects[location.0].lists[location.1]
    save()
    print("\(completed ? "completed" : "uncompleted")\tlist\t\(list.id.uuidString)\t\(list.title)")

case "list-timestamp":
    guard arguments.count == 3 else { usage() }
    let location = requireList(arguments[1])
    let style: TimestampStyle
    switch arguments[2].lowercased() {
    case "date": style = .dateOnly
    case "datetime": style = .dateAndTime
    case "timezone": style = .dateTimeAndZone
    default: fail("Unknown timestamp style: \(arguments[2]). Use date, datetime, or timezone.")
    }
    library.projects[location.0].lists[location.1].timestampStyle = style
    let list = library.projects[location.0].lists[location.1]
    save()
    print("updated\tlist\t\(list.id.uuidString)\ttimestamp=\(style.rawValue)")

case "item-add":
    guard arguments.count >= 3 else { usage() }
    let location = requireList(arguments[1])
    var titleParts = Array(arguments.dropFirst(2))
    var parentID: UUID?
    if let flagIndex = titleParts.firstIndex(of: "--parent") {
        guard titleParts.indices.contains(flagIndex + 1) else { usage() }
        let list = library.projects[location.0].lists[location.1]
        parentID = requireItem(titleParts[flagIndex + 1], in: list)
        titleParts.removeSubrange(flagIndex...flagIndex + 1)
    }
    let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { usage() }
    let id = library.projects[location.0].lists[location.1].addItem(title: title, parentID: parentID)
    save()
    print("created\titem\t\(id.uuidString)\t\(title)")

case "item-rename":
    guard arguments.count >= 4 else { usage() }
    let location = requireList(arguments[1])
    let currentList = library.projects[location.0].lists[location.1]
    let itemID = requireItem(arguments[2], in: currentList)
    let title = cleaned(arguments.dropFirst(3))
    guard !title.isEmpty else { usage() }
    guard let itemIndex = library.projects[location.0].lists[location.1].items.firstIndex(where: { $0.id == itemID }) else {
        fail("Item disappeared before it could be renamed: \(itemID.uuidString)")
    }
    library.projects[location.0].lists[location.1].items[itemIndex].title = title
    save()
    print("renamed\titem\t\(itemID.uuidString)\t\(title)")

case "item-delete":
    guard arguments.count >= 3 else { usage() }
    let location = requireList(arguments[1])
    let currentList = library.projects[location.0].lists[location.1]
    var deleted: [(UUID, String)] = []
    for reference in arguments.dropFirst(2) {
        let id = requireItem(reference, in: currentList)
        if !deleted.contains(where: { $0.0 == id }) {
            let title = currentList.items.first(where: { $0.id == id })?.title ?? reference
            deleted.append((id, title))
        }
    }
    for (id, _) in deleted {
        library.projects[location.0].lists[location.1].deleteItem(id)
    }
    save()
    for (id, title) in deleted {
        print("deleted\titem\t\(id.uuidString)\t\(title)")
    }

case "item-move":
    guard arguments.count == 4 || arguments.count == 6 else { usage() }
    let location = requireList(arguments[1])
    let currentList = library.projects[location.0].lists[location.1]
    let itemID = requireItem(arguments[2], in: currentList)
    let currentItem = currentList.items.first(where: { $0.id == itemID })!
    var parentID = currentItem.parentID

    if arguments.count == 6 {
        guard arguments[4] == "--parent" else { usage() }
        parentID = arguments[5].lowercased() == "root"
            ? nil
            : requireItem(arguments[5], in: currentList)
    }

    let siblingCount = currentList.children(of: parentID).filter { $0.id != itemID }.count
    let destination = requirePosition(arguments[3], maximum: siblingCount + 1) - 1
    do {
        try library.projects[location.0].lists[location.1].moveItem(
            itemID,
            toParent: parentID,
            at: destination
        )
    } catch {
        fail("Could not move item: \(error.localizedDescription)")
    }
    save()
    print("moved\titem\t\(itemID.uuidString)\tposition=\(destination + 1) parent=\(parentID?.uuidString ?? "root")")

case "item-complete", "item-uncomplete", "complete", "uncomplete":
    guard arguments.count == 3 else { usage() }
    let location = requireList(arguments[1])
    let list = library.projects[location.0].lists[location.1]
    let itemID = requireItem(arguments[2], in: list)
    let completed = command == "item-complete" || command == "complete"
    library.projects[location.0].lists[location.1].setItemCompletion(itemID, completed: completed)
    save()
    print("\(completed ? "completed" : "uncompleted")\titem\t\(itemID.uuidString)\t\(arguments[2])")

default:
    usage()
}
