import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var service = ScanService()
    @State private var isDragOver = false
    @State private var showFilePicker = false
    @State private var fileSizeThresholdText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    dropZoneSection
                    optionsSection
                    if service.isScanning {
                        progressSection
                    }
                    if service.results != nil || service.scanError != nil {
                        resultsSection
                    }
                }
                .padding(24)
            }
            }
        .frame(minWidth: service.results != nil ? 960 : 680, minHeight: service.results != nil ? expandedMinHeight : 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await service.checkEnvironment()
            try? await Task.sleep(nanoseconds: 300_000_000)
            isTextFieldFocused = false
        }
        .onTapGesture {
            isTextFieldFocused = false
        }
        .onChange(of: service.results != nil) { _, _ in
            resizeWindowToContent()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("用于分析检测应用安装包")
                .font(.headline)

            Spacer()

            HStack(spacing: 12) {
                linkButton("GitHub", icon: "link", url: "https://github.com/iHongRen/hm-app-check-tool")
                linkButton("扫描工具文档", icon: "doc.text", url: "https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-check-tool")
                linkButton("包体积优化", icon: "shippingbox", url: "https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-decrease_pakage_size#section1660158101012")
            }

            if service.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func linkButton(_ title: String, icon: String, url: String) -> some View {
        Button {
            NSWorkspace.shared.open(URL(string: url)!)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Drop Zone

    private var dropZoneSection: some View {
        VStack(spacing: 12) {
            if service.inputFilePath != nil {
                loadedFileView
            } else {
                emptyDropZone
            }
        }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48))
                .foregroundStyle(isDragOver ? Color.accentColor : .secondary)
            Text("拖入 .hap / .hsp / .app 文件")
                .font(.title3)
                .foregroundStyle(isDragOver ? Color.accentColor : .secondary)
            Text("或点击选择文件")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .contentShape(Rectangle())
        .onTapGesture {
            showFilePicker = true
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isDragOver ? Color.accentColor.opacity(0.06) : Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDragOver ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: isDragOver ? 2 : 1))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: supportedTypes, allowsMultipleSelection: false) { result in
            guard let url = try? result.get().first else { return }
            setInputFile(url.path)
        }
    }

    private var loadedFileView: some View {
        HStack(spacing: 12) {
            Image(systemName: fileTypeIcon)
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.inputFileName ?? "")
                    .font(.body.bold())
                Text(service.inputFilePath ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                removeInputFile()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(service.isScanning)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1))
        )
    }

    // MARK: - Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("扫描选项")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                toggleOption("重复文件", isOn: $service.enableDuplicate, icon: "doc.on.doc")
                toggleOption("大文件", isOn: $service.enableFileSize, icon: "arrow.up.right.and.arrow.down.left")
                if service.enableFileSize {
                    HStack(spacing: 4) {
                        Text(">")
                        TextField("KB", text: $fileSizeThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .focused($isTextFieldFocused)
                            .onChange(of: fileSizeThresholdText) { _, newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered != newValue {
                                    fileSizeThresholdText = filtered
                                }
                                if let intValue = Int(filtered), intValue > 0 {
                                    service.fileSizeThreshold = intValue
                                }
                            }
                            .onAppear {
                                fileSizeThresholdText = String(service.fileSizeThreshold)
                                DispatchQueue.main.async {
                                    isTextFieldFocused = false
                                }
                            }
                        Text("KB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                toggleOption("文件后缀", isOn: $service.enableSuffix, icon: "doc.text.magnifyingglass")
                Spacer()
                Button {
                    Task { await service.startScan() }
                } label: {
                    Label("开始扫描", systemImage: "magnifyingglass")
                        .frame(minWidth: 120)
                }
                .controlSize(.large)
                .disabled(!service.canStartScan)
            }
        }
    }

    private func toggleOption(_ title: String, isOn: Binding<Bool>, icon: String) -> some View {
        HStack(spacing: 6) {
//            Image(systemName: icon)
//                .font(.caption)
//                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text(service.scanProgress)
                .font(.body.bold())
            if !service.scanProgressDetail.isEmpty {
                Text(service.scanProgressDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.04))
        )
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = service.scanError {
                errorBanner(error)
            }

            if let results = service.results {
                resultSummary(results)

                if let dup = results.duplicateResult {
                    duplicateCard(dup)
                }

                if let fs = results.fileSizeResult {
                    fileSizeCard(fs)
                }

                if let suf = results.suffixResult {
                    suffixCard(suf)
                }

                if !results.htmlPaths.isEmpty {
                    HStack {
                        Spacer()
                        Button("打开 HTML 报告") {
                            for path in results.htmlPaths {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("扫描错误")
                    .font(.body.bold())
                    .foregroundStyle(.red)
            }
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    private func resultSummary(_ results: ScanResults) -> some View {
        HStack(spacing: 24) {
            if let info = results.packageInfo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.bundleName)
                        .font(.headline)
                    Text(".\(info.type) 包")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let dup = results.duplicateResult {
                summaryBadge(
                    label: "重复文件",
                    value: "\(dup.totalDuplicateFiles)",
                    color: dup.totalDuplicateFiles > 0 ? .orange : .green
                )
            }
            if let fs = results.fileSizeResult {
                summaryBadge(
                    label: "大文件",
                    value: "\(fs.largeFileCount)",
                    color: fs.largeFileCount > 0 ? .orange : .green
                )
            }
            if let suf = results.suffixResult {
                summaryBadge(
                    label: "文件类型",
                    value: "\(suf.entries.count)",
                    color: .blue
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func summaryBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Duplicate Card

    private func duplicateCard(_ result: DuplicateResult) -> some View {
        resultCard("重复文件 (\(result.totalDuplicateFiles) 个文件, \(result.details.count) 组)", icon: "doc.on.doc", accent: .orange) {
            if result.details.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("未发现重复文件")
                        .font(.body)
                        .foregroundStyle(.green)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.details) { entry in
                        duplicateGroupRow(entry)
                    }
                }
            }
        }
    }

    private func duplicateGroupRow(_ entry: DuplicateEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.sizeBytes), countStyle: .file))
                    .font(.body.bold())
                    .foregroundStyle(.orange)
                Text("\(entry.count) 个重复文件")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.files, id: \.self) { path in
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.06))
        )
    }

    // MARK: - File Size Card

    private func fileSizeCard(_ result: FileSizeResult) -> some View {
        resultCard("大文件 (> \(result.threshold) KB)", icon: "arrow.up.right.and.arrow.down.left", accent: .red) {
            if result.details.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("未超过阈值的文件")
                        .font(.body)
                        .foregroundStyle(.green)
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("路径")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("大小")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .separatorColor).opacity(0.3))

                    let entries = result.details
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 8) {
                            Text(entry.path)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.sizeBytes), countStyle: .file))
                                .font(.body)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        if index < entries.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Suffix Card

    private func suffixCard(_ result: SuffixResult) -> some View {
        resultCard("文件后缀分布", icon: "doc.text.magnifyingglass", accent: .blue) {
            if result.entries.isEmpty {
                Text("无后缀数据")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(result.entries) { entry in
                        suffixRow(entry, totalSize: result.totalSize)
                    }
                }
            }
        }
    }

    private func suffixRow(_ entry: SuffixEntry, totalSize: Int) -> some View {
        HStack(spacing: 8) {
            Text(".\(entry.suffix)")
                .font(.body.bold())
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                let ratio = totalSize > 0 ? Double(entry.totalSizeBytes) / Double(totalSize) : 0
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(geo.size.width * ratio, 2))
            }
            .frame(height: 20)
            Text(totalSize > 0 ? String(format: "%.1f%%", Double(entry.totalSizeBytes) / Double(totalSize) * 100) : "0%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text("\(entry.fileCount) 个文件, \(ByteCountFormatter.string(fromByteCount: Int64(entry.totalSizeBytes), countStyle: .file))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Generic Result Card

    private func resultCard(_ title: String, icon: String, accent: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    // MARK: - Helpers

    private var expandedMinHeight: CGFloat {
        NSScreen.main.map { $0.visibleFrame.height * 0.9 } ?? 800
    }

    private func removeInputFile() {
        service.inputFilePath = nil
        service.inputFileName = nil
        service.results = nil
        service.scanError = nil
        resizeWindowToContent()
    }

    private func resizeWindowToContent() {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { return }
        let width: CGFloat = service.results != nil ? 960 : 680
        let height: CGFloat = service.results != nil ? expandedMinHeight : 360
        var frame = window.frame
        frame.size.width = width
        frame.size.height = height
        window.setFrame(frame, display: true, animate: true)
    }

    private var supportedTypes: [UTType] {
        [.item]
    }

    private var fileTypeIcon: String {
        let ext = (service.inputFilePath ?? "").pathExtension.lowercased()
        switch ext {
        case "hap": return "app.badge"
        case "hsp": return "app.badge.checkmark"
        case "app": return "app.dashed"
        default: return "doc"
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
            var filePath: String? = nil
            if let url = data as? URL {
                filePath = url.path
            } else if let data = data as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                filePath = url.path
            } else if let path = data as? String {
                filePath = path
            }
            if let path = filePath {
                DispatchQueue.main.async {
                    setInputFile(path)
                }
            }
        }
    }

    private func setInputFile(_ path: String) {
        // Remove percent encoding if present
        let cleanPath = path.removingPercentEncoding ?? path
        let ext = URL(fileURLWithPath: cleanPath).pathExtension.lowercased()
        if !["hap", "hsp", "app"].contains(ext) {
            service.scanError = "不支持的文件类型: .\(ext)。请使用 .hap、.hsp 或 .app 文件。"
            return
        }
        service.inputFilePath = cleanPath
        service.inputFileName = URL(fileURLWithPath: cleanPath).lastPathComponent
        service.results = nil
        service.scanError = nil
        Task { await service.startScan() }
    }
}

extension String {
    var abbreviatedPath: String {
        let components = self.components(separatedBy: "/")
        if components.count <= 4 { return self }
        return ".../" + components.dropFirst(components.count - 3).joined(separator: "/")
    }

    var pathExtension: String {
        URL(fileURLWithPath: self).pathExtension
    }
}

#Preview {
    ContentView()
}
