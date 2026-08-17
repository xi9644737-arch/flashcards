import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 牌组列表

struct DeckListView: View {
    @EnvironmentObject var store: Store
    @State private var showNewDeck = false
    @State private var newName = ""
    @State private var showBackup = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.decks) { deck in
                        NavigationLink(value: deck.id) {
                            HStack {
                                Text(deck.name)
                                    .fontWeight(.medium)
                                Spacer()
                                if deck.dueTotal > 0 {
                                    Text("\(deck.dueTotal)")
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 9).padding(.vertical, 2)
                                        .background(Color.red.opacity(0.16))
                                        .foregroundColor(.red)
                                        .clipShape(Capsule())
                                }
                                Text("\(deck.cards.count) 张")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        store.decks.remove(atOffsets: offsets)
                        store.save()
                    }
                } footer: {
                    if store.decks.isEmpty {
                        Text("右上角 ＋ 新建一个牌组。")
                    }
                }

                Section {
                    Button("备份 / 恢复") { showBackup = true }
                } footer: {
                    Text("数据只存在这台手机上。重签、换机、删 app 之前，先导出一份。")
                }
            }
            .navigationTitle("卡片")
            .navigationDestination(for: UUID.self) { id in
                DeckView(deckID: id)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewDeck = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("新建牌组", isPresented: $showNewDeck) {
                TextField("名字", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("建立") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty {
                        store.decks.append(Deck(name: n))
                        store.save()
                    }
                    newName = ""
                }
            }
            .sheet(isPresented: $showBackup) { BackupView() }
        }
    }
}

// MARK: - 单个牌组

struct DeckView: View {
    @EnvironmentObject var store: Store
    let deckID: UUID

    @State private var showStudy = false
    @State private var showImport = false
    @State private var showNewCard = false
    @State private var showRename = false
    @State private var renameText = ""

    private var deck: Deck? { store.decks.first { $0.id == deckID } }

    var body: some View {
        Group {
            if let deck {
                let c = deck.counts()
                List {
                    Section {
                        VStack(spacing: 6) {
                            Text("\(c.new + c.learn + c.review)")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                            Text("张待复习").font(.footnote).foregroundColor(.secondary)
                            HStack(spacing: 16) {
                                Label("\(c.new)", systemImage: "circle.fill")
                                    .foregroundColor(.blue)
                                Label("\(c.learn)", systemImage: "circle.fill")
                                    .foregroundColor(.orange)
                                Label("\(c.review)", systemImage: "circle.fill")
                                    .foregroundColor(.green)
                            }
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }

                    Section {
                        Button {
                            showStudy = true
                        } label: {
                            Text(deck.cards.isEmpty ? "还没有卡片"
                                 : (deck.dueTotal > 0 ? "开始复习" : "没到期，随便翻翻"))
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(deck.cards.isEmpty)
                    }

                    Section {
                        Button("批量导入") { showImport = true }
                        Button("加一张卡") { showNewCard = true }
                        NavigationLink("管理卡片（\(deck.cards.count)）") {
                            CardListView(deckID: deckID)
                        }
                    }
                }
                .navigationTitle(deck.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("改名") {
                            renameText = deck.name
                            showRename = true
                        }
                    }
                }
                .alert("改名", isPresented: $showRename) {
                    TextField("名字", text: $renameText)
                    Button("取消", role: .cancel) { }
                    Button("好") {
                        if let i = store.index(of: deckID) {
                            let n = renameText.trimmingCharacters(in: .whitespaces)
                            if !n.isEmpty { store.decks[i].name = n; store.save() }
                        }
                    }
                }
                .fullScreenCover(isPresented: $showStudy) {
                    StudyView(deckID: deckID)
                }
                .sheet(isPresented: $showImport) {
                    ImportView(deckID: deckID)
                }
                .sheet(isPresented: $showNewCard) {
                    CardEditView(deckID: deckID, cardID: nil)
                }
            } else {
                Text("牌组不见了").foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 复习

struct StudyView: View {
    @EnvironmentObject var store: Store
    let deckID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var currentID: UUID?
    @State private var revealed = false
    @State private var finished = false

    private var deckIndex: Int? { store.index(of: deckID) }

    private var card: Card? {
        guard let i = deckIndex, let cid = currentID else { return nil }
        return store.decks[i].cards.first { $0.id == cid }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let card {
                    counters
                    ScrollView {
                        VStack(spacing: 18) {
                            faceView(text: card.front, image: card.frontImage, size: 22)
                            if revealed {
                                Divider().frame(width: 70)
                                faceView(text: card.back, image: card.backImage, size: 20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 30)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !revealed { revealed = true } }

                    if revealed {
                        gradeButtons(card)
                    } else {
                        Button {
                            revealed = true
                        } label: {
                            Text("显示答案")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                } else {
                    Spacer()
                    Text(finished ? "这一轮完事了。" : "这个牌组还没有卡片。")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear { pickFirst() }
    }

    private var counters: some View {
        let c = deckIndex.map { store.decks[$0].counts() } ?? (new: 0, learn: 0, review: 0)
        return HStack(spacing: 18) {
            Text("\(c.new)").foregroundColor(.blue)
            Text("\(c.learn)").foregroundColor(.orange)
            Text("\(c.review)").foregroundColor(.green)
        }
        .font(.footnote.weight(.semibold))
        .padding(.top, 6)
    }

    @ViewBuilder
    private func faceView(text: String, image: Data?, size: CGFloat) -> some View {
        VStack(spacing: 14) {
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: size))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            if let image, let ui = UIImage(data: image) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .background(Color.white)
                    .cornerRadius(10)
            }
            if text.isEmpty && image == nil {
                Text("（空）").foregroundColor(.secondary)
            }
        }
    }

    private func gradeButtons(_ card: Card) -> some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases) { g in
                Button {
                    answer(g)
                } label: {
                    VStack(spacing: 2) {
                        Text(g.title).font(.system(size: 15, weight: .semibold))
                        Text(Scheduler.preview(card, g)).font(.system(size: 11)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(color(for: g))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }

    private func color(for g: Grade) -> Color {
        switch g {
        case .again: return Color(red: 0.90, green: 0.33, blue: 0.29)
        case .hard:  return Color(red: 0.85, green: 0.51, blue: 0.17)
        case .good:  return Color(red: 0.18, green: 0.62, blue: 0.39)
        case .easy:  return Color(red: 0.25, green: 0.50, blue: 0.84)
        }
    }

    private func pickFirst() {
        guard let i = deckIndex else { return }
        var pool = store.decks[i].dueCards()
        if pool.isEmpty { pool = store.decks[i].cards.sorted { $0.due < $1.due } }
        currentID = pool.first?.id
        revealed = false
        finished = false
    }

    private func answer(_ g: Grade) {
        guard let i = deckIndex,
              let cid = currentID,
              let ci = store.decks[i].cards.firstIndex(where: { $0.id == cid })
        else { return }

        Scheduler.apply(&store.decks[i].cards[ci], g)
        store.save()

        let remaining = store.decks[i].dueCards()
        if let next = remaining.first {
            currentID = next.id
            revealed = false
        } else {
            currentID = nil
            finished = true
        }
    }
}

// MARK: - 卡片列表

struct CardListView: View {
    @EnvironmentObject var store: Store
    let deckID: UUID
    @State private var showNew = false

    private var deck: Deck? { store.decks.first { $0.id == deckID } }

    var body: some View {
        List {
            if let deck {
                ForEach(deck.cards) { card in
                    NavigationLink {
                        CardEditView(deckID: deckID, cardID: card.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.front.isEmpty ? "（图片）" : card.front)
                                .lineLimit(1)
                            Text(card.back.isEmpty ? "（图片）" : card.back)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in
                    if let i = store.index(of: deckID) {
                        store.decks[i].cards.remove(atOffsets: offsets)
                        store.save()
                    }
                }
            }
        }
        .navigationTitle("卡片 \(deck?.cards.count ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showNew) {
            CardEditView(deckID: deckID, cardID: nil)
        }
    }
}

// MARK: - 编辑一张卡

struct CardEditView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let deckID: UUID
    let cardID: UUID?

    @State private var front = ""
    @State private var back = ""
    @State private var frontImage: Data?
    @State private var backImage: Data?
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("正面（问题）") {
                    TextEditor(text: $front).frame(minHeight: 88)
                    PhotosPicker("加图片", selection: $frontItem, matching: .images)
                    if let frontImage, let ui = UIImage(data: frontImage) {
                        Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 160)
                        Button("移除图片", role: .destructive) { self.frontImage = nil }
                    }
                }
                Section("背面（答案）") {
                    TextEditor(text: $back).frame(minHeight: 88)
                    PhotosPicker("加图片", selection: $backItem, matching: .images)
                    if let backImage, let ui = UIImage(data: backImage) {
                        Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 160)
                        Button("移除图片", role: .destructive) { self.backImage = nil }
                    }
                }
                Section {
                    Text("公式直接截图当图片，比打字快。图片会压到宽 900 以内。")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle(cardID == nil ? "新卡片" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadExisting)
            .onChange(of: frontItem) { item in
                Task { frontImage = await loadImage(item) }
            }
            .onChange(of: backItem) { item in
                Task { backImage = await loadImage(item) }
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return ImageTool.downscale(data)
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let cardID,
              let i = store.index(of: deckID),
              let c = store.decks[i].cards.first(where: { $0.id == cardID })
        else { return }
        front = c.front
        back = c.back
        frontImage = c.frontImage
        backImage = c.backImage
    }

    private func save() {
        guard let i = store.index(of: deckID) else { dismiss(); return }
        if let cardID, let ci = store.decks[i].cards.firstIndex(where: { $0.id == cardID }) {
            store.decks[i].cards[ci].front = front
            store.decks[i].cards[ci].back = back
            store.decks[i].cards[ci].frontImage = frontImage
            store.decks[i].cards[ci].backImage = backImage
        } else {
            var c = Card(front: front, back: back)
            c.frontImage = frontImage
            c.backImage = backImage
            if c.isBlank { dismiss(); return }
            store.decks[i].cards.append(c)
        }
        store.save()
        dismiss()
    }
}

// MARK: - 批量导入

struct ImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let deckID: UUID
    @State private var text = ""
    @State private var mode: ImportMode = .oneLine
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Picker("模式", selection: $mode) {
                    ForEach(ImportMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(mode.hint)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $text)
                    .font(.system(size: 15, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                if let message {
                    Text(message).font(.footnote).foregroundColor(.orange)
                }

                Button {
                    doImport()
                } label: {
                    Text("导入").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func doImport() {
        let cards = CardParser.parse(text, mode: mode)
        guard !cards.isEmpty else {
            message = "一张也没认出来。换个模式，或者检查分隔符。"
            return
        }
        guard let i = store.index(of: deckID) else { return }
        store.decks[i].cards.append(contentsOf: cards)
        store.save()
        dismiss()
    }
}

// MARK: - 备份 / 恢复

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?

    private var fileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "卡片备份-\(f.string(from: Date()))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("导出备份文件") { showExporter = true }
                    Button("从备份文件恢复") { showImporter = true }
                } footer: {
                    Text("导出的是一个 .json 文件，可以存到「文件」、发给自己或者传网盘。恢复会覆盖当前全部数据。")
                }

                Section {
                    let total = store.decks.reduce(0) { $0 + $1.cards.count }
                    Text("\(store.decks.count) 个牌组 · \(total) 张卡")
                        .foregroundColor(.secondary)
                }

                if let message {
                    Section { Text(message).foregroundColor(.orange) }
                }
            }
            .navigationTitle("备份 / 恢复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .fileExporter(isPresented: $showExporter,
                          document: JSONFile(data: store.exportData()),
                          contentType: .json,
                          defaultFilename: fileName) { result in
                switch result {
                case .success: message = "导出好了。"
                case .failure(let e): message = "导出失败：\(e.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let needsStop = url.startAccessingSecurityScopedResource()
                    defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else {
                        message = "读不出这个文件。"; return
                    }
                    message = store.importData(data) ? "恢复好了。" : "这个文件不是有效的备份。"
                case .failure(let e):
                    message = "打开失败：\(e.localizedDescription)"
                }
            }
        }
    }
}
