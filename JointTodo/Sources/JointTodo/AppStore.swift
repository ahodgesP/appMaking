import Foundation
import Combine
import JointTodoCore

enum LinearDropPlacement: Equatable {
    case before
    case after
}

enum TaskDropPlacement: Equatable {
    case before
    case inside
    case after
    case outside
}

@MainActor
final class AppStore: ObservableObject {
    @Published var library: TodoLibrary
    @Published var selectedProjectID: UUID?
    @Published var selectedListID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let dataURL: URL
    private var persistedLibrary: TodoLibrary
    private var undoStack: [TodoLibrary] = []
    private var redoStack: [TodoLibrary] = []
    private let historyLimit = 100

    init(dataURL: URL = JointTodoPaths.defaultDataFile()) {
        self.dataURL = dataURL
        let initialLibrary: TodoLibrary
        do {
            initialLibrary = try TodoPersistence.load(from: dataURL)
        } catch {
            initialLibrary = .starter
            errorMessage = "Could not read the library: \(error.localizedDescription)"
        }
        library = initialLibrary
        persistedLibrary = initialLibrary
        selectedProjectID = library.projects.first?.id
        selectedListID = library.projects.first?.lists.first?.id
        save()
    }

    var selectedProject: Project? {
        guard let selectedProjectID else { return nil }
        return library.projects.first { $0.id == selectedProjectID }
    }

    var selectedList: TodoList? {
        guard let selectedProjectID, let selectedListID,
              let project = library.projects.first(where: { $0.id == selectedProjectID }) else { return nil }
        return project.lists.first { $0.id == selectedListID }
    }

    func addProject() {
        addProject(named: "New Project")
    }

    func addProject(named name: String) {
        let project = Project(name: name)
        library.projects.append(project)
        selectedProjectID = project.id
        selectedListID = nil
        commit()
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let index = library.projects.firstIndex(where: { $0.id == id }) else { return }
        library.projects[index].name = name
        commit()
    }

    func moveProject(_ id: UUID, relativeTo targetID: UUID, placement: LinearDropPlacement) {
        guard id != targetID,
              let sourceIndex = library.projects.firstIndex(where: { $0.id == id }) else { return }
        let project = library.projects.remove(at: sourceIndex)
        guard let targetIndex = library.projects.firstIndex(where: { $0.id == targetID }) else {
            library.projects.insert(project, at: min(sourceIndex, library.projects.count))
            return
        }
        library.projects.insert(project, at: targetIndex + (placement == .after ? 1 : 0))
        commit()
    }

    func deleteProject(_ id: UUID) {
        deleteProjects([id])
    }

    func deleteProjects(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        library.projects.removeAll { ids.contains($0.id) }
        selectedProjectID = library.projects.first?.id
        selectedListID = selectedProject?.lists.first?.id
        commit()
    }

    func addList() {
        addList(named: "New List")
    }

    func addList(named title: String) {
        guard let projectIndex else { return }
        let list = TodoList(title: title)
        library.projects[projectIndex].lists.append(list)
        selectedListID = list.id
        commit()
    }

    func renameList(_ id: UUID, to title: String) {
        mutateList(id) { $0.title = title }
    }

    func moveList(_ id: UUID, relativeTo targetID: UUID, placement: LinearDropPlacement) {
        guard id != targetID, let projectIndex else { return }
        var lists = library.projects[projectIndex].lists
        guard let sourceIndex = lists.firstIndex(where: { $0.id == id }) else { return }
        let list = lists.remove(at: sourceIndex)
        guard let targetIndex = lists.firstIndex(where: { $0.id == targetID }) else { return }
        lists.insert(list, at: targetIndex + (placement == .after ? 1 : 0))
        library.projects[projectIndex].lists = lists
        commit()
    }

    func deleteList(_ id: UUID) {
        guard let projectIndex else { return }
        library.projects[projectIndex].lists.removeAll { $0.id == id }
        selectedListID = library.projects[projectIndex].lists.first?.id
        commit()
    }

    func setListCompletion(_ id: UUID, completed: Bool) {
        mutateList(id) { $0.setListCompletion(completed) }
    }

    func setTimestampStyle(_ id: UUID, style: TimestampStyle) {
        mutateList(id) { $0.timestampStyle = style }
    }

    func addItem(to listID: UUID, parentID: UUID? = nil) {
        addItem(to: listID, parentID: parentID, titled: parentID == nil ? "New item" : "New sub-item")
    }

    func addItem(to listID: UUID, parentID: UUID? = nil, titled title: String) {
        mutateList(listID) { _ = $0.addItem(title: title, parentID: parentID) }
    }

    func renameItem(in listID: UUID, itemID: UUID, to title: String) {
        mutateList(listID) { list in
            guard let index = list.items.firstIndex(where: { $0.id == itemID }) else { return }
            list.items[index].title = title
        }
    }

    func setItemCompletion(in listID: UUID, itemID: UUID, completed: Bool) {
        mutateList(listID) { $0.setItemCompletion(itemID, completed: completed) }
    }

    func deleteItem(in listID: UUID, itemID: UUID) {
        mutateList(listID) { $0.deleteItem(itemID) }
    }

    func moveItem(
        in listID: UUID,
        itemID: UUID,
        relativeTo targetID: UUID,
        placement: TaskDropPlacement
    ) {
        guard itemID != targetID,
              let projectIndex,
              let listIndex = library.projects[projectIndex].lists.firstIndex(where: { $0.id == listID }) else { return }

        do {
            var list = library.projects[projectIndex].lists[listIndex]
            guard let target = list.items.first(where: { $0.id == targetID }) else { return }
            let parentID: UUID?
            let destinationIndex: Int

            switch placement {
            case .inside:
                parentID = target.id
                destinationIndex = list.children(of: target.id).filter { $0.id != itemID }.count
            case .before, .after:
                parentID = target.parentID
                let siblings = list.children(of: target.parentID).filter { $0.id != itemID }
                guard let targetIndex = siblings.firstIndex(where: { $0.id == targetID }) else { return }
                destinationIndex = targetIndex + (placement == .after ? 1 : 0)
            case .outside:
                guard let targetParentID = target.parentID,
                      let targetParent = list.items.first(where: { $0.id == targetParentID }) else {
                    parentID = nil
                    let siblings = list.children(of: nil).filter { $0.id != itemID }
                    destinationIndex = siblings.firstIndex(where: { $0.id == targetID }) ?? siblings.count
                    break
                }
                parentID = targetParent.parentID
                let siblings = list.children(of: targetParent.parentID).filter { $0.id != itemID }
                guard let parentIndex = siblings.firstIndex(where: { $0.id == targetParentID }) else { return }
                destinationIndex = parentIndex + 1
            }

            try list.moveItem(itemID, toParent: parentID, at: destinationIndex)
            library.projects[projectIndex].lists[listIndex] = list
            commit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        do {
            library = try TodoPersistence.load(from: dataURL)
            acceptExternalLibrary()
        } catch {
            errorMessage = "Could not reload the library: \(error.localizedDescription)"
        }
    }

    func reloadIfChanged() {
        do {
            let diskLibrary = try TodoPersistence.load(from: dataURL)
            guard diskLibrary.revision != library.revision else { return }
            library = diskLibrary
            acceptExternalLibrary()
            if !library.projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = library.projects.first?.id
            }
            if selectedList == nil {
                selectedListID = selectedProject?.lists.first?.id
            }
        } catch {
            errorMessage = "Could not reload agent changes: \(error.localizedDescription)"
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        let current = library
        library = revisionBumped(previous, after: current)
        guard saveReportingFailure() else {
            library = current
            undoStack.append(previous)
            updateHistoryAvailability()
            return
        }
        redoStack.append(current)
        persistedLibrary = library
        updateHistoryAvailability()
        normalizeSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        let current = library
        library = revisionBumped(next, after: current)
        guard saveReportingFailure() else {
            library = current
            redoStack.append(next)
            updateHistoryAvailability()
            return
        }
        undoStack.append(current)
        persistedLibrary = library
        updateHistoryAvailability()
        normalizeSelection()
    }

    private var projectIndex: Int? {
        guard let selectedProjectID else { return nil }
        return library.projects.firstIndex { $0.id == selectedProjectID }
    }

    private func mutateList(_ listID: UUID, mutation: (inout TodoList) -> Void) {
        guard let projectIndex,
              let listIndex = library.projects[projectIndex].lists.firstIndex(where: { $0.id == listID }) else { return }
        mutation(&library.projects[projectIndex].lists[listIndex])
        commit()
    }

    private func commit() {
        let previous = persistedLibrary
        library.revision += 1
        guard saveReportingFailure() else {
            library = previous
            return
        }
        if previous != library {
            undoStack.append(previous)
            if undoStack.count > historyLimit {
                undoStack.removeFirst(undoStack.count - historyLimit)
            }
            redoStack.removeAll()
        }
        persistedLibrary = library
        updateHistoryAvailability()
    }

    private func save() {
        _ = saveReportingFailure()
        persistedLibrary = library
    }

    private func saveReportingFailure() -> Bool {
        do {
            try TodoPersistence.save(library, to: dataURL)
            return true
        } catch {
            errorMessage = "Could not save changes: \(error.localizedDescription)"
            return false
        }
    }

    private func acceptExternalLibrary() {
        persistedLibrary = library
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryAvailability()
        normalizeSelection()
    }

    private func normalizeSelection() {
        if !library.projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = library.projects.first?.id
        }
        if selectedList == nil {
            selectedListID = selectedProject?.lists.first?.id
        }
    }

    private func revisionBumped(_ snapshot: TodoLibrary, after current: TodoLibrary) -> TodoLibrary {
        var result = snapshot
        result.revision = max(snapshot.revision, current.revision) + 1
        return result
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
