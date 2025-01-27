import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import PDFKit
import Combine

/** Csv data structure

 ``Csv`` is a struct to store information to parse csv into table.

 ``Csv`` automatically recognize first row as column and others as rows.

 ```swift
 let rawCsv = """
 a,b,c
 1,2,3
 4,5,6
 7,8,9
 10,11,12
 """
 let csv = Csv.loadFromString(rawCsv)
 Output:
 | a  | b  | c  |
 | 1  | 2  | 3  |
 | 4  | 5  | 6  |
 | 7  | 8  | 9  |
 | 10 | 11 | 12 |
 ```
 */
public actor Csv {

    /// initialization
    ///
    /// `separator` is applied to each row and generate items per row.
    /// `columns` is array of column whose type is ``Column``.
    /// `Row` is array of row whose type is ``Row``    
    public init(
        separator: String=",",
        rawString: String? = nil,
        columns: [Csv.Column] = [],
        rows: [Csv.Row] = [],
        exportType: ExportType = .png
    ) {
        self.imageMarker = ImageMaker(maximumRowCount: maximumRowCount, fontSize: 12)
        self.pdfMarker = PdfMaker(
            maximumRowCount: maximumRowCount,
            fontSize: 12,
            metadata: PDFMetadata(
                author: "Author",
                title: "Title"
            )
        )
        self.separator = separator
        self.rawString = rawString
        self.columns = columns
        self.rows = rows
        self.exportType = exportType
    }

    /// A flag whether ``Csv`` is loading contents or not
    public var isLoading: Bool {
        isLoadingSubject.value
    }

    /// A `Publisher` to send ``isLoading``.
    nonisolated public var isLoadingPublisher: AnyPublisher<Bool, Never> {
        isLoadingSubject.eraseToAnyPublisher()
    }

    /// `CurrentValueSubject` to store ``isLoading``.
    private let isLoadingSubject: CurrentValueSubject<Bool, Never> = .init(false)


    /// progress stores current completeFraction of convert
    /// Value is in `0...1` with `Double` type
    public var progress: Double {
        progressSubject.value
    }

    /// A `Publisher` to send ``progress``.
    nonisolated public var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    /// `CurrentValueSubject` to store ``progress``.
    private let progressSubject: CurrentValueSubject<Double, Never> = .init(0)

    /// an separator applied to each row and column
    public var separator: String

    /// an array of ``Column``
    public var columns: [Column]

    /// an array of row whose type is ``Row`.
    public var rows: [Row]

    /// ``ImageMarker`` has responsibility to generate png-image from csv
    private let imageMarker: ImageMaker

    /// ``PdfMaker`` has responsibility to generate pdf-image from csv
    private let pdfMarker: PdfMaker

    /// `rawString` is original String read from Resource (either Local or Network)
    public var rawString: String?

    /// `exportType` determines export type. Please choose ``ExportType.png`` or ``ExportType.pdf``.
    public var exportType: ExportType

    /// ``maximumRowCount`` is the max number of Rows. this is fixed due to performance issue.
    private let maximumRowCount: Int? = nil

    private let queue = DispatchQueue(label: "dev.fummicc1.csv2img.csv-queue")

    // MARK: Internal update functions
    /// Internal method to update `Array<Row>`
    func update(rows: [Row]) {
        self.rows = rows
    }
    /// Internal method to update `Array<Column>`
    func update(columns: [Column]) {
        self.columns = columns
    }
}

extension Csv {
    /**
     `ExportType` is a enum that expresses
     */
    public enum ExportType: String, Hashable {
        /// `png` output
        case png
        /// `pdf` output (Work In Progress)
        case pdf

        public var fileExtension: String {
            self.rawValue
        }

        public var utType: UTType {
            switch self {
            case .png:
                return .png
            case .pdf:
                return .pdf
            }
        }
    }
}

extension Csv {

    /// Generate `Csv` from `String` data.
    ///
    /// You cloud call `Csv.loadFromString` if you can own raw-CSV data.
    ///
    /// ```swift
    /// let rawCsv = """
    /// a,b,c
    /// 1,2,3
    /// 4,5,6
    /// 7,8,9
    /// 10,11,12
    /// """
    /// let csv = Csv.loadFromString(rawCsv)
    /// Output:
    /// | a  | b  | c  |
    /// | 1  | 2  | 3  |
    /// | 4  | 5  | 6  |
    /// | 7  | 8  | 9  |
    /// | 10 | 11 | 12 |
    ///```
    ///
    /// You cloud change separator by giving value to `separator` parameter.
    ///
    ///```swift
    /// let dotSeparated = """
    /// a.b.c
    /// 1.2.3
    /// 4.5.6
    /// 7.8.9
    /// """
    /// let csv = Csv.loadFromString(dotSeparated, separator: ".")
    /// Output:
    /// | a  | b  | c  |
    /// | 1  | 2  | 3  |
    /// | 4  | 5  | 6  |
    /// | 7  | 8  | 9  |
    /// | 10 | 11 | 12 |
    /// ```
    ///
    /// If certain row-item is very long, you could trim it with `maxLength`-th length.
    ///
    ///```swift
    /// let longCsv = """
    /// a.b.c
    /// 1.2.33333333333333333333333333333333333333333
    /// 4.5.6
    /// 7.8.9
    /// """
    /// let csv = Csv.loadFromString(dotSeparated, separator: ".", maxLength: 7)
    /// Output:
    /// | a  | b  | c        |
    /// | 1  | 2  | 3333333  |
    /// | 4  | 5  | 6        |
    /// | 7  | 8  | 9        |
    /// | 10 | 11 | 12       |
    /// ```
    ///
    /// - Parameters:
    ///     - str: Row String
    ///     - separator: Default separator in a row is `","`. You cloud change it by giving separator to `separator` parameter.
    ///     - maxLength: Default value is nil. if `maxLength` is not nil, every row-item length is limited by `maxLength`.
    ///     - exportType: Default `exportType` is `.png`. If you use too big image size, I strongly recommend use `.pdf` instead.
    public static func loadFromString(
        _ str: String,
        separator: String = ",",
        maxLength: Int? = nil,
        exportType: ExportType = .png
    ) -> Csv {
        var lines = str
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .filter({ !$0.isEmpty })
        var columns: [Csv.Column] = []
        var rows: [Row] = []

        if lines.count == 1 {
            let count = lines[0]
                .split(separator: Character(separator), omittingEmptySubsequences: false)
                .count
            let columns = (0..<count).map { String($0) }
            lines.insert(columns.joined(separator: separator), at: 0)
        }

        for (i, line) in lines.enumerated() {
            var items = line
                .split(separator: Character(separator), omittingEmptySubsequences: false)
                .map({ String($0) })
            if i == 0 {
                let columnCount = items.count
                let styles = Column.Style.random(count: columnCount)
                columns = items.enumerated().map { (i, name) in
                    return Column(
                        name: name,
                        style: styles[i])
                }
            } else {
                items = items.enumerated().compactMap { (index, item) in
                    let str: String
                    if let maxLength = maxLength, item.count > maxLength {
                        str = String(item.prefix(maxLength)) + "..."
                    } else {
                        str = item
                    }
                    return str
                }
                let row = Row(
                    index: i,
                    values: items
                )
                rows.append(row)
            }
        }
        return Csv(
            separator: separator,
            rawString: str,
            columns: columns,
            rows: rows,
            exportType: .pdf
        )
    }

    /// Generate `Csv` from network url (like `HTTPS`).
    ///
    /// - Parameters:
    ///     - url: Network url, commonly `HTTPS` schema.
    ///     - separator: Default `separator` in a row is `","`. You cloud change it by giving separator to `separator` parameter.
    ///     - exportType: Default `exportType` is `.png`. If you use too big image size, I strongly recommend use `.pdf` instead.
    public static func loadFromNetwork(
        _ url: URL,
        separator: String = ",",
        exportType: ExportType = .png
    ) throws -> Csv {
        let data = try Data(contentsOf: url)
        let str: String
        if let _str = String(data: data, encoding: .utf8) {
            str = _str
        } else if let _str = String(data: data, encoding: .utf16) {
            str = _str
        } else if let _str = String(data: data, encoding: .utf32) {
            str = _str
        } else if let _str = String(data: data, encoding: .ascii) {
            str = _str
        } else {
            throw Error.invalidDownloadResource(url: url.absoluteString, data: data)
        }
        return Csv.loadFromString(str, separator: separator)
    }

    /// Generate `Csv` from local disk url (like `file://Users/...`).
    ///
    /// - Parameters:
    ///     - file: Local disk url, commonly starts from `file://` schema. Relative-path method is not allowed, please specify by absolute-path method.
    ///     - separator: Default `separator` in a row is `","`. You cloud change it by giving separator to `separator` parameter.
    ///     - checkAccessSecurityScope: This flag is effective to only macOS. If you want to check local-file is securely accessible from this app, make this flat `true`. Default value if `false` which does not check the file access-security-scope.
    ///     - exportType: Default `exportType` is `.png`. If you use too big image size, I strongly recommend use `.pdf` instead.
    public static func loadFromDisk(
        _ file: URL,
        separator: String = ",",
        checkAccessSecurityScope: Bool = false,
        exportType: ExportType = .png
    ) throws -> Csv {
        // https://www.hackingwithswift.com/forums/swift/accessing-files-from-the-files-app/8203
        if !checkAccessSecurityScope || file.startAccessingSecurityScopedResource() {
            let data = try Data(contentsOf: file)
            let str: String
            if let _str = String(data: data, encoding: .utf8) {
                str = _str
            } else if let _str = String(data: data, encoding: .utf16) {
                str = _str
            } else if let _str = String(data: data, encoding: .utf32) {
                str = _str
            } else if let _str = String(data: data, encoding: .ascii) {
                str = _str
            } else {
                throw Error.invalidLocalResource(url: file.absoluteString, data: data)
            }
            return Csv.loadFromString(str, separator: separator)
        }
        throw Error.cannotAccessFile(url: file.absoluteString)
    }

    /**
     Generate Output (file-type is determined by `exportType` parameter)
     - Parameters:
     - fontSize: Determine the fontsize of characters in output-table image.
     - exportType:Determine file-extension. Type is ``ExportType`` and default value is ``ExportType.png``. If you use too big image size, I strongly recommend use `.pdf` instead.
     - Note:
     `fontSize` determines the size of output image and it can be as large as you want. Please consider the case that output image is too large to open image. Although output image becomes large, it is recommended to set fontSize amply enough (maybe larger than `12pt`) to see image clearly.
     - Returns: ``CsvExportable``. (either ``CGImage`` or  ``PdfDocument``).
     - Throws: Throws ``Csv.Error``.
     */
    public func generate(
        fontSize: Double? = nil,
        exportType: ExportType = .png
    ) async throws -> AnyCsvExportable {
        if isLoading {
            throw Csv.Error.workInProgress
        }
        isLoadingSubject.value = true
        progressSubject.value = 0
        defer {
            isLoadingSubject.value = false
        }
        if columns.isEmpty || rows.isEmpty {
            throw Csv.Error.emptyData
        }
        self.exportType = exportType
        var maker: Any?
        switch exportType {
        case .png:
            maker = self.imageMarker
        case .pdf:
            maker = self.pdfMarker
        }
        if let maker = maker as? ImageMaker {
            if let fontSize = fontSize {
                maker.setFontSize(fontSize)
            }
            // TODO: When Swift5.7 is supported officailly, replace `CGImage` with `any CsvExportable`.
            let exportable: CGImage = try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self = self else {
                        continuation.resume(throwing: Csv.Error.underlying(nil))
                        return
                    }
                    Task {
                        do {
                            let img = try maker.make(columns: await self.columns, rows: await self.rows) { progress in
                                self.progressSubject.value = progress
                            }
                            continuation.resume(returning: img)
                        } catch {
                            continuation.resume(throwing: Csv.Error.underlying(error))
                        }
                    }
                }
            }
            return AnyCsvExportable(exportable)
        } else if let maker = maker as? PdfMaker {
            if let fontSize = fontSize {
                maker.setFontSize(fontSize)
            }
            let exportable: PDFDocument = try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self = self else {
                        continuation.resume(throwing: Csv.Error.underlying(nil))
                        return
                    }
                    Task {
                        do {
                            let doc = try maker.make(columns: await self.columns, rows: await self.rows) { progress in
                                self.progressSubject.value = progress
                            }
                            continuation.resume(returning: doc)
                        } catch {
                            continuation.resume(throwing: Csv.Error.underlying(error))
                        }
                    }
                }
            }
            return AnyCsvExportable(exportable)
        }
        throw Error.invalidExportType(exportType)
    }

    /**
     - parameters:
     - to url: local file path where [png, pdf] image will be saved.
     - Returns: If saving csv image to file, returns `true`. Otherwise, return `False`.
     */
    public func write(to url: URL) -> Data? {
        let data: Data?
        if exportType == .png {
            data = imageMarker.latestOutput?.convertToData()
        } else if exportType == .pdf {
            pdfMarker.latestOutput?.write(to: url)
            return pdfMarker.latestOutput?.dataRepresentation()
        } else {
            data = nil
        }
        guard let data = data else {
            return nil
        }
        do {
            if !FileManager.default.fileExists(atPath: url.absoluteString) {
                FileManager.default.createFile(atPath: url.absoluteString, contents: data)
            } else {
                try data.write(to: url)
            }
            return data
        } catch {
            print(error)
            return nil
        }
    }
}
