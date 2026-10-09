import XCTest
@testable import JointTodoCore

final class CompletionTests: XCTestCase {
    func testCompletingParentCompletesDescendantsAndList() {
        var list = TodoList(title: "Chores")
        let parent = list.addItem(title: "Bathroom")
        let child = list.addItem(title: "Toilet", parentID: parent)

        list.setItemCompletion(parent, completed: true)

        XCTAssertTrue(list.items.first(where: { $0.id == parent })!.isCompleted)
        XCTAssertTrue(list.items.first(where: { $0.id == child })!.isCompleted)
        XCTAssertTrue(list.isCompleted)
    }

    func testCompletingAllChildrenCompletesParentAndList() {
        var list = TodoList(title: "Chores")
        let parent = list.addItem(title: "Bathroom")
        let childA = list.addItem(title: "Toilet", parentID: parent)
        let childB = list.addItem(title: "Vanity", parentID: parent)

        list.setItemCompletion(childA, completed: true)
        XCTAssertFalse(list.items.first(where: { $0.id == parent })!.isCompleted)
        XCTAssertFalse(list.isCompleted)

        list.setItemCompletion(childB, completed: true)
        XCTAssertTrue(list.items.first(where: { $0.id == parent })!.isCompleted)
        XCTAssertTrue(list.isCompleted)
    }

    func testUncheckingChildUnchecksAncestors() {
        var list = TodoList(title: "Chores")
        let parent = list.addItem(title: "Bathroom")
        let child = list.addItem(title: "Toilet", parentID: parent)
        list.setListCompletion(true)

        list.setItemCompletion(child, completed: false)

        XCTAssertFalse(list.items.first(where: { $0.id == parent })!.isCompleted)
        XCTAssertFalse(list.isCompleted)
    }

    func testMovingChildToRootPromotesAndReordersIt() throws {
        var list = TodoList(title: "Pipeline")
        let parent = list.addItem(title: "Canary")
        let child = list.addItem(title: "Tiny audience caps", parentID: parent)
        let sibling = list.addItem(title: "Benchmark")

        try list.moveItem(child, toParent: nil, at: 0)

        XCTAssertEqual(list.children(of: nil).map(\.id), [child, parent, sibling])
        XCTAssertNil(list.items.first(where: { $0.id == child })?.parentID)
    }

    func testMovingRootInsideAnotherTaskDemotesIt() throws {
        var list = TodoList(title: "Pipeline")
        let parent = list.addItem(title: "Canary")
        let task = list.addItem(title: "Audience caps")

        try list.moveItem(task, toParent: parent, at: 0)

        XCTAssertEqual(list.children(of: parent).map(\.id), [task])
        XCTAssertEqual(list.children(of: nil).map(\.id), [parent])
    }

    func testMovingTaskIntoDescendantIsRejected() throws {
        var list = TodoList(title: "Pipeline")
        let parent = list.addItem(title: "Canary")
        let child = list.addItem(title: "Audience caps", parentID: parent)

        XCTAssertThrowsError(try list.moveItem(parent, toParent: child, at: 0)) { error in
            XCTAssertEqual(error as? TaskMoveError, .cannotMoveIntoDescendant)
        }
    }
}
