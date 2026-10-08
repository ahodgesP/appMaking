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
}
