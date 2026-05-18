import Foundation

#if canImport(XCTest)
import XCTest
@testable import Netherite

final class WorkspaceSelectionBehaviorTests: XCTestCase {
    @MainActor
    func testPreviewSelectionReplacesCurrentFile() throws {
        let store = try makeStore(fileNames: ["Alpha.md", "Beta.md"])

        store.previewFile(id: "Alpha.md")
        XCTAssertEqual(store.selectedFileID, "Alpha.md")
        XCTAssertEqual(store.currentFile?.name, "Alpha.md")
        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md"])
        XCTAssertEqual(store.previewTabFileID, "Alpha.md")

        store.previewFile(id: "Beta.md")
        XCTAssertEqual(store.selectedFileID, "Beta.md")
        XCTAssertEqual(store.currentFile?.name, "Beta.md")
        XCTAssertEqual(store.openFileTabIDs, ["Beta.md"])
        XCTAssertEqual(store.previewTabFileID, "Beta.md")
    }

    @MainActor
    func testOpenFilePinsMultipleTabs() throws {
        let store = try makeStore(fileNames: ["Alpha.md", "Beta.md"])

        store.openFile("Alpha.md")
        store.openFile("Beta.md")

        XCTAssertEqual(store.selectedFileID, "Beta.md")
        XCTAssertEqual(store.currentFile?.name, "Beta.md")
        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md", "Beta.md"])
        XCTAssertNil(store.previewTabFileID)
    }

    @MainActor
    func testOpenFilePinsExistingPreviewTab() throws {
        let store = try makeStore(fileNames: ["Alpha.md"])

        store.previewFile(id: "Alpha.md")
        store.openFile("Alpha.md")

        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md"])
        XCTAssertNil(store.previewTabFileID)
    }

    @MainActor
    func testOpeningMissingFileKeepsCurrentSelection() throws {
        let store = try makeStore(fileNames: ["Alpha.md"])

        store.openFile("Alpha.md")
        store.openFile("Missing.md")

        XCTAssertEqual(store.selectedFileID, "Alpha.md")
        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md"])
    }

    @MainActor
    func testEditingSelectedFileMarksDocumentDirty() throws {
        let store = try makeStore(fileNames: ["Alpha.md"])

        store.openFile("Alpha.md")
        store.setDocumentText("# Edited\n")

        XCTAssertTrue(store.isDirty)
    }

    @MainActor
    func testEditingPreviewTabPinsIt() throws {
        let store = try makeStore(fileNames: ["Alpha.md"])

        store.previewFile(id: "Alpha.md")
        store.setDocumentText("# Edited\n")

        XCTAssertNil(store.previewTabFileID)
        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md"])
    }

    @MainActor
    func testCloseSelectedTabSelectsNextNeighbor() throws {
        let store = try makeStore(fileNames: ["Alpha.md", "Beta.md", "Gamma.md"])

        store.openFile("Alpha.md")
        store.openFile("Beta.md")
        store.openFile("Gamma.md")
        store.selectTab(fileID: "Beta.md")

        store.closeTab(fileID: "Beta.md")

        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md", "Gamma.md"])
        XCTAssertEqual(store.selectedFileID, "Gamma.md")
    }

    @MainActor
    func testCloseLastSelectedTabSelectsPreviousNeighbor() throws {
        let store = try makeStore(fileNames: ["Alpha.md", "Beta.md"])

        store.openFile("Alpha.md")
        store.openFile("Beta.md")

        store.closeCurrentTab()

        XCTAssertEqual(store.openFileTabIDs, ["Alpha.md"])
        XCTAssertEqual(store.selectedFileID, "Alpha.md")
    }

    @MainActor
    private func makeStore(fileNames: [String]) throws -> VaultStore {
        UserDefaults.standard.set(false, forKey: "launchReopensLastVault")

        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteWorkspaceSelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let files = try fileNames.map { fileName in
            let url = vaultURL.appendingPathComponent(fileName)
            try "# \(url.deletingPathExtension().lastPathComponent)\n".write(to: url, atomically: true, encoding: .utf8)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])

            return VaultFile(
                id: fileName,
                url: url,
                relativePath: fileName,
                name: fileName,
                fileExtension: url.pathExtension,
                kind: FileKind(fileExtension: url.pathExtension),
                byteCount: values.fileSize ?? 0,
                modifiedAt: values.contentModificationDate ?? Date.distantPast
            )
        }

        let store = VaultStore()
        store.vaultURL = vaultURL
        store.files = files
        return store
    }
}
#endif
