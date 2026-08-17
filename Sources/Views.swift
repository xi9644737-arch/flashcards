import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - 牌组列表

struct DeckListView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIStore

    @State private var showNewDeck = false
    @State private var newName = ""
    @State private var showBackup = false
    @State private var showAISettings = false
    @State private var showWeak = false
    @State private var showScheduler = false

    private var totalDue: Int { store.decks.reduce(0) { $0 + $1.dueTotal } }

    var body: some View {
        NavigationStack {
            Screen(title: "卡片",
                   subtitle: totalDue > 0 ? "今天有 \(totalDue) 张等着你" : "今天没有到期的") {

                VStack(spacing: 10) {
                    ForEach(store.decks) { deck in
                        NavigationLink(value: deck.id) {
                            deckRow(deck)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showNewDeck = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("新建牌组")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "练习")
                    Panel(padding: 0) {
                        VStack(spacing: 0) {
                            RowButton(title: "AI 设置",
                                      subtitle: ai.settings.configured ? "已接好 \(ai.settings.model)" : "还没填接口") {
                                showAISettings = true
                            }
                            .padding(.horizontal, T.pad).padding(.vertical, 14)

                            Hair().padding(.leading, T.pad)

                            RowButton(title: "薄弱点",
                                      subtitle: ai.tags.isEmpty ? "做几道题就有了" : "记录了 \(ai.tags.count) 个知识点") {
                                showWeak = true
                            }
                            .padding(.horizontal, T.pad).padding(.vertical, 14)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "设置")
                    Panel(padding: 0) {
                        VStack(spacing: 0) {
                            RowButton(title: "复习算法",
                                      subtitle: store.config.algorithm.label) {
                                showScheduler = true
                            }
                            .padding(.horizontal, T.pad).padding(.vertical, 14)

                            Hair().padding(.leading, T.pad)

                            RowButton(title: "备份 / 恢复",
                                      subtitle: "数据只在这台手机上") {
                                showBackup = true
                            }
                            .padding(.horizontal, T.pad).padding(.vertical, 14)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(T.bg, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                DeckView(deckID: id)
            }
            .alert("新建牌组", isPresented: $showNewDeck) {
                TextField("名字", text: $newName)
                Button("取消", role: .cancel) { newName = "" }
                Button("建立") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { store.decks.append(Deck(name: n)); store.save() }
                    newName = ""
                }
            }
            .sheet(isPresented: $showBackup) { BackupView() }
            .sheet(isPresented: $showAISettings) { AISettingsView() }
            .sheet(isPresented: $showWeak) { WeakPointsView() }
            .sheet(isPresented: $showScheduler) { SchedulerSettingsView() }
        }
        .tint(T.accent)
    }

    private func deckRow(_ deck: Deck) -> some View {
        Panel {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.name)
                        .font(T.serif(19, .medium))
                        .foregroundColor(T.text)
                    Text("\(deck.cards.count) 张卡")
                        .font(T.sans(13))
                        .foregroundColor(T.faint)
                }
                Spacer()
                if deck.dueTotal > 0 {
                    Text("\(deck.dueTotal)")
                        .font(T.sans(15, .semibold))
                        .foregroundColor(T.accent)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(T.accentBg)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(T.faint)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(T.faint)
            }
        }
    }
}

// MARK: - 单个牌组

struct DeckView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIStore
    let deckID: UUID

    @State private var showQuiz = false
    @State private var showStudy = false
    @State private var showImport = false
    @State private var showNewCard = false
    @State private var showRename = false
    @State private var showDelete = false
    @State private var renameText = ""

    private var deck: Deck? { store.decks.first { $0.id == deckID } }

    var body: some View {
        Group {
            if let deck {
                let c = deck.counts()
                Screen(title: deck.name, subtitle: nil) {

                    Panel {
                        VStack(spacing: 10) {
                            Text("\(c.new + c.learn + c.review)")
                                .font(T.serif(52, .semibold))
                                .foregroundColor(T.text)
                            Text("张待复习")
                                .font(T.sans(13))
                                .foregroundColor(T.faint)
                            HStack(spacing: 20) {
                                countPill("新", c.new, T.blue)
                                countPill("学习", c.learn, T.amber)
                                countPill("复习", c.review, T.green)
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }

                    VStack(spacing: 10) {
                        Button {
                            showStudy = true
                        } label: {
                            Text(deck.dueTotal > 0 ? "开始复习" : "没到期，随便翻翻")
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: !deck.cards.isEmpty))
                        .disabled(deck.cards.isEmpty)

                        Button {
                            showQuiz = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "sparkles")
                                Text("AI 出题练习")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(deck.cards.isEmpty)

                        Text(ai.settings.configured
                             ? "翻卡是测记没记住，出题是测会不会用。"
                             : "出题练习要先在上一层填 API。")
                            .font(T.sans(12.5))
                            .foregroundColor(T.faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "卡片")
                        Panel(padding: 0) {
                            VStack(spacing: 0) {
                                RowButton(title: "批量导入", subtitle: "从别处复制粘贴进来") {
                                    showImport = true
                                }
                                .padding(.horizontal, T.pad).padding(.vertical, 14)

                                Hair().padding(.leading, T.pad)

                                RowButton(title: "加一张卡") { showNewCard = true }
                                    .padding(.horizontal, T.pad).padding(.vertical, 14)

                                Hair().padding(.leading, T.pad)

                                NavigationLink {
                                    CardListView(deckID: deckID)
                                } label: {
                                    HStack {
                                        Text("管理卡片").font(T.sans(16)).foregroundColor(T.text)
                                        Spacer()
                                        Text("\(deck.cards.count)")
                                            .font(T.sans(14)).foregroundColor(T.faint)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(T.faint)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, T.pad).padding(.vertical, 14)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("改名") { renameText = deck.name; showRename = true }
                            .buttonStyle(SecondaryButtonStyle())
                        Button {
                            showDelete = true
                        } label: {
                            Text("删除牌组").foregroundColor(T.red)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(T.bg, for: .navigationBar)
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
                .alert("删掉「\(deck.name)」和里面 \(deck.cards.count) 张卡？", isPresented: $showDelete) {
                    Button("取消", role: .cancel) { }
                    Button("删除", role: .destructive) {
                        store.decks.removeAll { $0.id == deckID }
                        store.save()
                    }
                } message: {
                    Text("不可撤销。")
                }
                .fullScreenCover(isPresented: $showStudy) { StudyView(deckID: deckID) }
                .fullScreenCover(isPresented: $showQuiz) { QuizView(deckID: deckID) }
                .sheet(isPresented: $showImport) { ImportView(deckID: deckID) }
                .sheet(isPresented: $showNewCard) { CardEditView(deckID: deckID, cardID: nil) }
            } else {
                ZStack {
                    T.bg.ignoresSafeArea()
                    Text("牌组不见了").foregroundColor(T.dim)
                }
            }
        }
    }

    private func countPill(_ name: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(n)").font(T.sans(14, .semibold)).foregroundColor(T.text)
            Text(name).font(T.sans(12)).foregroundColor(T.faint)
        }
    }
}

// MARK: - 翻卡复习

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
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar

                if let card {
                    ScrollView {
                        VStack(spacing: 22) {
                            face(text: card.front, image: card.frontImage, size: 23, weight: .medium)
                            if revealed {
                                Rectangle().fill(T.line)
                                    .frame(width: 56, height: 1)
                                face(text: card.back, image: card.backImage, size: 20, weight: .regular)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 36)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !revealed { revealed = true } }

                    if revealed {
                        gradeBar(card)
                    } else {
                        Button("显示答案") { revealed = true }
                            .buttonStyle(PrimaryButtonStyle())
                            .padding(.horizontal, 18)
                            .padding(.bottom, 22)
                    }
                } else {
                    Spacer()
                    VStack(spacing: 10) {
                        Text(finished ? "这一轮完事了" : "这个牌组还没有卡片")
                            .font(T.serif(21, .medium))
                            .foregroundColor(T.text)
                        if finished {
                            Text("过一会儿再回来")
                                .font(T.sans(13)).foregroundColor(T.faint)
                        }
                    }
                    Spacer()
                }
            }
        }
        .onAppear { pickFirst() }
    }

    private var topBar: some View {
        let c = deckIndex.map { store.decks[$0].counts() } ?? (new: 0, learn: 0, review: 0)
        return HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(T.dim)
                    .frame(width: 34, height: 34)
                    .background(T.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(T.line, lineWidth: 1))
            }
            Spacer()
            HStack(spacing: 14) {
                Text("\(c.new)").foregroundColor(T.blue)
                Text("\(c.learn)").foregroundColor(T.amber)
                Text("\(c.review)").foregroundColor(T.green)
            }
            .font(T.sans(14, .semibold))
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func face(text: String, image: Data?, size: CGFloat, weight: Font.Weight) -> some View {
        VStack(spacing: 16) {
            if !text.isEmpty {
                Text(text)
                    .font(T.serif(size, weight))
                    .foregroundColor(T.text)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            if let image, let ui = UIImage(data: image) {
                Image(uiImage: ui)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 300)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if text.isEmpty && image == nil {
                Text("（空）").foregroundColor(T.faint)
            }
        }
    }

    private func gradeBar(_ card: Card) -> some View {
        HStack(spacing: 8) {
            ForEach(Grade.allCases) { g in
                Button {
                    answer(g)
                } label: {
                    VStack(spacing: 3) {
                        Text(g.title).font(T.sans(15, .semibold))
                        Text(Scheduler.preview(card, g, config: store.config))
                            .font(T.sans(11)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(T.gradeColor(g))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
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
        guard let cid = currentID else { return }
        store.answer(deckID: deckID, cardID: cid, grade: g)
        guard let i = deckIndex else { return }
        if let next = store.decks[i].dueCards().first {
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
    @State private var search = ""

    private var deck: Deck? { store.decks.first { $0.id == deckID } }

    private var filtered: [Card] {
        guard let deck else { return [] }
        let k = search.trimmingCharacters(in: .whitespaces)
        if k.isEmpty { return deck.cards }
        return deck.cards.filter { $0.front.contains(k) || $0.back.contains(k) }
    }

    var body: some View {
        Screen(title: "管理卡片", subtitle: "\(deck?.cards.count ?? 0) 张") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(T.faint)
                TextField("搜索", text: $search)
                    .font(T.sans(15))
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(T.faint)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(T.sunken)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                showNew = true
            } label: {
                HStack(spacing: 6) { Image(systemName: "plus"); Text("加一张卡") }
            }
            .buttonStyle(SecondaryButtonStyle())

            if filtered.isEmpty {
                Panel {
                    Text(search.isEmpty ? "还没有卡片。" : "没搜到。")
                        .font(T.sans(14)).foregroundColor(T.dim)
                }
            } else {
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, card in
                            NavigationLink {
                                CardEditView(deckID: deckID, cardID: card.id)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(card.front.isEmpty ? "（图片）" : card.front)
                                            .font(T.sans(15)).foregroundColor(T.text)
                                            .lineLimit(1)
                                        Text(card.back.isEmpty ? "（图片）" : card.back)
                                            .font(T.sans(12.5)).foregroundColor(T.faint)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Tag(text: card.stateName)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(T.faint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, T.pad).padding(.vertical, 13)

                            if idx < filtered.count - 1 {
                                Hair().padding(.leading, T.pad)
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(T.bg, for: .navigationBar)
        .sheet(isPresented: $showNew) { CardEditView(deckID: deckID, cardID: nil) }
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
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            Screen(title: cardID == nil ? "新卡片" : "编辑卡片") {
                editBlock(label: "正面 · 问题", text: $front, image: $frontImage,
                          item: $frontItem, placeholder: "二次函数顶点横坐标")
                editBlock(label: "背面 · 答案", text: $back, image: $backImage,
                          item: $backItem, placeholder: "x = −b / (2a)")

                Text("公式直接截图当图片，比打字快。图片会压到宽 900 存起来。")
                    .font(T.sans(12.5)).foregroundColor(T.faint)
                    .padding(.leading, 4)

                Button("保存") { save() }
                    .buttonStyle(PrimaryButtonStyle())

                if cardID != nil {
                    Button {
                        showDelete = true
                    } label: {
                        Text("删掉这张卡").foregroundColor(T.red)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(T.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }.tint(T.dim)
                }
            }
            .onAppear(perform: loadExisting)
            .onChange(of: frontItem) { item in
                Task { frontImage = await loadImage(item) }
            }
            .onChange(of: backItem) { item in
                Task { backImage = await loadImage(item) }
            }
            .alert("删掉这张卡？", isPresented: $showDelete) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) { deleteCard() }
            }
        }
        .tint(T.accent)
    }

    @ViewBuilder
    private func editBlock(label: String, text: Binding<String>, image: Binding<Data?>,
                           item: Binding<PhotosPickerItem?>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: label)
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if text.wrappedValue.isEmpty {
                            Text(placeholder)
                                .font(T.sans(16)).foregroundColor(T.faint)
                                .padding(.top, 8).padding(.leading, 5)
                        }
                        TextEditor(text: text)
                            .font(T.sans(16))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 88)
                    }

                    if let data = image.wrappedValue, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 170)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button("移除图片") { image.wrappedValue = nil }
                            .font(T.sans(13)).foregroundColor(T.red)
                    }

                    PhotosPicker(selection: item, matching: .images) {
                        HStack(spacing: 5) {
                            Image(systemName: "photo")
                            Text("加图片")
                        }
                        .font(T.sans(13.5))
                        .foregroundColor(T.accent)
                    }
                }
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async -> Data? {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return ImageTool.downscale(data)
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let cardID, let i = store.index(of: deckID),
              let c = store.decks[i].cards.first(where: { $0.id == cardID }) else { return }
        front = c.front; back = c.back
        frontImage = c.frontImage; backImage = c.backImage
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

    private func deleteCard() {
        guard let cardID, let i = store.index(of: deckID) else { return }
        store.decks[i].cards.removeAll { $0.id == cardID }
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

    private var preview: [Card] { CardParser.parse(text, mode: mode) }

    var body: some View {
        NavigationStack {
            Screen(title: "批量导入", subtitle: "从别处复制，粘贴进来") {
                Picker("模式", selection: $mode) {
                    ForEach(ImportMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(mode.hint)
                    .font(T.sans(12.5)).foregroundColor(T.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)

                Panel {
                    TextEditor(text: $text)
                        .font(.system(size: 14.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                }

                if !text.isEmpty {
                    Text(preview.isEmpty
                         ? "按这个模式一张也认不出来，换一个试试。"
                         : "认出 \(preview.count) 张。第一张：\(preview[0].front) → \(preview[0].back)")
                        .font(T.sans(12.5))
                        .foregroundColor(preview.isEmpty ? T.amber : T.green)
                        .padding(.leading, 4)
                }

                if let message {
                    Text(message).font(T.sans(13)).foregroundColor(T.amber)
                }

                Button("导入 \(preview.count) 张") { doImport() }
                    .buttonStyle(PrimaryButtonStyle(enabled: !preview.isEmpty))
                    .disabled(preview.isEmpty)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(T.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }.tint(T.dim)
                }
            }
        }
        .tint(T.accent)
    }

    private func doImport() {
        let cards = preview
        guard !cards.isEmpty, let i = store.index(of: deckID) else {
            message = "一张也没认出来。"
            return
        }
        store.decks[i].cards.append(contentsOf: cards)
        store.save()
        dismiss()
    }
}

// MARK: - 复习算法设置

struct SchedulerSettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Screen(title: "复习算法") {
                VStack(spacing: 10) {
                    ForEach(Algorithm.allCases) { a in
                        Button {
                            store.config.algorithm = a
                        } label: {
                            Panel {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: store.config.algorithm == a
                                          ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(store.config.algorithm == a ? T.accent : T.faint)
                                        .font(.system(size: 19))
                                        .padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(a.label)
                                            .font(T.serif(18, .medium)).foregroundColor(T.text)
                                        Text(a.blurb)
                                            .font(T.sans(13)).foregroundColor(T.dim)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if store.config.algorithm == .fsrs {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "目标记忆保持率")
                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(String(format: "%.0f%%", store.config.requestRetention * 100))
                                        .font(T.serif(28, .semibold))
                                        .foregroundColor(T.accent)
                                    Spacer()
                                    Text(retentionNote)
                                        .font(T.sans(12.5)).foregroundColor(T.faint)
                                }
                                Slider(value: $store.config.requestRetention, in: 0.75...0.97, step: 0.01)
                                    .tint(T.accent)
                                Text("到期那天，你还记得这张卡的概率。调高＝复习更勤、记得更牢、花时间更多；调低反过来。90% 是通用的甜点。")
                                    .font(T.sans(12.5)).foregroundColor(T.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "间隔上限")
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(Int(store.config.maximumInterval)) 天")
                                        .font(T.sans(16, .semibold)).foregroundColor(T.text)
                                    Spacer()
                                    Stepper("", value: $store.config.maximumInterval,
                                            in: 30...(365 * 10), step: 365)
                                        .labelsHidden()
                                }
                                Text("再熟的卡也不会隔得比这更久。")
                                    .font(T.sans(12.5)).foregroundColor(T.faint)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "参数")
                        Panel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("用的是 FSRS-4.5 官方默认参数。")
                                    .font(T.sans(14)).foregroundColor(T.text)
                                Text("已经攒了 \(store.logCount) 条复习记录。等这个数上千，就有条件用你自己的数据重新拟合一套专属参数，那时候间隔会更准。记录跟着备份一起存。")
                                    .font(T.sans(12.5)).foregroundColor(T.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Text("换算法不会清掉已有进度。FSRS 用稳定性和难度，SM-2 用 ease，两套数各存各的，来回切也不会打架。")
                    .font(T.sans(12.5)).foregroundColor(T.faint)
                    .padding(.leading, 4)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(T.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.tint(T.accent)
                }
            }
        }
        .tint(T.accent)
    }

    private var retentionNote: String {
        let r = store.config.requestRetention
        if r >= 0.94 { return "很勤，适合考前" }
        if r >= 0.88 { return "常用" }
        if r >= 0.82 { return "省时间" }
        return "很省，会忘得多"
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
            Screen(title: "备份 / 恢复") {
                Panel {
                    let total = store.decks.reduce(0) { $0 + $1.cards.count }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(store.decks.count) 个牌组 · \(total) 张卡")
                            .font(T.sans(16)).foregroundColor(T.text)
                        Text("复习记录 \(store.logCount) 条")
                            .font(T.sans(12.5)).foregroundColor(T.faint)
                    }
                }

                VStack(spacing: 10) {
                    Button("导出备份文件") { showExporter = true }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("从备份文件恢复") { showImporter = true }
                        .buttonStyle(SecondaryButtonStyle())
                }

                if let message {
                    Text(message).font(T.sans(13))
                        .foregroundColor(message.hasPrefix("导出好") || message.hasPrefix("恢复好") ? T.green : T.amber)
                        .padding(.leading, 4)
                }

                Text("导出的是一个 .json 文件，可以存到「文件」、发给自己或者传网盘。恢复会覆盖当前全部数据。\n\n免费签名 7 天到期后重签是覆盖安装，数据不会丢；但删掉 app 再装就没了，所以隔一阵导一次。")
                    .font(T.sans(12.5)).foregroundColor(T.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(T.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.tint(T.accent)
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
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
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
        .tint(T.accent)
    }
}
