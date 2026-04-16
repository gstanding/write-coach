import SwiftUI
import WritingCoachCore

struct EditorView: View {
    @EnvironmentObject var appModel: AppModel

    let documentId: String

    @State private var content: DocumentContent?
    @State private var bodyText: String = ""
    @State private var titleText: String = ""
    @State private var suggestions: [Suggestion] = []
    @State private var outline: [OutlineNode] = []
    @State private var errorText: String?

    @State private var saveTask: Task<Void, Never>?
    @State private var analyzeTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Text("Outline")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)

                List(outline, id: \.range) { node in
                    Button {
                        scrollTo(range: node.range)
                    } label: {
                        Text(String(repeating: "  ", count: max(0, node.level - 1)) + node.title)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 220, idealWidth: 260)

            VStack(spacing: 0) {
                HStack {
                    TextField("Title", text: $titleText)
                        .font(.title3)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: titleText) { _, _ in
                            scheduleSaveAndAnalyze()
                        }

                    Spacer()

                    Button("Analyze") {
                        runAnalyzeNow()
                    }
                }
                .padding(12)

                TextEditor(text: $bodyText)
                    .font(.system(size: 14))
                    .padding(8)
                    .onChange(of: bodyText) { _, _ in
                        scheduleSaveAndAnalyze()
                    }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .frame(minWidth: 520, idealWidth: 720)

            VStack(spacing: 0) {
                Text("Suggestions")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)

                List(suggestions, id: \.id) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("[\(s.severity.rawValue)] \(s.ruleId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(s.message)
                            .fixedSize(horizontal: false, vertical: true)
                        if !s.fixes.isEmpty {
                            HStack {
                                ForEach(s.fixes.prefix(2), id: \.title) { fix in
                                    Button(fix.title) {
                                        applyFix(fix)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(minWidth: 280, idealWidth: 360)
        }
        .frame(minWidth: 1100, minHeight: 700)
        .onAppear { load() }
    }

    private func load() {
        guard let service = appModel.service else { return }
        do {
            let c = try service.loadDocument(id: documentId)
            content = c
            titleText = c.frontMatter.title ?? ""
            bodyText = c.body
            outline = OutlineExtractor.extract(from: bodyText)
            suggestions = try service.analyzeDocument(id: documentId)
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }

    private func scheduleSaveAndAnalyze() {
        saveTask?.cancel()
        analyzeTask?.cancel()

        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            save()
        }

        analyzeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            runAnalyzeNow()
        }
    }

    private func save() {
        guard let service = appModel.service, var c = content else { return }
        c.frontMatter.title = titleText.isEmpty ? nil : titleText
        c.frontMatter.updatedAt = Date()
        c.body = bodyText
        do {
            try service.saveDocument(c)
            content = c
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }

    private func runAnalyzeNow() {
        guard let service = appModel.service else { return }
        do {
            outline = OutlineExtractor.extract(from: bodyText)
            let ctx = Analyzer.analyze(documentId: documentId, body: bodyText, lexicon: .default, voice: nil)
            suggestions = RuleEngine.default().run(ctx: ctx)
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }

    private func applyFix(_ fix: Fix) {
        let ns = bodyText as NSString
        let start = max(0, min(fix.range.start, ns.length))
        let end = max(start, min(fix.range.end, ns.length))
        let r = NSRange(location: start, length: end - start)
        let replaced = ns.replacingCharacters(in: r, with: fix.replacement)
        bodyText = replaced
    }

    private func scrollTo(range: TextRange) {
        _ = range
    }
}

