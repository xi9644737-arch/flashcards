import SwiftUI

// MARK: - 月考
//
// 和平时练习的区别：一次连着做完，中途不给对错，交卷之后一起批。
// 因为「答完立刻知道对错」会让你下一题带着刚才的思路走，测不出真实水平。

struct ExamItem: Identifiable {
    let id = UUID()
    let cardID: UUID
    let front: String
    let level: QuizLevel
    var quiz: Quiz?
    var answer: String = ""
    var judgement: Judgement?
    var failed: String? = nil
}

enum ExamPhase: Equatable {
    case setup
    case running
    case grading
    case done
}

struct ExamView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIStore
    @Environment(\.dismiss) private var dismiss

    let deckID: UUID

    @State private var phase: ExamPhase = .setup
    @State private var count = 15
    @State private var countsToward = true
    @State private var items: [ExamItem] = []
    @State private var index = 0
    @State private var loading = false
    @State private var gradedCount = 0
    @State private var errorText: String?
    @State private var record: ExamRecord?
    @State private var showCheatsheet = false

    private var deck: Deck? { store.decks.first { $0.id == deckID } }

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                switch phase {
                case .setup:   setupView
                case .running: runningView
                case .grading: gradingView
                case .done:    doneView
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(T.dim)
                    .frame(width: 34, height: 34)
                    .background(T.surface).clipShape(Circle())
                    .overlay(Circle().stroke(T.line, lineWidth: 1))
            }
            Spacer()
            Text(phase == .running ? "第 \(index + 1) / \(items.count) 题" : "月考")
                .font(T.serif(17, .medium)).foregroundColor(T.text)
            Spacer()
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 6)
    }

    // MARK: 开考前

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let deck, let last = deck.lastExam, let days = deck.daysSinceExam {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("上次月考").font(T.sans(12, .medium)).foregroundColor(T.faint)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(last.rate)")
                                    .font(T.serif(30, .semibold)).foregroundColor(scoreColor(last.rate))
                                Text("分").font(T.sans(13)).foregroundColor(T.faint)
                                Spacer()
                                Text("\(days) 天前 · 对 \(last.correct)/\(last.total)")
                                    .font(T.sans(12.5)).foregroundColor(T.dim)
                            }
                            if !last.weakTags.isEmpty {
                                Text("当时栽在：" + last.weakTags.prefix(5).joined(separator: "、"))
                                    .font(T.sans(12.5)).foregroundColor(T.faint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "考几题")
                    Panel {
                        HStack {
                            Text("\(count) 题").font(T.sans(16, .semibold)).foregroundColor(T.text)
                            Spacer()
                            Stepper("", value: $count, in: 5...40, step: 5).labelsHidden()
                        }
                    }
                    Text("大概要 \(count * 2) 次接口调用，出题一次、批改一次。DeepSeek Flash 算下来几分钱。")
                        .font(T.sans(12)).foregroundColor(T.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }

                Panel {
                    Toggle("成绩计入复习进度", isOn: $countsToward)
                        .font(T.sans(15)).tint(T.accent)
                }
                Text("打开的话，答对的卡按「良好」推进，答错的按「重来」拉回来重学。关掉就纯测水平，不动进度。")
                    .font(T.sans(12)).foregroundColor(T.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)

                Panel {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("规则").font(T.sans(13, .semibold)).foregroundColor(T.text)
                        ruleLine("从整个牌组均匀随机抽，不偏向薄弱卡")
                        ruleLine("一次做完，中途不给对错，没有提示")
                        ruleLine("不能降难度，按每张卡当前的档位出")
                        ruleLine("按考试标准批，不给同情分")
                        ruleLine("交卷之后一起批，给成绩单")
                    }
                }

                Button("开考") { start() }
                    .buttonStyle(PrimaryButtonStyle(enabled: ai.settings.configured))
                    .disabled(!ai.settings.configured)

                if !ai.settings.configured {
                    Text("要先在「AI 设置」里填接口。")
                        .font(T.sans(13)).foregroundColor(T.amber).padding(.leading, 4)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
    }

    private func ruleLine(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("·").foregroundColor(T.faint)
            Text(s).font(T.sans(13.5)).foregroundColor(T.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 考试中

    private var runningView: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(T.line)
                    Rectangle().fill(T.accent)
                        .frame(width: geo.size.width * CGFloat(index) / CGFloat(max(1, items.count)))
                }
            }
            .frame(height: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if index < items.count {
                        let item = items[index]

                        HStack(spacing: 6) {
                            Tag(text: item.level.label)
                            if let q = item.quiz {
                                Tag(text: q.kind.label, color: T.accent, bg: T.accentBg)
                            }
                            Spacer()
                        }

                        if loading && item.quiz == nil {
                            Panel {
                                HStack(spacing: 10) {
                                    ProgressView().tint(T.accent)
                                    Text("出题中......").font(T.sans(14)).foregroundColor(T.dim)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 26)
                            }
                        } else if let failed = item.failed {
                            Panel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(failed).font(T.sans(13)).foregroundColor(T.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Button("重试这一题") { loadQuestion(at: index) }
                                        .font(T.sans(14, .medium)).foregroundColor(T.accent)
                                }
                            }
                        } else if let q = item.quiz {
                            Panel {
                                Text(q.question)
                                    .font(T.serif(20)).foregroundColor(T.text)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            HStack {
                                SectionLabel(text: "你的作答")
                                Spacer()
                                Button {
                                    items[index].answer = MathInput.expand(items[index].answer)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "wand.and.stars"); Text("转符号")
                                    }
                                    .font(T.sans(12.5)).foregroundColor(T.accent)
                                }
                                Button {
                                    showCheatsheet.toggle()
                                } label: {
                                    Image(systemName: "questionmark.circle")
                                        .font(.system(size: 13)).foregroundColor(T.faint)
                                }
                            }

                            if showCheatsheet {
                                Text(MathInput.cheatsheet)
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundColor(T.dim)
                                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(T.sunken)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(MathKeys.all, id: \.self) { k in
                                        Button {
                                            items[index].answer += k
                                        } label: {
                                            Text(k).font(.system(size: 16)).foregroundColor(T.text)
                                                .frame(minWidth: 32, minHeight: 32)
                                                .background(T.surface)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(T.line, lineWidth: 1))
                                        }
                                    }
                                }
                                .padding(.horizontal, 2).padding(.vertical, 2)
                            }

                            Panel {
                                TextEditor(text: $items[index].answer)
                                    .font(T.sans(16))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 110)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
            }

            HStack(spacing: 10) {
                if index > 0 {
                    Button("上一题") { index -= 1 }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button(index == items.count - 1 ? "交卷" : "下一题") {
                    if index == items.count - 1 { submitAll() }
                    else {
                        index += 1
                        if items[index].quiz == nil { loadQuestion(at: index) }
                        prefetch(index + 1)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: items.indices.contains(index) && items[index].quiz != nil))
                .disabled(!(items.indices.contains(index) && items[index].quiz != nil))
            }
            .padding(.horizontal, 18).padding(.bottom, 20)
        }
    }

    // MARK: 批改中

    private var gradingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(T.accent).scaleEffect(1.3)
            Text("批改中 \(gradedCount) / \(items.count)")
                .font(T.serif(18, .medium)).foregroundColor(T.text)
            Text("别退出，退了这次就白考了")
                .font(T.sans(12.5)).foregroundColor(T.faint)
            Spacer()
        }
    }

    // MARK: 成绩单

    private var doneView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let r = record {
                    Panel {
                        VStack(spacing: 8) {
                            Text("\(r.rate)")
                                .font(T.serif(56, .semibold))
                                .foregroundColor(scoreColor(r.rate))
                            Text("对 \(r.correct) / \(r.total) 题")
                                .font(T.sans(14)).foregroundColor(T.dim)
                            if r.avgScore != r.rate {
                                Text("平均得分 \(r.avgScore)")
                                    .font(T.sans(12.5)).foregroundColor(T.faint)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }

                    if !r.weakTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "这次栽在这些地方")
                            Panel {
                                FlowTags(tags: r.weakTags)
                            }
                        }
                    }
                }

                SectionLabel(text: "逐题")
                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        ExamRow(number: i + 1, item: item)
                    }
                }

                Button("完成") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
    }

    private func scoreColor(_ n: Int) -> Color {
        if n >= 85 { return T.green }
        if n >= 60 { return T.amber }
        return T.red
    }

    // MARK: 逻辑

    private func start() {
        guard let deck else { return }
        // 全库均匀随机抽，不偏向薄弱卡也不偏向到期卡。
        // 偏了分数就不可比了 —— 薄弱卡少的月份卷子自动变简单，曲线会骗人。
        let pool = deck.cards.filter { $0.hasText }
        let picked = Array(pool.shuffled().prefix(count))
        guard !picked.isEmpty else { return }

        items = picked.map {
            ExamItem(cardID: $0.id, front: $0.front, level: QuizLevel.current(for: $0))
        }
        index = 0
        phase = .running
        loadQuestion(at: 0)
        prefetch(1)
    }

    private func card(_ id: UUID) -> Card? {
        deck?.cards.first { $0.id == id }
    }

    private func loadQuestion(at i: Int) {
        guard items.indices.contains(i), let c = card(items[i].cardID) else { return }
        if items[i].quiz != nil { return }
        if i == index { loading = true }
        items[i].failed = nil

        let client = AIClient(settings: ai.settings)
        let level = items[i].level
        let plan = QuizPlanner.examPlan(for: c)

        Task {
            do {
                let q: Quiz
                switch plan {
                case .variant(let s): q = try await client.makeVariant(of: s, card: c)
                default:              q = try await client.makeQuiz(card: c, weak: [], level: level)
                }
                await MainActor.run {
                    if items.indices.contains(i) { items[i].quiz = q }
                    if i == index { loading = false }
                }
            } catch {
                await MainActor.run {
                    if items.indices.contains(i) {
                        items[i].failed = (error as? AIError)?.errorDescription
                            ?? error.localizedDescription
                    }
                    if i == index { loading = false }
                }
            }
        }
    }

    /// 你在答这一题的时候，下一题已经在后台出了
    private func prefetch(_ i: Int) {
        guard items.indices.contains(i), items[i].quiz == nil else { return }
        loadQuestion(at: i)
    }

    private func submitAll() {
        phase = .grading
        gradedCount = 0
        let client = AIClient(settings: ai.settings)

        Task {
            for i in items.indices {
                guard let q = items[i].quiz, let c = card(items[i].cardID) else {
                    await MainActor.run { gradedCount += 1 }
                    continue
                }
                do {
                    let j = try await client.judge(quiz: q, answer: items[i].answer,
                                                   card: c, strict: true)
                    await MainActor.run {
                        items[i].judgement = j
                        ai.record(j, deckID: deckID)
                        gradedCount += 1
                    }
                } catch {
                    await MainActor.run {
                        items[i].failed = (error as? AIError)?.errorDescription
                            ?? error.localizedDescription
                        gradedCount += 1
                    }
                }
            }
            await MainActor.run { finish() }
        }
    }

    private func finish() {
        var r = ExamRecord()
        r.total = items.count
        r.correct = items.filter { $0.judgement?.correct == true }.count
        let scores = items.compactMap { $0.judgement?.score }
        r.avgScore = scores.isEmpty ? 0 : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())

        var tags: [String: Int] = [:]
        for item in items where item.judgement?.correct == false {
            for t in item.judgement?.tags ?? [] { tags[t, default: 0] += 1 }
        }
        r.weakTags = tags.sorted { $0.value > $1.value }.map { $0.key }

        store.addExam(r, to: deckID)

        // 成绩计入复习进度
        if countsToward {
            for item in items {
                guard let j = item.judgement else { continue }
                store.recordQuizResult(correct: j.correct, cardID: item.cardID, in: deckID)
                store.answer(deckID: deckID, cardID: item.cardID, grade: j.correct ? .good : .again)
            }
        } else {
            for item in items {
                guard let j = item.judgement else { continue }
                store.recordQuizResult(correct: j.correct, cardID: item.cardID, in: deckID)
            }
        }

        record = r
        phase = .done
    }
}

// MARK: - 成绩单里的一行

struct ExamRow: View {
    let number: Int
    let item: ExamItem
    @State private var expanded = false

    var body: some View {
        Panel(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.judgement?.correct == true
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(item.judgement?.correct == true ? T.green : T.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(number). \(item.front)")
                                .font(T.sans(14.5)).foregroundColor(T.text).lineLimit(1)
                            if let j = item.judgement {
                                Text("\(j.score) 分").font(T.sans(12)).foregroundColor(T.faint)
                            } else {
                                Text("没批上").font(T.sans(12)).foregroundColor(T.amber)
                            }
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(T.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, T.pad).padding(.vertical, 13)

                if expanded {
                    Hair().padding(.leading, T.pad)
                    VStack(alignment: .leading, spacing: 11) {
                        if let q = item.quiz {
                            block("题目", q.question)
                        }
                        block("你答的", item.answer.isEmpty ? "（空着）" : item.answer)
                        if let q = item.quiz, !q.reference.isEmpty {
                            block("参考答案", q.reference)
                        }
                        if let j = item.judgement {
                            if !j.wrongStep.isEmpty { block("错在哪", j.wrongStep) }
                            if !j.comment.isEmpty { block("解析", j.comment) }
                        }
                    }
                    .padding(.horizontal, T.pad).padding(.vertical, 13)
                }
            }
        }
    }

    private func block(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(T.sans(11.5, .medium)).foregroundColor(T.faint)
            Text(text).font(T.sans(14)).foregroundColor(T.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 标签自动换行
struct FlowTags: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows(), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { Tag(text: $0, color: T.red, bg: T.red.opacity(0.12)) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 粗暴按字数分行，够用
    private func rows() -> [[String]] {
        var out: [[String]] = []
        var line: [String] = []
        var width = 0
        for t in tags {
            let w = t.count + 3
            if width + w > 18 && !line.isEmpty {
                out.append(line); line = []; width = 0
            }
            line.append(t); width += w
        }
        if !line.isEmpty { out.append(line) }
        return out
    }
}

// MARK: - 历次月考与进步曲线

struct ExamHistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID

    private var deck: Deck? { store.decks.first { $0.id == deckID } }
    private var exams: [ExamRecord] { deck?.exams ?? [] }

    var body: some View {
        NavigationStack {
            Screen(title: "月考记录",
                   subtitle: exams.isEmpty ? nil : "共 \(exams.count) 次") {
                if exams.isEmpty {
                    Panel {
                        Text("还没考过。牌组页上有「月考」。")
                            .font(T.sans(14)).foregroundColor(T.dim)
                    }
                } else {
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(exams.last?.rate ?? 0)")
                                    .font(T.serif(38, .semibold))
                                    .foregroundColor(color(exams.last?.rate ?? 0))
                                Text("分").font(T.sans(13)).foregroundColor(T.faint)
                                Spacer()
                                if let d = delta {
                                    HStack(spacing: 3) {
                                        Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        Text("\(abs(d))")
                                    }
                                    .font(T.sans(14, .semibold))
                                    .foregroundColor(d >= 0 ? T.green : T.red)
                                }
                            }
                            ScoreCurve(values: exams.map { $0.rate })
                                .frame(height: 130)
                            Text("每次都是从整个牌组均匀随机抽题，所以这条线是可比的。")
                                .font(T.sans(11.5)).foregroundColor(T.faint)
                        }
                    }

                    SectionLabel(text: "逐次")
                    Panel(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(exams.reversed().enumerated()), id: \.element.id) { i, e in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(dateText(e.date))
                                            .font(T.sans(14)).foregroundColor(T.text)
                                        Spacer()
                                        Text("对 \(e.correct)/\(e.total)")
                                            .font(T.sans(12.5)).foregroundColor(T.faint)
                                        Text("\(e.rate)")
                                            .font(T.sans(15, .semibold))
                                            .foregroundColor(color(e.rate))
                                            .frame(width: 34, alignment: .trailing)
                                    }
                                    if !e.weakTags.isEmpty {
                                        Text("栽在：" + e.weakTags.prefix(4).joined(separator: "、"))
                                            .font(T.sans(12)).foregroundColor(T.faint)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.horizontal, T.pad).padding(.vertical, 12)

                                if i < exams.count - 1 { Hair().padding(.leading, T.pad) }
                            }
                        }
                    }
                }
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

    private var delta: Int? {
        guard exams.count >= 2 else { return nil }
        return exams[exams.count - 1].rate - exams[exams.count - 2].rate
    }

    private func color(_ n: Int) -> Color {
        if n >= 85 { return T.green }
        if n >= 60 { return T.amber }
        return T.red
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }
}

/// 手画的折线图。不引 Charts，少一个编译风险
struct ScoreCurve: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = points(in: CGSize(width: w, height: h))

            ZStack {
                // 横向参考线：60 分及格、85 分良好
                ForEach([60, 85], id: \.self) { mark in
                    let y = h - h * CGFloat(mark) / 100
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundColor(T.line)
                }

                if pts.count >= 2 {
                    // 面积
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
                        p.closeSubpath()
                    }
                    .fill(T.accent.opacity(0.10))

                    // 折线
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(T.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                // 点
                ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                    Circle()
                        .fill(T.surface)
                        .overlay(Circle().stroke(T.accent, lineWidth: 2))
                        .frame(width: 7, height: 7)
                        .position(pt)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        if values.count == 1 {
            return [CGPoint(x: size.width / 2,
                            y: size.height - size.height * CGFloat(values[0]) / 100)]
        }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step,
                    y: size.height - size.height * CGFloat(max(0, min(100, v))) / 100)
        }
    }
}
