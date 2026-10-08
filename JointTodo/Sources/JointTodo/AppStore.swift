import Foundation
import Combine
import JointTodoCore

@MainActor
final class AppStore: ObservableObject {
    @Published var library: TodoLibrary
    @Published var selectedProjectID: UUID?
    @Published var selectedListID: UUID?
    @Published var errorMessage: String?

    let dataURL: URL

    init(dataURL: URL = JointTodoPaths.defaultDataFile()) {
        self.dataURL = dataURL
        do {
            library = try TodoPersistence.load(from: dataURL)
        } catch {
            library = .starter
            errorMessage = "Could not read the library: \(error.localizedDescription)"
        }
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

    func reload() {
        do {
            library = try TodoPersistence.load(from: dataURL)
        } catch {
            errorMessage = "Could not reload the library: \(error.localizedDescription)"
        }
    }

    func reloadIfChanged() {
        do {
            let diskLibrary = try TodoPersistence.load(from: dataURL)
            guard diskLibrary.revision != library.revision else { return }
            library = diskLibrary
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
        library.revision += 1
        save()
    }

    private func save() {
        do {
            try TodoPersistence.save(library, to: dataURL)
        } catch {
            errorMessage = "Could not save changes: \(error.localizedDescription)"
        }
    }
}
