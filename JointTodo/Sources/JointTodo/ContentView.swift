import SwiftUI
import Combine
import AppKit
import CoreTransferable
import UniformTypeIdentifiers
import JointTodoCore

private extension UTType {
    static let jointTodoProject = UTType(exportedAs: "local.jointodo.project")
    static let jointTodoList = UTType(exportedAs: "local.jointodo.list")
    static let jointTodoTask = UTType(exportedAs: "local.jointodo.task")
}

private struct ProjectDragPayload: Codable, Transferable {
    let projectID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .jointTodoProject)
    }
}

private struct ListDragPayload: Codable, Transferable {
    let projectID: UUID
    let listID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .jointTodoList)
    }
}

private struct TaskDragPayload: Codable, Transferable {
    let listID: UUID
    let itemID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .jointTodoTask)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var projectRowFrames: [UUID: CGRect] = [:]
    @State private var dragAnchorProjectID: UUID?
    @FocusState private var projectPaneFocused: Bool
    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            projectSidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            listSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            listDetail
        }
        .frame(minWidth: 900, minHeight: 580)
        .alert("JointTodo", isPresented: errorBinding) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .onReceive(refreshTimer) { _ in store.reloadIfChanged() }
    }

    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Projects")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 5)
            ScrollView {
                LazyVStack(spacing: 2) {
                ForEach(store.library.projects) { project in
                    ProjectSidebarRow(
                        project: project,
                        isSelected: selectedProjectIDs.contains(project.id),
                        onRename: { store.renameProject(project.id, to: $0) },
                        onSelectionDragChanged: updateProjectDragSelection,
                        onSelectionDragEnded: finishProjectDragSelection
                    )
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ProjectRowFramePreferenceKey.self,
                                value: [project.id: geometry.frame(in: .named("project-list"))]
                            )
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { selectProject(project.id) })
                    .contextMenu {
                        Button("Delete Project", role: .destructive) {
                            let ids = selectedProjectIDs.contains(project.id) ? selectedProjectIDs : [project.id]
                            deleteProjects(ids)
                        }
                    }
                }
                DoubleClickCreationArea(
                    prompt: "Double-click to add a project",
                    onSingleClick: clearProjectSelection,
                    onDoubleClick: addAndSelectProject
                )
                }
                .padding(.horizontal, 8)
            }
            .coordinateSpace(name: "project-list")
            .onPreferenceChange(ProjectRowFramePreferenceKey.self) { projectRowFrames = $0 }
            .focusable()
            .focused($projectPaneFocused)
            .onDeleteCommand { deleteProjects(selectedProjectIDs) }

            Button(action: selectAllProjects) { EmptyView() }
                .keyboardShortcut("a", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .navigationTitle("JointTodo")
        .toolbar {
            ToolbarItem {
                Button(action: addAndSelectProject) {
                    Label("New Project", systemImage: "folder.badge.plus")
                }
                .floatingHelp("Create a new project")
            }
        }
        .onAppear {
            if let selectedProjectID = store.selectedProjectID {
                selectedProjectIDs = [selectedProjectID]
            }
        }
        .onChange(of: selectedProjectIDs) { oldSelection, newSelection in
            applyProjectSelection(from: oldSelection, to: newSelection)
        }
    }

    @ViewBuilder
    private var listSidebar: some View {
        if let project = store.selectedProject {
            List(selection: $store.selectedListID) {
                Section(project.name) {
                    ForEach(project.lists) { list in
                        TodoListSidebarRow(list: list, projectID: project.id)
                        .tag(list.id)
                        .contextMenu {
                            Button("Delete List", role: .destructive) { store.deleteList(list.id) }
                        }
                    }
                    DoubleClickCreationArea(
                        prompt: "Double-click to add a list",
                        onSingleClick: { store.selectedListID = nil },
                        onDoubleClick: store.addList
                    )
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem {
                    Button(action: store.addList) {
                        Label("New List", systemImage: "plus")
                    }
                    .floatingHelp("Create a new list in \(project.name)")
                }
            }
            .onDeleteCommand {
                if let selectedListID = store.selectedListID {
                    store.deleteList(selectedListID)
                }
            }
        } else {
            ContentUnavailableView("No Project", systemImage: "folder", description: Text("Create a project to get started."))
        }
    }

    @ViewBuilder
    private var listDetail: some View {
        if let list = store.selectedList {
            VStack(alignment: .leading, spacing: 0) {
                ListHeader(list: list)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                Divider()
                QuickAddRow(listID: list.id)
                    .id(list.id)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                Divider()
                if list.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here yet", systemImage: "checklist")
                    } description: {
                        Text("Add the first item to this list.")
                    } actions: {
                        Button("Add Item") { store.addItem(to: list.id) }
                            .floatingHelp("Create the first item in this list")
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(list.children(of: nil)) { item in
                                TaskRow(list: list, item: item, depth: 0)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { store.addItem(to: list.id) } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                    .floatingHelp("Create a new item in this list")
                    Button(action: store.reload) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .floatingHelp("Reload changes made by a local agent")
                }
            }
        } else {
            ContentUnavailableView("Select a List", systemImage: "checklist", description: Text("Choose a list from the sidebar."))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }

    private func addAndSelectProject() {
        store.addProject()
        if let selectedProjectID = store.selectedProjectID {
            selectedProjectIDs = [selectedProjectID]
        }
        projectPaneFocused = true
    }

    private func clearProjectSelection() {
        selectedProjectIDs = []
        store.selectedProjectID = nil
        store.selectedListID = nil
        projectPaneFocused = true
    }

    private func applyProjectSelection(from oldSelection: Set<UUID>, to newSelection: Set<UUID>) {
        guard !newSelection.isEmpty else {
            clearProjectSelection()
            return
        }

        let added = newSelection.subtracting(oldSelection)
        let nextActiveID: UUID?
        if !added.isEmpty {
            nextActiveID = store.library.projects.last(where: { added.contains($0.id) })?.id
        } else if let current = store.selectedProjectID, newSelection.contains(current) {
            nextActiveID = current
        } else {
            nextActiveID = store.library.projects.first(where: { newSelection.contains($0.id) })?.id
        }

        guard store.selectedProjectID != nextActiveID else { return }
        store.selectedProjectID = nextActiveID
        store.selectedListID = store.selectedProject?.lists.first?.id
    }

    private func deleteProjects(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        store.deleteProjects(ids)
        selectedProjectIDs = store.selectedProjectID.map { [$0] } ?? []
    }

    private func selectProject(_ id: UUID) {
        projectPaneFocused = true
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if selectedProjectIDs.contains(id) {
                selectedProjectIDs.remove(id)
            } else {
                selectedProjectIDs.insert(id)
            }
            return
        }

        if modifiers.contains(.shift),
           let anchorID = store.selectedProjectID,
           let anchorIndex = store.library.projects.firstIndex(where: { $0.id == anchorID }),
           let currentIndex = store.library.projects.firstIndex(where: { $0.id == id }) {
            let bounds = min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)
            selectedProjectIDs = Set(bounds.map { store.library.projects[$0].id })
            return
        }

        selectedProjectIDs = [id]
    }

    private func selectAllProjects() {
        guard projectPaneFocused else { return }
        selectedProjectIDs = Set(store.library.projects.map(\.id))
    }

    private func updateProjectDragSelection(_ value: DragGesture.Value) {
        guard !projectRowFrames.isEmpty else { return }
        if dragAnchorProjectID == nil {
            dragAnchorProjectID = projectNearest(to: value.startLocation)
        }
        guard let anchorID = dragAnchorProjectID,
              let currentID = projectNearest(to: value.location),
              let anchorIndex = store.library.projects.firstIndex(where: { $0.id == anchorID }),
              let currentIndex = store.library.projects.firstIndex(where: { $0.id == currentID }) else { return }

        let bounds = min(anchorIndex, currentIndex)...max(anchorIndex, currentIndex)
        selectedProjectIDs = Set(bounds.map { store.library.projects[$0].id })
    }

    private func finishProjectDragSelection(_ value: DragGesture.Value) {
        updateProjectDragSelection(value)
        let finalSelection = selectedProjectIDs
        dragAnchorProjectID = nil
        DispatchQueue.main.async {
            selectedProjectIDs = finalSelection
        }
    }

    private func projectNearest(to point: CGPoint) -> UUID? {
        projectRowFrames.min { lhs, rhs in
            abs(lhs.value.midY - point.y) < abs(rhs.value.midY - point.y)
        }?.key
    }
}

private struct ProjectRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ProjectSidebarRow: View {
    @EnvironmentObject private var store: AppStore
    let project: Project
    let isSelected: Bool
    let onRename: (String) -> Void
    let onSelectionDragChanged: (DragGesture.Value) -> Void
    let onSelectionDragEnded: (DragGesture.Value) -> Void
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 7) {
            ReorderHandle(help: "Drag to reorder this project")
                .draggable(ProjectDragPayload(projectID: project.id))
            HStack(spacing: 0) {
                EditableLabel(text: project.name, systemImage: "folder", onChange: onRename)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("project-list"))
                    .onChanged(onSelectionDragChanged)
                    .onEnded(onSelectionDragEnded)
            )
        }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.28) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .dropDestination(for: ProjectDragPayload.self) { payloads, location in
                guard let sourceID = payloads.first?.projectID, sourceID != project.id else { return false }
                store.moveProject(
                    sourceID,
                    relativeTo: project.id,
                    placement: location.y < 16 ? .before : .after
                )
                return true
            } isTargeted: { isDropTarget = $0 }
    }
}

private struct TodoListSidebarRow: View {
    @EnvironmentObject private var store: AppStore
    let list: TodoList
    let projectID: UUID
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 8) {
            ReorderHandle(help: "Drag to reorder this list")
                .draggable(ListDragPayload(projectID: projectID, listID: list.id))
            CompletionButton(isCompleted: list.isCompleted) {
                store.setListCompletion(list.id, completed: !list.isCompleted)
            }
            EditableLabel(text: list.title) {
                store.renameList(list.id, to: $0)
            }
            Spacer(minLength: 4)
            Text("\(list.items.filter { $0.completedAt != nil }.count)/\(list.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .dropDestination(for: ListDragPayload.self) { payloads, location in
            guard let payload = payloads.first,
                  payload.projectID == projectID,
                  payload.listID != list.id else { return false }
            store.moveList(
                payload.listID,
                relativeTo: list.id,
                placement: location.y < 18 ? .before : .after
            )
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}

private struct ListHeader: View {
    @EnvironmentObject private var store: AppStore
    let list: TodoList

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CompletionButton(isCompleted: list.isCompleted) {
                    store.setListCompletion(list.id, completed: !list.isCompleted)
                }
                EditableLabel(text: list.title, font: .largeTitle.bold()) {
                    store.renameList(list.id, to: $0)
                }
            }
            HStack(spacing: 16) {
                Text("Created \(list.timestampStyle.format(list.createdAt))")
                if let completedAt = list.completedAt {
                    Text("Completed \(list.timestampStyle.format(completedAt))")
                }
                Spacer()
                Picker("Timestamps", selection: Binding(
                    get: { list.timestampStyle },
                    set: { store.setTimestampStyle(list.id, style: $0) }
                )) {
                    ForEach(TimestampStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var store: AppStore
    let list: TodoList
    let item: TaskItem
    let depth: Int
    @State private var isExpanded = true
    @State private var isDropTarget = false

    private var children: [TaskItem] { list.children(of: item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                if children.isEmpty {
                    Color.clear
                        .frame(width: 14, height: 20)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 14, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(isExpanded ? "Collapse sub-items" : "Expand sub-items")
                    .floatingHelp(isExpanded ? "Collapse sub-items" : "Expand sub-items")
                }
                ReorderHandle(help: "Drag to reorder; drop in the center of another task to nest it")
                    .draggable(TaskDragPayload(listID: list.id, itemID: item.id))
                CompletionButton(isCompleted: item.isCompleted) {
                    store.setItemCompletion(in: list.id, itemID: item.id, completed: !item.isCompleted)
                }
                EditableLabel(
                    text: item.title,
                    font: depth == 0 ? .body.weight(.medium) : .body,
                    isStruckThrough: item.isCompleted,
                    onChange: { store.renameItem(in: list.id, itemID: item.id, to: $0) }
                )
                Spacer()
                Text(item.timestampStyleText(using: list.timestampStyle))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button {
                    isExpanded = true
                    store.addItem(to: list.id, parentID: item.id)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .floatingHelp("Add a sub-item")
                Button(role: .destructive) {
                    store.deleteItem(in: list.id, itemID: item.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .floatingHelp("Delete this item and its sub-items")
            }
            .padding(.leading, CGFloat(depth) * 26)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(depth == 0 ? Color.secondary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .dropDestination(for: TaskDragPayload.self) { payloads, location in
                guard let payload = payloads.first,
                      payload.listID == list.id,
                      payload.itemID != item.id else { return false }
                let placement = dropPlacement(at: location)
                if placement == .inside { isExpanded = true }
                store.moveItem(
                    in: list.id,
                    itemID: payload.itemID,
                    relativeTo: item.id,
                    placement: placement
                )
                return true
            } isTargeted: { isDropTarget = $0 }

            if isExpanded {
                ForEach(children) { child in
                    TaskRow(list: list, item: child, depth: depth + 1)
                }
            }
        }
    }

    private func dropPlacement(at location: CGPoint) -> TaskDropPlacement {
        if location.y < 14 { return .before }
        if location.y > 32 { return .after }
        return .inside
    }
}

private struct ReorderHandle: View {
    let help: String

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(width: 14, height: 20)
            .contentShape(Rectangle())
            .accessibilityLabel(help)
            .floatingHelp(help)
    }
}

private struct CompletionButton: View {
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isCompleted ? "✅" : "○")
                .font(isCompleted ? .body : .title3)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted ? "Mark incomplete" : "Mark complete")
        .floatingHelp(isCompleted ? "Mark incomplete" : "Mark complete")
    }
}

private struct QuickAddRow: View {
    @EnvironmentObject private var store: AppStore
    let listID: UUID
    @State private var title = ""

    var body: some View {
        HStack(spacing: 10) {
            TextField("Add something to this list…", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button(action: add) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(cleanedTitle.isEmpty)
            .floatingHelp("Add this item to the current list")
        }
    }

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        guard !cleanedTitle.isEmpty else { return }
        store.addItem(to: listID, titled: cleanedTitle)
        title = ""
    }
}

private extension View {
    func floatingHelp(_ text: String) -> some View {
        help(text)
    }
}

private struct DoubleClickCreationArea: View {
    let prompt: String
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 320)
            .contentShape(Rectangle())
            .gesture(
                TapGesture(count: 2)
                    .onEnded(onDoubleClick)
                    .exclusively(before: TapGesture().onEnded(onSingleClick))
            )
            .accessibilityLabel(prompt)
            .help(prompt)
    }
}

private struct EditableLabel: View {
    let text: String
    var systemImage: String?
    var font: Font = .body
    var isStruckThrough = false
    let onChange: (String) -> Void

    @State private var draft = ""
    @State private var isEditing = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage { Image(systemName: systemImage) }
            if isEditing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .strikethrough(isStruckThrough)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .shadow(color: Color.accentColor.opacity(0.18), radius: 2)
                    .focused($isFieldFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
            } else {
                Text(text)
                    .font(font)
                    .strikethrough(isStruckThrough)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
                    .help("Double-click to rename")
            }
        }
        .onChange(of: text) {
            if !isEditing { draft = text }
        }
        .onChange(of: isFieldFocused) {
            if isEditing && !isFieldFocused { commit() }
        }
        .onAppear { draft = text }
        .onDisappear(perform: commit)
    }

    private func beginEditing() {
        draft = text
        isEditing = true
        DispatchQueue.main.async { isFieldFocused = true }
    }

    private func commit() {
        let cleaned = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, cleaned != text { onChange(cleaned) }
        isEditing = false
    }

    private func cancel() {
        draft = text
        isEditing = false
    }
}

private extension TaskItem {
    func timestampStyleText(using style: TimestampStyle) -> String {
        if let completedAt { return "Done \(style.format(completedAt))" }
        return "Added \(style.format(createdAt))"
    }
}
