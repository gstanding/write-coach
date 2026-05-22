import SwiftUI
import WritingCoachCore

struct IOSLibraryView: View {
    @EnvironmentObject var model: IOSAppModel
    @State private var docs: [DocumentMeta] = []
    @State private var query: String = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List(docs, id: \.id) { d in
                NavigationLink {
                    IOSEditorView(documentId: d.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(d.title ?? d.id).lineLimit(1)
                        Text(d.id).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query)
            .onChange(of: query) { _, _ in reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createDoc()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear { reload() }
            .overlay(alignment: .bottom) {
                if let errorText {
                    Text(errorText).foregroundStyle(.red).padding(8)
                }
            }
        }
    }

    private func reload() {
        guard let service = model.service else { return }
        do {
            docs = try service.listDocuments(query: query.isEmpty ? nil : query, tag: nil, limit: 200, offset: 0)
            errorText = nil
        } catch {
            errorText = String(describing: error)
        }
    }

    private func createDoc() {
        guard let service = model.service else { return }
        do {
            _ = try service.createDocument(title: "Untitled")
            reload()
        } catch {
            errorText = String(describing: error)
        }
    }
}

struct IOSEditorView: View {
    @EnvironmentObject var model: IOSAppModel
    let documentId: String

    @State private var content: DocumentContent?
    @State private var titleText: String = ""
    @State private var bodyText: String = ""
    @State private var suggestions: [Suggestion] = []

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            TextEditor(text: $bodyText)
                .padding(.horizontal, 12)

            List(suggestions, id: \.id) { s in
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.message)
                    if let fix = s.fixes.first {
                        Button(fix.title) { applyFix(fix) }
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 220)
        }
        .navigationTitle(titleText.isEmpty ? "Editor" : titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Analyze") { analyze() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        guard let service = model.service else { return }
        do {
            let c = try service.loadDocument(id: documentId)
            content = c
            titleText = c.frontMatter.title ?? ""
            bodyText = c.body
            analyze()
        } catch {
        }
    }

    private func save() {
        guard let service = model.service, var c = content else { return }
        c.frontMatter.title = titleText.isEmpty ? nil : titleText
        c.frontMatter.updatedAt = Date()
        c.body = bodyText
        do {
            try service.saveDocument(c)
            content = c
        } catch {
        }
    }

    private func analyze() {
        Task { @MainActor in
            do {
                let ctx = Analyzer.analyze(documentId: documentId, body: bodyText, lexicon: .default, voice: nil)
                suggestions = try await RuleEngine.default().run(ctx: ctx)
            } catch {
                // handle error silently
            }
        }
    }

    private func applyFix(_ fix: Fix) {
        let ns = bodyText as NSString
        let start = max(0, min(fix.range.start, ns.length))
        let end = max(start, min(fix.range.end, ns.length))
        let r = NSRange(location: start, length: end - start)
        bodyText = ns.replacingCharacters(in: r, with: fix.replacement)
    }
}

