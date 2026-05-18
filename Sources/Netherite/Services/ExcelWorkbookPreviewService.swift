import Foundation

struct ExcelWorkbookPreview: Sendable, Equatable {
    let sheets: [ExcelSheetPreview]
}

struct ExcelSheetPreview: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let rows: [ExcelRowPreview]
    let columnCount: Int
    let truncatedRows: Bool
    let truncatedColumns: Bool

    var isEmpty: Bool {
        rows.allSatisfy { row in
            row.values.allSatisfy(\.isEmpty)
        }
    }
}

struct ExcelRowPreview: Identifiable, Sendable, Equatable {
    let rowIndex: Int
    let values: [String]

    var id: Int { rowIndex }
}

enum ExcelWorkbookPreviewError: LocalizedError, Sendable {
    case unsupportedExtension(String)
    case extractionFailed(String)
    case missingWorkbook
    case missingSheets
    case xmlParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(fileExtension):
            "Only Open XML Excel workbooks (.xlsx, .xlsm, .xltx, .xltm) can be previewed here. This file is .\(fileExtension)."
        case let .extractionFailed(detail):
            "Could not unpack this workbook: \(detail)"
        case .missingWorkbook:
            "This workbook is missing xl/workbook.xml."
        case .missingSheets:
            "No readable worksheets were found in this workbook."
        case let .xmlParsingFailed(detail):
            "Could not read workbook XML: \(detail)"
        }
    }
}

enum ExcelWorkbookPreviewService {
    private static let previewableExtensions: Set<String> = ["xlsx", "xlxs", "xlsm", "xltx", "xltm"]

    static func load(url: URL, maxRows: Int = 250, maxColumns: Int = 60) throws -> ExcelWorkbookPreview {
        let fileExtension = url.pathExtension.lowercased()
        guard previewableExtensions.contains(fileExtension) else {
            throw ExcelWorkbookPreviewError.unsupportedExtension(fileExtension.isEmpty ? "unknown" : fileExtension)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetheriteExcelPreview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try ProcessRunner.run(arguments: [
                "/usr/bin/ditto",
                "-x", "-k", "--noqtn",
                url.path,
                tempURL.path
            ])
        } catch let error as ProcessRunnerError {
            if case let .failed(_, result) = error {
                throw ExcelWorkbookPreviewError.extractionFailed(result.output.trimmed)
            }
            throw error
        }

        return try loadUnpackedWorkbook(at: tempURL, maxRows: maxRows, maxColumns: maxColumns)
    }

    private static func loadUnpackedWorkbook(at packageRoot: URL, maxRows: Int, maxColumns: Int) throws -> ExcelWorkbookPreview {
        let workbookURL = packageRoot.appendingPathComponent("xl/workbook.xml")
        guard FileManager.default.fileExists(atPath: workbookURL.path) else {
            throw ExcelWorkbookPreviewError.missingWorkbook
        }

        let workbookParser = WorkbookXMLParser()
        try parseXML(at: workbookURL, delegate: workbookParser)

        let relationshipsURL = packageRoot.appendingPathComponent("xl/_rels/workbook.xml.rels")
        let relationshipTargets: [String: String]
        if FileManager.default.fileExists(atPath: relationshipsURL.path) {
            let parser = WorkbookRelationshipXMLParser()
            try parseXML(at: relationshipsURL, delegate: parser)
            relationshipTargets = parser.targetsByID
        } else {
            relationshipTargets = [:]
        }

        let sharedStringsURL = packageRoot.appendingPathComponent("xl/sharedStrings.xml")
        let sharedStrings: [String]
        if FileManager.default.fileExists(atPath: sharedStringsURL.path) {
            let parser = SharedStringsXMLParser()
            try parseXML(at: sharedStringsURL, delegate: parser)
            sharedStrings = parser.strings
        } else {
            sharedStrings = []
        }

        let sheets = try workbookParser.sheets.compactMap { sheetReference -> ExcelSheetPreview? in
            let target = relationshipTargets[sheetReference.relationshipID] ?? "worksheets/sheet\(sheetReference.sheetID).xml"
            let sheetURL = resolveWorkbookTarget(target, packageRoot: packageRoot)
            guard FileManager.default.fileExists(atPath: sheetURL.path) else { return nil }

            let parser = WorksheetXMLParser(
                sheetID: sheetReference.relationshipID,
                sheetName: sheetReference.name,
                sharedStrings: sharedStrings,
                maxRows: maxRows,
                maxColumns: maxColumns
            )
            try parseXML(at: sheetURL, delegate: parser)
            return parser.sheet
        }

        guard !sheets.isEmpty else {
            throw ExcelWorkbookPreviewError.missingSheets
        }

        return ExcelWorkbookPreview(sheets: sheets)
    }

    private static func parseXML(at url: URL, delegate: XMLParserDelegate) throws {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? url.lastPathComponent
            throw ExcelWorkbookPreviewError.xmlParsingFailed(detail)
        }
    }

    private static func resolveWorkbookTarget(_ target: String, packageRoot: URL) -> URL {
        let normalizedTarget = target.replacingOccurrences(of: "\\", with: "/")
        if normalizedTarget.hasPrefix("/") {
            return packageRoot.appendingPathComponent(String(normalizedTarget.dropFirst()))
        }
        return packageRoot.appendingPathComponent("xl").appendingPathComponent(normalizedTarget)
    }
}

enum ExcelColumnName {
    static func name(for zeroBasedIndex: Int) -> String {
        var index = zeroBasedIndex + 1
        var name = ""

        while index > 0 {
            let remainder = (index - 1) % 26
            let scalar = UnicodeScalar(65 + remainder)!
            name.insert(Character(scalar), at: name.startIndex)
            index = (index - 1) / 26
        }

        return name
    }

    static func zeroBasedIndex(from cellReference: String) -> Int? {
        var columnNumber = 0
        var foundLetter = false

        for scalar in cellReference.unicodeScalars {
            let value = scalar.value
            let uppercase = value >= 97 && value <= 122 ? value - 32 : value
            guard uppercase >= 65 && uppercase <= 90 else {
                break
            }
            foundLetter = true
            columnNumber = columnNumber * 26 + Int(uppercase - 64)
        }

        return foundLetter ? columnNumber - 1 : nil
    }
}

private struct WorkbookSheetReference {
    let name: String
    let sheetID: String
    let relationshipID: String
}

private final class WorkbookXMLParser: NSObject, XMLParserDelegate {
    private(set) var sheets: [WorkbookSheetReference] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.localXMLName == "sheet",
              let name = attributeDict.xmlAttribute(named: "name"),
              let sheetID = attributeDict.xmlAttribute(named: "sheetId"),
              let relationshipID = attributeDict.xmlAttribute(named: "id")
        else {
            return
        }

        sheets.append(
            WorkbookSheetReference(
                name: name,
                sheetID: sheetID,
                relationshipID: relationshipID
            )
        )
    }
}

private final class WorkbookRelationshipXMLParser: NSObject, XMLParserDelegate {
    private(set) var targetsByID: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.localXMLName == "Relationship",
              let id = attributeDict.xmlAttribute(named: "Id"),
              let target = attributeDict.xmlAttribute(named: "Target")
        else {
            return
        }

        targetsByID[id] = target
    }
}

private final class SharedStringsXMLParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var isInsideSharedString = false
    private var isCollectingText = false
    private var currentString = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.localXMLName {
        case "si":
            isInsideSharedString = true
            currentString = ""
        case "t" where isInsideSharedString:
            isCollectingText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCollectingText else { return }
        currentString += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.localXMLName {
        case "t":
            isCollectingText = false
        case "si":
            strings.append(currentString)
            currentString = ""
            isInsideSharedString = false
        default:
            break
        }
    }
}

private final class WorksheetXMLParser: NSObject, XMLParserDelegate {
    let sheetID: String
    let sheetName: String
    let sharedStrings: [String]
    let maxRows: Int
    let maxColumns: Int

    private var rows: [ExcelRowPreview] = []
    private var currentRowIndex = 0
    private var currentRowValues: [Int: String] = [:]
    private var currentRowIsVisible = false
    private var currentCellColumnIndex: Int?
    private var currentCellType = ""
    private var currentCellValue = ""
    private var currentCellInlineText = ""
    private var currentCellFormula = ""
    private var isCollectingValue = false
    private var isCollectingInlineText = false
    private var isCollectingFormula = false
    private var displayedColumnCount = 0
    private var sawRowBeyondLimit = false
    private var sawColumnBeyondLimit = false

    init(sheetID: String, sheetName: String, sharedStrings: [String], maxRows: Int, maxColumns: Int) {
        self.sheetID = sheetID
        self.sheetName = sheetName
        self.sharedStrings = sharedStrings
        self.maxRows = maxRows
        self.maxColumns = maxColumns
    }

    var sheet: ExcelSheetPreview {
        ExcelSheetPreview(
            id: sheetID,
            name: sheetName,
            rows: rows,
            columnCount: displayedColumnCount,
            truncatedRows: sawRowBeyondLimit,
            truncatedColumns: sawColumnBeyondLimit
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.localXMLName {
        case "row":
            currentRowIndex = Int(attributeDict.xmlAttribute(named: "r") ?? "") ?? currentRowIndex + 1
            currentRowValues = [:]
            currentRowIsVisible = rows.count < maxRows
            if !currentRowIsVisible {
                sawRowBeyondLimit = true
            }

        case "c":
            startCell(attributes: attributeDict)

        case "v" where currentCellColumnIndex != nil:
            currentCellValue = ""
            isCollectingValue = true

        case "f" where currentCellColumnIndex != nil:
            currentCellFormula = ""
            isCollectingFormula = true

        case "t" where currentCellColumnIndex != nil && currentCellType == "inlineStr":
            isCollectingInlineText = true

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingValue {
            currentCellValue += string
        } else if isCollectingInlineText {
            currentCellInlineText += string
        } else if isCollectingFormula {
            currentCellFormula += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.localXMLName {
        case "v":
            isCollectingValue = false
        case "f":
            isCollectingFormula = false
        case "t":
            isCollectingInlineText = false
        case "c":
            finishCell()
        case "row":
            finishRow()
        default:
            break
        }
    }

    private func startCell(attributes: [String: String]) {
        currentCellColumnIndex = nil
        currentCellType = attributes.xmlAttribute(named: "t") ?? ""
        currentCellValue = ""
        currentCellInlineText = ""
        currentCellFormula = ""
        isCollectingValue = false
        isCollectingInlineText = false
        isCollectingFormula = false

        guard currentRowIsVisible else { return }

        let inferredColumn = currentRowValues.keys.max().map { $0 + 1 } ?? 0
        let columnIndex = attributes
            .xmlAttribute(named: "r")
            .flatMap(ExcelColumnName.zeroBasedIndex(from:)) ?? inferredColumn

        if columnIndex >= maxColumns {
            sawColumnBeyondLimit = true
            return
        }

        currentCellColumnIndex = columnIndex
        displayedColumnCount = max(displayedColumnCount, columnIndex + 1)
    }

    private func finishCell() {
        defer {
            currentCellColumnIndex = nil
            currentCellType = ""
            currentCellValue = ""
            currentCellInlineText = ""
            currentCellFormula = ""
        }

        guard let columnIndex = currentCellColumnIndex else { return }
        let displayValue = cellDisplayValue()
        guard !displayValue.isEmpty else { return }
        currentRowValues[columnIndex] = displayValue
    }

    private func finishRow() {
        defer {
            currentRowValues = [:]
            currentRowIsVisible = false
        }

        guard currentRowIsVisible else { return }
        guard !currentRowValues.isEmpty else { return }
        let rowColumnCount = min(maxColumns, max(displayedColumnCount, (currentRowValues.keys.max() ?? -1) + 1))

        let values = (0..<rowColumnCount).map { currentRowValues[$0] ?? "" }
        rows.append(ExcelRowPreview(rowIndex: currentRowIndex, values: values))
    }

    private func cellDisplayValue() -> String {
        let rawValue = currentCellValue.trimmed

        let value: String
        switch currentCellType {
        case "s":
            if let index = Int(rawValue), sharedStrings.indices.contains(index) {
                value = sharedStrings[index]
            } else {
                value = rawValue
            }
        case "b":
            value = rawValue == "1" ? "TRUE" : "FALSE"
        case "inlineStr":
            value = currentCellInlineText
        default:
            value = rawValue
        }

        if value.isEmpty, !currentCellFormula.trimmed.isEmpty {
            return "=\(currentCellFormula.trimmed)"
        }
        return value
    }
}

private extension String {
    var localXMLName: String {
        split(separator: ":", maxSplits: 1).last.map(String.init) ?? self
    }
}

private extension Dictionary where Key == String, Value == String {
    func xmlAttribute(named name: String) -> String? {
        if let exact = self[name] {
            return exact
        }

        return first { key, _ in
            key.localXMLName.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}
