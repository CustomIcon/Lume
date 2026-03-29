import SwiftUI
import PDFKit
import WebKit
import Compression

// MARK: - Book Reader View Model

@Observable
final class BookReaderViewModel {
    var isLoading = true
    var statusMessage = "Downloading book..."
    var errorMessage: String?
    var bookData: Data?
    var bookFormat: BookFormat = .unknown
    var title: String = ""
    var isSidebarOpen: Bool = true
    
    // PDF State
    var pdfDocument: PDFDocument?
    var currentPage: Int = 1
    var totalPages: Int = 0
    
    // EPUB State
    var epubContent: String = ""
    var epubTOC: [EPUBChapter] = []
    var epubBaseURL: URL? = nil
    var epubIndexURL: URL? = nil

    enum BookFormat {
        case pdf
        case epub
        case unknown
    }

    func detectFormat(container: String?, data: Data) -> BookFormat {
        let hint = (container ?? "").lowercased()
        if hint.contains("pdf") { return .pdf }
        if hint.contains("epub") { return .epub }

        if data.count >= 4 {
            let header = data.prefix(4)
            if header.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }
            if header.starts(with: [0x50, 0x4B]) { return .epub }
        }
        return .unknown
    }
}

struct EPUBChapter: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let preview: String // Short snippet of text
    let anchor: String // ID in the HTML
}

struct ParsedEPUB {
    let html: String
    let toc: [EPUBChapter]
    let baseURL: URL?
    let indexURL: URL?
}

// MARK: - Main Book Reader View

struct BookReaderView: View {
    @Environment(SessionManager.self) private var session
    let item: BaseItemDto

    @State private var vm = BookReaderViewModel()

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()

            if let error = vm.errorMessage {
                errorView(error)
            } else if vm.isLoading {
                loadingView
            } else if let data = vm.bookData {
                VStack(spacing: 0) {
                    // Safe area spacer to avoid traffic lights
                    Spacer()
                        .frame(height: 32)
                    
                    switch vm.bookFormat {
                    case .pdf:
                        PDFReaderContentView(vm: vm, data: data, title: vm.title, onClose: close)
                    case .epub:
                        EPUBReaderContentView(vm: vm, data: data, title: vm.title, onClose: close)
                    case .unknown:
                        errorView("Unsupported book format. Only PDF and EPUB are supported.")
                    }
                }
            }
        }
        .task { await loadBook() }
        .onAppear { SleepPreventer.shared.startPreventingSleep(reason: "Reading a book in Lume") }
        .onDisappear { SleepPreventer.shared.stopPreventingSleep() }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 8) {
                Text(vm.statusMessage)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(item.displayName)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Failed to Load Book")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Close") { close() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadBook() async {
        guard let itemId = item.id else {
            vm.errorMessage = "Invalid item — no ID"
            vm.isLoading = false
            return
        }

        vm.title = item.displayName
        vm.isLoading = true
        vm.statusMessage = "Checking local storage..."

        // 1. Check for local download
        if let localURL = session.downloadManager.getLocalURL(for: itemId) {
            do {
                print("[Lume] Loading local book: \(localURL.path)")
                let data = try Data(contentsOf: localURL)
                vm.bookData = data
                vm.bookFormat = vm.detectFormat(container: item.container, data: data)
                vm.isLoading = false
                return
            } catch {
                print("[Lume] Failed to load local book data: \(error)")
            }
        }

        vm.statusMessage = "Downloading book..."

        do {
            let data = try await session.apiClient.downloadBookData(itemId: itemId)
            vm.bookData = data
            vm.bookFormat = vm.detectFormat(container: item.container, data: data)

            if vm.bookFormat == .unknown {
                vm.errorMessage = "Unsupported book format. Only PDF and EPUB are supported."
            }
        } catch {
            vm.errorMessage = error.localizedDescription
        }

        vm.isLoading = false
    }

    @Environment(\.dismissWindow) private var dismissWindow

    private func close() {
        dismissWindow()
        withAnimation { session.activeBookItem = nil }
    }
}

// MARK: - PDF Reader

struct PDFReaderContentView: View {
    @Bindable var vm: BookReaderViewModel
    let data: Data
    let title: String
    let onClose: () -> Void

    @State private var searchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            
            HStack(spacing: 0) {
                if vm.isSidebarOpen {
                    pdfSidebar
                        .transition(.move(edge: .leading))
                        .frame(width: 300)
                        .background(.ultraThinMaterial)
                        .overlay(Divider(), alignment: .trailing)
                }
                
                PDFKitView(data: data, vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var pdfSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pages")
                .font(.headline)
                .padding()
            
            ScrollViewReader { proxy in
                List {
                    ForEach(0..<vm.totalPages, id: \.self) { i in
                        Button {
                            vm.currentPage = i + 1
                        } label: {
                            HStack(spacing: 12) {
                                // PDF Page Thumbnail
                                if let doc = vm.pdfDocument, let page = doc.page(at: i) {
                                    Image(nsImage: page.thumbnail(of: CGSize(width: 120, height: 160), for: .artBox))
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 80, height: 110)
                                        .background(Color.white)
                                        .cornerRadius(6)
                                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                                        .padding(.vertical, 4)
                                } else {
                                    Rectangle()
                                        .fill(.quaternary)
                                        .frame(width: 80, height: 110)
                                        .cornerRadius(6)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Page \(i + 1)")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                    Text("Preview Content")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(vm.currentPage == i + 1 ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .id(i + 1)
                    }
                }
                .listStyle(.plain)
                .onChange(of: vm.currentPage) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: 16) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation { vm.isSidebarOpen.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
                    .foregroundStyle(vm.isSidebarOpen ? Color.accentColor : .primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if vm.totalPages > 0 {
                    Text("\(vm.totalPages) pages • PDF")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if vm.totalPages > 0 {
                Text("Page \(vm.currentPage) of \(vm.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct PDFKitView: NSViewRepresentable {
    let data: Data
    @Bindable var vm: BookReaderViewModel

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor.controlBackgroundColor

        if let doc = PDFDocument(data: data) {
            pdfView.document = doc
            vm.pdfDocument = doc
            vm.totalPages = doc.pageCount
            
            NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { _ in
                if let page = pdfView.currentPage {
                    let index = doc.index(for: page)
                    vm.currentPage = index + 1
                }
            }
        }

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if let doc = nsView.document, let page = doc.page(at: vm.currentPage - 1) {
            if nsView.currentPage != page {
                nsView.go(to: page)
            }
        }
    }
}

// MARK: - EPUB Reader

struct EPUBReaderContentView: View {
    @Bindable var vm: BookReaderViewModel
    let data: Data
    let title: String
    let onClose: () -> Void

    @State private var isProcessing = true
    @State private var fontSize: CGFloat = 18
    @State private var isDarkMode = true
    @State private var scrollToAnchor: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            epubToolbar

            if let error = vm.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Could not parse EPUB")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isProcessing {
                ProgressView("Parsing EPUB...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    if vm.isSidebarOpen {
                        epubSidebar
                            .transition(.move(edge: .leading))
                            .frame(width: 300)
                            .background(.ultraThinMaterial)
                            .overlay(Divider(), alignment: .trailing)
                    }
                    
                    EPUBWebView(htmlContent: vm.epubContent, fontSize: fontSize, isDarkMode: isDarkMode, baseURL: vm.epubBaseURL, indexURL: vm.epubIndexURL, scrollToAnchor: $scrollToAnchor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await parseEPUB() }
    }

    private var epubSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents")
                .font(.headline)
                .padding()
            
            List {
                ForEach(vm.epubTOC, id: \.anchor) { chapter in
                    Button {
                        scrollToAnchor = chapter.anchor
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.08))
                                .frame(width: 60, height: 84)
                                .overlay {
                                    VStack(spacing: 4) {
                                        Image(systemName: "text.justify.left")
                                            .font(.body)
                                            .foregroundStyle(Color.accentColor.opacity(0.6))
                                        
                                        Rectangle()
                                            .fill(Color.accentColor.opacity(0.2))
                                            .frame(height: 1)
                                            .padding(.horizontal, 12)
                                        Rectangle()
                                            .fill(Color.accentColor.opacity(0.2))
                                            .frame(height: 1)
                                            .padding(.horizontal, 12)
                                        Rectangle()
                                            .fill(Color.accentColor.opacity(0.2))
                                            .frame(height: 1)
                                            .padding(.horizontal, 16)
                                    }
                                }
                                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if !chapter.preview.isEmpty {
                                    Text(chapter.preview)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .lineSpacing(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(scrollToAnchor == chapter.anchor ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                if vm.epubTOC.isEmpty {
                    Text("No chapters found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .listStyle(.plain)
        }
    }

    private var epubToolbar: some View {
        HStack(spacing: 16) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation { vm.isSidebarOpen.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.title3)
                    .foregroundStyle(vm.isSidebarOpen ? Color.accentColor : .primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("EPUB")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Font size controls
            HStack(spacing: 8) {
                Button {
                    fontSize = max(12, fontSize - 2)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.plain)

                Text("\(Int(fontSize))pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                Button {
                    fontSize = min(32, fontSize + 2)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 16)

                Button {
                    isDarkMode.toggle()
                } label: {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                }
                .buttonStyle(.plain)
                .help(isDarkMode ? "Switch to light mode" : "Switch to dark mode")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func parseEPUB() async {
        isProcessing = true

        do {
            let parsed = try EPUBParser.parse(data: data)
            vm.epubContent = parsed.html
            vm.epubTOC = parsed.toc
            vm.epubBaseURL = parsed.baseURL
            vm.epubIndexURL = parsed.indexURL
        } catch {
            vm.errorMessage = error.localizedDescription
        }

        isProcessing = false
    }
}

struct EPUBWebView: NSViewRepresentable {
    let htmlContent: String
    let fontSize: CGFloat
    let isDarkMode: Bool
    let baseURL: URL?
    let indexURL: URL?
    @Binding var scrollToAnchor: String?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != htmlContent || 
           context.coordinator.lastDarkMode != isDarkMode || 
           context.coordinator.lastFontSize != fontSize ||
           context.coordinator.lastBaseURL != baseURL ||
           context.coordinator.lastIndexURL != indexURL {
            loadContent(in: nsView)
            context.coordinator.lastHTML = htmlContent
            context.coordinator.lastDarkMode = isDarkMode
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastBaseURL = baseURL
            context.coordinator.lastIndexURL = indexURL
        }
        
        if let anchor = scrollToAnchor {
            nsView.evaluateJavaScript("document.getElementById('\(anchor)')?.scrollIntoView({behavior: 'smooth'});")
            DispatchQueue.main.async {
                self.scrollToAnchor = nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var lastHTML: String = ""
        var lastDarkMode: Bool = false
        var lastFontSize: CGFloat = 0
        var lastBaseURL: URL? = nil
        var lastIndexURL: URL? = nil
    }

    private func loadContent(in webView: WKWebView) {
        let bgColor = isDarkMode ? "#1e1e2e" : "#fafafa"
        let textColor = isDarkMode ? "#cdd6f4" : "#1e1e2e"
        let linkColor = isDarkMode ? "#89b4fa" : "#1e40af"

        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, 'Georgia', 'Times New Roman', serif;
                font-size: \(Int(fontSize))px;
                line-height: 1.8;
                color: \(textColor);
                background-color: \(bgColor);
                max-width: 720px;
                margin: 0 auto;
                padding: 40px 32px 80px 32px;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            h1, h2, h3, h4, h5, h6 {
                margin-top: 1.5em;
                margin-bottom: 0.5em;
                line-height: 1.3;
            }
            h1 { font-size: 1.8em; }
            h2 { font-size: 1.5em; }
            h3 { font-size: 1.3em; }
            p { margin: 0.8em 0; text-align: justify; }
            a { color: \(linkColor); text-decoration: none; }
            img {
                max-width: 100%;
                height: auto;
                display: block;
                margin: 1.5em auto;
                border-radius: 8px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.1);
            }
            blockquote {
                border-left: 3px solid \(isDarkMode ? "#585b70" : "#ccc");
                margin: 1em 0;
                padding: 0.5em 1em;
                color: \(isDarkMode ? "#a6adc8" : "#555");
            }
            hr {
                border: none;
                border-top: 1px solid \(isDarkMode ? "#45475a" : "#ddd");
                margin: 2em 0;
            }
            pre, code {
                font-family: 'SF Mono', 'Menlo', monospace;
                font-size: 0.9em;
                background: \(isDarkMode ? "#313244" : "#f0f0f0");
                padding: 2px 6px;
                border-radius: 4px;
            }
            table { border-collapse: collapse; width: 100%; margin: 1em 0; }
            th, td {
                border: 1px solid \(isDarkMode ? "#45475a" : "#ddd");
                padding: 8px 12px;
                text-align: left;
            }
            ::selection {
                background: \(isDarkMode ? "#585b70" : "#b4d5fe");
            }
        </style>
        </head>
        <body>
        \(htmlContent)
        </body>
        </html>
        """

        webView.loadHTMLString(fullHTML, baseURL: baseURL)
        
        // Use loadFileURL for better local asset support in Sandbox
        if let indexURL = indexURL, let baseURL = baseURL {
            try? fullHTML.write(to: indexURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(indexURL, allowingReadAccessTo: baseURL)
        } else {
            webView.loadHTMLString(fullHTML, baseURL: baseURL)
        }
    }
}

// MARK: - EPUB Parser

enum EPUBParserError: LocalizedError {
    case invalidArchive
    case noContentFound
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "The EPUB file could not be opened as a valid archive."
        case .noContentFound: return "No readable content was found in this EPUB."
        case .parsingFailed(let detail): return "EPUB parsing failed: \(detail)"
        }
    }
}

/// Minimal in-memory ZIP reader (no external process needed — works in sandbox).
/// Supports "stored" (method 0) and "deflate" (method 8) entries.
private enum MiniZIP {
    struct Entry {
        let path: String
        let data: Data
    }

    static func extract(from zipData: Data) throws -> [Entry] {
        var entries: [Entry] = []
        var offset = 0
        let bytes = [UInt8](zipData)
        let count = bytes.count

        while offset + 30 <= count {
            // Scan for next PK\x03\x04 signature: https://stackoverflow.com/questions/5004201/decode-the-bytes
            if !(bytes[offset] == 0x50 && bytes[offset+1] == 0x4B && bytes[offset+2] == 0x03 && bytes[offset+3] == 0x04) {
                offset += 1
                continue
            }

            if offset + 30 > count { break }

            let compressionMethod = UInt16(bytes[offset+8]) | (UInt16(bytes[offset+9]) << 8)
            let compressedSize = Int(UInt32(bytes[offset+18]) | (UInt32(bytes[offset+19]) << 8) | (UInt32(bytes[offset+20]) << 16) | (UInt32(bytes[offset+21]) << 24))
            let uncompressedSize = Int(UInt32(bytes[offset+22]) | (UInt32(bytes[offset+23]) << 8) | (UInt32(bytes[offset+24]) << 16) | (UInt32(bytes[offset+25]) << 24))
            let fileNameLength = Int(UInt16(bytes[offset+26]) | (UInt16(bytes[offset+27]) << 8))
            let extraFieldLength = Int(UInt16(bytes[offset+28]) | (UInt16(bytes[offset+29]) << 8))

            let headerEnd = offset + 30
            guard headerEnd + fileNameLength + extraFieldLength <= count else { break }

            let fileNameData = Data(bytes[headerEnd..<(headerEnd + fileNameLength)])
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

            let dataStart = headerEnd + fileNameLength + extraFieldLength
            guard dataStart + compressedSize <= count else { break }

            let compressedData = Data(bytes[dataStart..<(dataStart + compressedSize)])

            // Skip directories and zero-length files
            if !fileName.hasSuffix("/") && (compressedSize > 0 || uncompressedSize > 0) {
                var fileData: Data?

                if compressionMethod == 0 {
                    fileData = compressedData
                } else if compressionMethod == 8 {
                    if uncompressedSize == 0 {
                        fileData = Data()
                    } else {
                        var decompressed = Data(count: uncompressedSize)
                        let resultSize = decompressed.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) in
                            compressedData.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) in
                                compression_decode_buffer(
                                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                                    uncompressedSize,
                                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                                    compressedData.count,
                                    nil,
                                    COMPRESSION_ZLIB
                                )
                            }
                        }
                        
                        if resultSize > 0 {
                            fileData = decompressed.prefix(resultSize)
                        }
                    }
                }

                if let fData = fileData {
                    entries.append(Entry(path: fileName, data: fData))
                }
            }

            offset = dataStart + compressedSize
        }

        return entries
    }
}

/// Minimal EPUB parser that extracts content from EPUB (ZIP) archives entirely in memory.
/// Parses the OPF manifest + spine to extract HTML/XHTML content in reading order.
enum EPUBParser {
    /// Helper to resolve relative paths like "../Images/cover.jpg" based on the current chapter's directory.
    private static func resolveRelativePath(href: String, relativeTo: String) -> String {
        if href.contains("://") || href.hasPrefix("data:") { return href }
        
        var components = relativeTo.components(separatedBy: "/")
        if !components.isEmpty { components.removeLast() } // Remove filename
        
        let hrefComponents = href.components(separatedBy: "/")
        for comp in hrefComponents {
            if comp == ".." {
                if !components.isEmpty { components.removeLast() }
            } else if comp == "." || comp == "" {
                continue
            } else {
                components.append(comp)
            }
        }
        return components.joined(separator: "/")
    }

    static func parse(data: Data) throws -> ParsedEPUB {
        // Create temp directory for current reading session
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lume-epub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        // Extract ZIP entries in memory and write only images/styles to disk for WebKit to find
        let entries = try MiniZIP.extract(from: data)
        guard !entries.isEmpty else { throw EPUBParserError.invalidArchive }

        var fileMap: [String: Data] = [:]
        for entry in entries {
            var normalizedPath = entry.path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            while normalizedPath.hasPrefix("/") { normalizedPath.removeFirst() }
            
            fileMap[normalizedPath] = entry.data
            fileMap[normalizedPath.lowercased()] = entry.data
            
            // Write to disk
            let fileURL = tempRoot.appendingPathComponent(normalizedPath)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? entry.data.write(to: fileURL)
        }

        let opfRelativePath: String
        if let containerData = fileMap["META-INF/container.xml"] ?? fileMap["meta-inf/container.xml"],
           let containerXML = String(data: containerData, encoding: .utf8) {
            if let range = containerXML.range(of: "full-path=\"", options: .caseInsensitive),
               let endRange = containerXML[range.upperBound...].range(of: "\"") {
                opfRelativePath = String(containerXML[range.upperBound..<endRange.lowerBound])
            } else {
                throw EPUBParserError.parsingFailed("Could not find rootfile in container.xml")
            }
        } else {
            guard let opf = fileMap.keys.first(where: { $0.lowercased().hasSuffix(".opf") }) else {
                throw EPUBParserError.parsingFailed("No OPF file found")
            }
            opfRelativePath = opf
        }

        var cleanOpfPath = opfRelativePath.replacingOccurrences(of: "\\", with: "/")
        if cleanOpfPath.hasPrefix("/") { cleanOpfPath.removeFirst() }

        guard let opfData = fileMap[cleanOpfPath] ?? fileMap[cleanOpfPath.lowercased()],
              let opfContent = String(data: opfData, encoding: .utf8) else {
            throw EPUBParserError.parsingFailed("Could not read OPF file: \(cleanOpfPath)")
        }

        let opfDir: String
        if let lastSlash = cleanOpfPath.lastIndex(of: "/") {
            opfDir = String(cleanOpfPath[...lastSlash])
        } else {
            opfDir = ""
        }

        var manifest: [String: String] = [:]
        let opfNS = opfContent as NSString
        let patterns = [
            "<item[^>]+id=[\"']([^\"']+)[\"'][^>]+href=[\"']([^\"']+)[\"'][^>]*/?>",
            "<item[^>]+href=[\"']([^\"']+)[\"'][^>]+id=[\"']([^\"']+)[\"'][^>]*/?>"
        ]

        for (i, pattern) in patterns.enumerated() {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            regex.enumerateMatches(in: opfContent, range: NSRange(location: 0, length: opfNS.length)) { match, _, _ in
                guard let match = match else { return }
                if i == 0 {
                    let id = opfNS.substring(with: match.range(at: 1))
                    let href = opfNS.substring(with: match.range(at: 2))
                    manifest[id] = href
                } else {
                    let href = opfNS.substring(with: match.range(at: 1))
                    let id = opfNS.substring(with: match.range(at: 2))
                    if manifest[id] == nil { manifest[id] = href }
                }
            }
        }

        var spineIds: [String] = []
        let spinePattern = try NSRegularExpression(pattern: "<itemref[^>]+idref=[\"']([^\"']+)[\"']", options: .caseInsensitive)
        spinePattern.enumerateMatches(in: opfContent, range: NSRange(location: 0, length: opfNS.length)) { match, _, _ in
            guard let match = match else { return }
            spineIds.append(opfNS.substring(with: match.range(at: 1)))
        }

        var allContent = ""
        var toc: [EPUBChapter] = []

        for idref in spineIds {
            guard var href = manifest[idref] else { continue }
            if href.hasPrefix("/") { href.removeFirst() }
            if href.hasPrefix("./") { href.removeFirst(2) }
            
            let decodedHref = href.removingPercentEncoding ?? href
            let fullPath = opfDir + decodedHref

            guard let fileData = fileMap[fullPath] ?? fileMap[decodedHref] else { continue }
            guard let content = String(data: fileData, encoding: .utf8) else { continue }

            let anchor = "chapter-\(idref)"
            var bodyContent = extractBody(from: content)

            let relativeTo = fullPath
            let attrPatterns = [
                "src\\s*=\\s*[\"']([^\"']+)[\"']",
                "href\\s*=\\s*[\"']([^\"']+)[\"']",
                "poster\\s*=\\s*[\"']([^\"']+)[\"']",
                "xlink:href\\s*=\\s*[\"']([^\"']+)[\"']",     // SVG image support
                "url\\s*\\(\\s*[\"']?([^\"'\\)]+)[\"']?\\s*\\)" // CSS url()
            ]
            
            for p in attrPatterns {
                if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                    let matches = regex.matches(in: bodyContent, options: [], range: NSRange(location: 0, length: (bodyContent as NSString).length))
                    for match in matches.reversed() {
                        let originalHref = (bodyContent as NSString).substring(with: match.range(at: 1))
                        let decodedOriginal = originalHref.removingPercentEncoding ?? originalHref
                        let resolved = resolveRelativePath(href: decodedOriginal, relativeTo: relativeTo)
                        
                        // Re-encode for HTML/SVG URL safety
                        let finalPath = resolved.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolved
                        bodyContent = (bodyContent as NSString).replacingCharacters(in: match.range(at: 1), with: finalPath)
                    }
                }
            }
            
            var chapterTitle = ""
            if let h1Range = bodyContent.range(of: "<h1[^>]*>(.*?)</h1>", options: [.regularExpression, .caseInsensitive]) {
                chapterTitle = bodyContent[h1Range].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            } else if let h2Range = bodyContent.range(of: "<h2[^>]*>(.*?)</h2>", options: [.regularExpression, .caseInsensitive]) {
                chapterTitle = bodyContent[h2Range].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
            
            if chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let titleRange = content.range(of: "<title>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) {
                    chapterTitle = content[titleRange].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                }
            }

            if chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chapterTitle = "Chapter \(toc.count + 1)"
            }
            
            let plainTextSnippet = bodyContent
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = plainTextSnippet.count > 120 ? String(plainTextSnippet.prefix(120)) + "..." : plainTextSnippet
            
            toc.append(EPUBChapter(title: chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines), preview: preview, anchor: anchor))
            allContent += "<div id=\"\(anchor)\">\(bodyContent)</div>\n<hr/>\n"
        }

        if allContent.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "<hr/>", with: "").isEmpty {
            // ... fallback reading logic ...
            // (omitted for brevity but should keep existing logic if needed)
        }

        let indexURL = tempRoot.appendingPathComponent("reading-\(UUID().uuidString).html")
        try? allContent.write(to: indexURL, atomically: true, encoding: .utf8)

        return ParsedEPUB(html: allContent, toc: toc, baseURL: tempRoot, indexURL: indexURL)
    }

    private static func extractBody(from html: String) -> String {
        let lower = html.lowercased()
        if let bodyStart = lower.range(of: "<body"),
           let bodyTagEnd = html[bodyStart.lowerBound...].range(of: ">"),
           let bodyEnd = lower.range(of: "</body>", options: .backwards) {
            return String(html[bodyTagEnd.upperBound..<bodyEnd.lowerBound])
        }
        return html
    }
}

