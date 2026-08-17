import SwiftUI

// MARK: - AI 出题练习

struct QuizView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ai: AIStore
    @Environment(\.dismiss) private var dismiss

    let deckID: UUID

    @State private var cardID: UUID?
    @State private var quiz: Quiz?
    @State private var answer = ""
    @State private var judgement: Judgement?
    @State private var loading = false
    @State private var judging = false
    @State private var errorText: String?
    @State private var showHint = false
    @State private var planLabel: String?
    @State private var servedQuizID: UUID?
    @State private var currentLevel: QuizLevel = .recall
    @State private var levelChange: LevelChange = .none
    @State private var showCheatsheet = false
    @FocusState private var focused: Bool

    private var deckIndex: Int? { store.index(of: deckID) }
    private var card: Card? {
        guard let i = deckIndex, let cid = cardID else { return nil }
        return store.decks[i].cards.first { $0.id == cid }
    }

    /// AI 看不见图，纯图片卡出不了题
    private var quizableCards: [Card] {
        guard let i = deckIndex else { return [] }
        return store.decks[i].cards.filter { $0.hasText }
    }

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if !ai.settings.configured {
                    notice("还没配 API", "回上一层，在「AI 设置」里填地址和 key。")
                } else if quizableCards.isEmpty {
                    notice("这个牌组出不了题",
                           "AI 需要读得懂卡上写的字，纯图片卡挑不出来。翻卡模式照常能用。")
                } else {
                    content
                }
            }
        }
        .onAppear { if quiz == nil && cardID == nil { nextCard() } }
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
            Text("出题练习").font(T.serif(17, .medium)).foregroundColor(T.text)
            Spacer()
            Button {
                loadQuiz()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(loading || judging ? T.faint : T.dim)
                    .frame(width: 34, height: 34)
                    .background(T.surface).clipShape(Circle())
                    .overlay(Circle().stroke(T.line, lineWidth: 1))
            }
            .disabled(loading || judging)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let card {
                        Text("出自：\(card.front)")
                            .font(T.sans(12)).foregroundColor(T.faint)
                            .padding(.leading, 4)
                    }

                    if loading {
                        Panel {
                            HStack(spacing: 10) {
                                ProgressView().tint(T.accent)
                                Text("正在出题......").font(T.sans(14)).foregroundColor(T.dim)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                        }
                    }

                    if let errorText {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(errorText)
                                    .font(T.sans(13)).foregroundColor(T.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("重试") { loadQuiz() }
                                    .font(T.sans(14, .medium)).foregroundColor(T.accent)
                            }
                        }
                    }

                    if let quiz {
                        HStack(spacing: 6) {
                            Tag(text: quiz.kind.label, color: T.accent, bg: T.accentBg)
                            Tag(text: currentLevel.label)
                            if let planLabel {
                                Tag(text: planLabel)
                            }
                            Spacer()
                            if !quiz.hint.isEmpty && judgement == nil {
                                Button(showHint ? "收起提示" : "看提示") { showHint.toggle() }
                                    .font(T.sans(13)).foregroundColor(T.accent)
                            }
                        }

                        if judgement == nil {
                            HStack(spacing: 14) {
                                Button {
                                    nudge(-1)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.right.circle")
                                        Text(currentLevel == .recall ? "换一道" : "太难了，降一档")
                                    }
                                }
                                .disabled(loading)

                                Button {
                                    nudge(1)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.right.circle")
                                        Text("太简单了，升一档")
                                    }
                                }
                                .disabled(loading || currentLevel == .transfer)
                                .opacity(currentLevel == .transfer ? 0.35 : 1)

                                Spacer()
                            }
                            .font(T.sans(13))
                            .foregroundColor(T.dim)
                            .padding(.leading, 4)
                        }

                        Panel {
                            Text(quiz.question)
                                .font(T.serif(20))
                                .foregroundColor(T.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if showHint && !quiz.hint.isEmpty && judgement == nil {
                            Text(quiz.hint)
                                .font(T.sans(13)).foregroundColor(T.dim)
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(T.sunken)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if judgement == nil { answerBox } else { answeredBox }
                    }

                    if let j = judgement { resultBox(j) }

                    if let t = levelChange.text {
                        HStack(spacing: 8) {
                            Image(systemName: levelChange == .none ? "" :
                                    (t.contains("升档") ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                            Text(t).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(T.sans(13))
                        .foregroundColor(t.contains("升档") ? T.green : T.amber)
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((t.contains("升档") ? T.green : T.amber).opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if judgement != nil, let c = card, c.quizStreak > 0 {
                        Text("这一档已经连对 \(c.quizStreak) 次，再对 \(QuizPlanner.promoteAfter - c.quizStreak) 次升档。")
                            .font(T.sans(12.5)).foregroundColor(T.faint)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }

            if let j = judgement { gradeBar(j) }
            else if quiz != nil { submitBar }
        }
    }

    private var answerBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "你的作答")
                Spacer()
                Button {
                    answer = MathInput.expand(answer)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("转符号")
                    }
                    .font(T.sans(12.5))
                    .foregroundColor(T.accent)
                }
                Button {
                    showCheatsheet.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundColor(T.faint)
                }
            }

            if showCheatsheet {
                Text(MathInput.cheatsheet)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(T.dim)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.sunken)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MathKeys.all, id: \.self) { k in
                        Button {
                            answer += k
                        } label: {
                            Text(k)
                                .font(.system(size: 16))
                                .foregroundColor(T.text)
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
                TextEditor(text: $answer)
                    .font(T.sans(16))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 110)
            }
        }
    }

    private var answeredBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "你的作答")
            Text(answer.isEmpty ? "（空着）" : answer)
                .font(T.sans(15))
                .foregroundColor(answer.isEmpty ? T.faint : T.text)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(T.sunken)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func resultBox(_ j: Judgement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: j.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(j.correct ? T.green : T.red)
                        Text(j.correct ? "对了" : "错了")
                            .font(T.serif(20, .medium)).foregroundColor(T.text)
                        Spacer()
                        Text("\(j.score)")
                            .font(T.serif(22, .semibold))
                            .foregroundColor(j.correct ? T.green : T.red)
                        Text("分").font(T.sans(12)).foregroundColor(T.faint)
                    }

                    if !j.wrongStep.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("错在哪").font(T.sans(12, .medium)).foregroundColor(T.faint)
                            Text(j.wrongStep)
                                .font(T.sans(15)).foregroundColor(T.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(T.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }

                    if !j.comment.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("解析").font(T.sans(12, .medium)).foregroundColor(T.faint)
                            Text(j.comment)
                                .font(T.sans(15)).foregroundColor(T.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let quiz, !quiz.reference.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("参考答案").font(T.sans(12, .medium)).foregroundColor(T.faint)
                            Text(quiz.reference)
                                .font(T.serif(16)).foregroundColor(T.text)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !j.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(j.tags, id: \.self) { Tag(text: $0) }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            Hair()
            Button {
                focused = false
                submit()
            } label: {
                HStack(spacing: 8) {
                    if judging { ProgressView().tint(.white) }
                    Text(judging ? "批改中......" : "提交")
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !judging && !loading))
            .disabled(judging || loading)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(T.bg)
    }

    private func gradeBar(_ j: Judgement) -> some View {
        VStack(spacing: 8) {
            Hair()
            Text("AI 建议「\(j.suggestedGrade.title)」，不同意自己选")
                .font(T.sans(11.5)).foregroundColor(T.faint)
                .padding(.top, 8)
            HStack(spacing: 8) {
                ForEach(Grade.allCases) { g in
                    Button {
                        applyGrade(g)
                    } label: {
                        VStack(spacing: 3) {
                            Text(g.title).font(T.sans(15, .semibold))
                            if let c = card {
                                Text(Scheduler.preview(c, g, config: store.config))
                                    .font(T.sans(11)).opacity(0.85)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(g == j.suggestedGrade
                                    ? T.gradeColor(g) : T.gradeColor(g).opacity(0.42))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(T.bg)
    }

    private func notice(_ title: String, _ body: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title).font(T.serif(21, .medium)).foregroundColor(T.text)
            Text(body)
                .font(T.sans(13.5)).foregroundColor(T.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 36)
    }

    // MARK: 逻辑

    private func nextCard() {
        let pool = quizableCards
        guard !pool.isEmpty else { return }
        let due = pool.filter { $0.due <= Date() }.sorted { $0.due < $1.due }
        cardID = (due.first ?? pool.randomElement())?.id
        loadQuiz()
    }

    private func loadQuiz(forceFresh: Bool = false) {
        guard let card else { return }
        quiz = nil; judgement = nil; answer = ""
        showHint = false; errorText = nil; planLabel = nil
        servedQuizID = nil; levelChange = .none; loading = true

        let client = AIClient(settings: ai.settings)
        let weak = ai.weakest(ai.settings.weakHintCount, deckID: deckID)
        let plan: QuizPlan = forceFresh ? .fresh : QuizPlanner.plan(for: card)
        let cid = card.id
        let level = ai.settings.autoLevel ? QuizLevel.current(for: card) : ai.settings.fixedLevel
        currentLevel = level

        Task {
            do {
                switch plan {
                case .reuse(let stored):
                    // 零调用
                    await MainActor.run {
                        quiz = stored.asQuiz
                        servedQuizID = stored.id
                        planLabel = plan.label
                        loading = false
                        store.markQuizUsed(stored.id, cardID: cid, in: deckID)
                    }

                case .variant(let stored):
                    let q = try await client.makeVariant(of: stored, card: card)
                    await MainActor.run {
                        quiz = q
                        servedQuizID = stored.id
                        planLabel = plan.label
                        loading = false
                        store.markQuizUsed(stored.id, cardID: cid, in: deckID)
                    }

                case .fresh:
                    let q = try await client.makeQuiz(card: card, weak: weak, level: level)
                    await MainActor.run {
                        quiz = q
                        servedQuizID = nil
                        planLabel = plan.label
                        loading = false
                        store.addQuiz(q, cardID: cid, in: deckID)
                    }
                }
            } catch {
                // 接口挂了或者没网：库里有存货就照常练，只是批改要等联网
                if let fallback = QuizPlanner.fallback(for: card) {
                    await MainActor.run {
                        quiz = fallback.asQuiz
                        servedQuizID = fallback.id
                        planLabel = "离线复用"
                        errorText = "连不上接口，先用存着的旧题。答完要联网才能批改。"
                        loading = false
                        store.markQuizUsed(fallback.id, cardID: cid, in: deckID)
                    }
                } else {
                    await MainActor.run {
                        errorText = (error as? AIError)?.errorDescription ?? error.localizedDescription
                        loading = false
                    }
                }
            }
        }
    }

    private func submit() {
        guard let quiz, let card else { return }
        judging = true; errorText = nil
        let client = AIClient(settings: ai.settings)

        Task {
            do {
                let j = try await client.judge(quiz: quiz, answer: answer, card: card)
                await MainActor.run {
                    judgement = j
                    ai.record(j, deckID: deckID)
                    judging = false
                    // 记对错，并按表现升降档
                    levelChange = store.recordQuizResult(
                        correct: j.correct, cardID: card.id, in: deckID)
                }
            } catch {
                await MainActor.run {
                    errorText = (error as? AIError)?.errorDescription ?? error.localizedDescription
                    judging = false
                }
            }
        }
    }

    /// 手动升降一档，然后重出一道
    private func nudge(_ delta: Int) {
        guard let cid = cardID else { return }
        store.nudgeQuizLevel(by: delta, dropQuiz: delta < 0 ? servedQuizID : nil,
                             cardID: cid, in: deckID)
        loadQuiz(forceFresh: true)
    }

    private func applyGrade(_ g: Grade) {
        if let cid = cardID {
            store.answer(deckID: deckID, cardID: cid, grade: g)
        }
        nextCard()
    }
}

// MARK: - AI 设置

struct AISettingsView: View {
    @EnvironmentObject var ai: AIStore
    @Environment(\.dismiss) private var dismiss

    @State private var testing = false
    @State private var testResult: String?
    @State private var ok = false
    @State private var listing = false
    @State private var models: [String] = []
    @State private var modelError: String?

    var body: some View {
        NavigationStack {
            Screen(title: "AI 设置", subtitle: "填一个 OpenAI 兼容的接口") {

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "快速填入")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Preset.all) { p in
                                Button {
                                    ai.settings.baseURL = p.url
                                    if !p.model.isEmpty { ai.settings.model = p.model }
                                    testResult = nil
                                    models = []
                                } label: {
                                    Text(p.name)
                                        .font(T.sans(13, .medium))
                                        .foregroundColor(ai.settings.baseURL == p.url ? .white : T.text)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(ai.settings.baseURL == p.url ? T.accent : T.surface)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(
                                            ai.settings.baseURL == p.url ? Color.clear : T.line, lineWidth: 1))
                                }
                            }
                        }
                        .padding(.horizontal, 2).padding(.vertical, 2)
                    }
                    if let p = Preset.all.first(where: { $0.url == ai.settings.baseURL }) {
                        Text(p.note)
                            .font(T.sans(12)).foregroundColor(T.faint)
                            .padding(.leading, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "接口地址")
                    Panel {
                        TextField("https://api.deepseek.com", text: $ai.settings.baseURL)
                            .font(T.sans(15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Text("填到 /v1 或者只填到域名都行，/chat/completions 会自动补。")
                        .font(T.sans(12)).foregroundColor(T.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "API Key")
                    Panel {
                        SecureField("sk-......", text: $ai.settings.apiKey)
                            .font(T.sans(15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "模型")
                    Panel {
                        TextField("deepseek-v4-flash", text: $ai.settings.model)
                            .font(T.sans(15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Button {
                        fetchModels()
                    } label: {
                        HStack(spacing: 6) {
                            if listing { ProgressView().scaleEffect(0.8) }
                            Image(systemName: "arrow.down.circle")
                            Text(listing ? "拉取中......" : "拉取可用模型")
                        }
                        .font(T.sans(13.5))
                        .foregroundColor(T.accent)
                    }
                    .disabled(listing || ai.settings.apiKey.isEmpty)
                    .padding(.leading, 4)

                    if let modelError {
                        Text(modelError)
                            .font(T.sans(12)).foregroundColor(T.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 4)
                    }

                    if !models.isEmpty {
                        Panel(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(models.enumerated()), id: \.element) { idx, m in
                                    Button {
                                        ai.settings.model = m
                                    } label: {
                                        HStack {
                                            Text(m)
                                                .font(T.sans(14))
                                                .foregroundColor(T.text)
                                                .lineLimit(1)
                                            Spacer()
                                            if ai.settings.model == m {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(T.accent)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, T.pad).padding(.vertical, 11)

                                    if idx < models.count - 1 { Hair().padding(.leading, T.pad) }
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "题目难度")
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("跟着掌握程度自动走", isOn: $ai.settings.autoLevel)
                                .font(T.sans(15))
                                .tint(T.accent)

                            if ai.settings.autoLevel {
                                VStack(alignment: .leading, spacing: 6) {
                                    levelLine("新卡 / 还在学", "认得出")
                                    levelLine("记住了（稳定性 < 21 天）", "会套用")
                                    levelLine("熟了（稳定性 ≥ 21 天）", "会变形")
                                }
                            } else {
                                Picker("难度", selection: $ai.settings.fixedLevel) {
                                    ForEach(QuizLevel.allCases) { Text($0.label).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                Text(ai.settings.fixedLevel.blurb)
                                    .font(T.sans(12.5)).foregroundColor(T.faint)
                            }
                        }
                    }
                    Text("答题时按「这题太难了」，那张卡会单独降一档，而且刚才那道题会从题库里删掉。下次答对了自动升回来。")
                        .font(T.sans(12)).foregroundColor(T.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "出题参考几个薄弱点")
                    Panel {
                        HStack {
                            Text("\(ai.settings.weakHintCount) 个")
                                .font(T.sans(16, .semibold)).foregroundColor(T.text)
                            Spacer()
                            Stepper("", value: $ai.settings.weakHintCount, in: 0...15)
                                .labelsHidden()
                        }
                    }
                    Text("每次出题会把这一科里你错得最多的几个知识点告诉模型，让它专挑这些考。填 0 就是随机出。薄弱点按牌组分开记，不会串科。")
                        .font(T.sans(12)).foregroundColor(T.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }

                Button {
                    runTest()
                } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView().tint(T.text) }
                        Text(testing ? "连接中......" : "测试连接")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(testing || !ai.settings.configured)

                if let testResult {
                    Text(testResult)
                        .font(T.sans(13))
                        .foregroundColor(ok ? T.green : T.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)
                }

                Text("key 存在这台手机上，不会上传到别处。出题和批改的时候，卡片内容会发给你填的那个接口。")
                    .font(T.sans(12)).foregroundColor(T.faint)
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
        }
        .tint(T.accent)
    }

    private func levelLine(_ when: String, _ level: String) -> some View {
        HStack(spacing: 8) {
            Text(when)
                .font(T.sans(13)).foregroundColor(T.dim)
            Spacer()
            Tag(text: level, color: T.accent, bg: T.accentBg)
        }
    }

    private func fetchModels() {
        listing = true; modelError = nil
        let client = AIClient(settings: ai.settings)
        Task {
            do {
                let list = try await client.listModels()
                await MainActor.run { models = list; listing = false }
            } catch {
                await MainActor.run {
                    models = []
                    modelError = (error as? AIError)?.errorDescription ?? error.localizedDescription
                    listing = false
                }
            }
        }
    }

    private func runTest() {
        testing = true; testResult = nil
        let client = AIClient(settings: ai.settings)
        Task {
            do {
                let r = try await client.testConnection()
                await MainActor.run {
                    ok = true
                    testResult = "通了。模型回了：\(r.prefix(40))"
                    testing = false
                }
            } catch {
                await MainActor.run {
                    ok = false
                    testResult = (error as? AIError)?.errorDescription ?? error.localizedDescription
                    testing = false
                }
            }
        }
    }
}

// MARK: - 薄弱知识点

struct WeakPointsView: View {
    @EnvironmentObject var ai: AIStore
    @Environment(\.dismiss) private var dismiss
    let deckID: UUID
    let deckName: String
    @State private var showClear = false

    private var rows: [TagStat] { ai.sortedAll(deckID: deckID) }

    var body: some View {
        NavigationStack {
            Screen(title: "薄弱点", subtitle: rows.isEmpty ? deckName : "\(deckName) · 按该练的程度排") {
                if rows.isEmpty {
                    Panel {
                        Text("还没有记录。做几道 AI 出的题就有了。")
                            .font(T.sans(14)).foregroundColor(T.dim)
                    }
                } else {
                    Panel(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.tag) { idx, s in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.tag)
                                            .font(T.sans(15.5)).foregroundColor(T.text)
                                        Text("对 \(s.right) · 错 \(s.wrong)")
                                            .font(T.sans(12)).foregroundColor(T.faint)
                                    }
                                    Spacer()
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(T.sunken).frame(width: 54, height: 6)
                                        Capsule().fill(color(s.weakness))
                                            .frame(width: max(4, 54 * s.weakness), height: 6)
                                    }
                                    Text(String(format: "%.0f%%", s.weakness * 100))
                                        .font(T.sans(13, .semibold))
                                        .foregroundColor(color(s.weakness))
                                        .frame(width: 38, alignment: .trailing)
                                }
                                .padding(.horizontal, T.pad).padding(.vertical, 13)

                                if idx < rows.count - 1 {
                                    Hair().padding(.leading, T.pad)
                                }
                            }
                        }
                    }

                    Text("百分比是「下一次还会错」的粗略估计。样本少的时候会往中间收，不会因为错一次就冲到 100%。出题时优先挑排在前面的。\n\n每个牌组的薄弱点分开记，考数学不会被物理的错处干扰。")
                        .font(T.sans(12.5)).foregroundColor(T.faint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 4)

                    Button {
                        showClear = true
                    } label: {
                        Text("清空全部记录").foregroundColor(T.red)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(T.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }.tint(T.accent)
                }
            }
            .alert("清空「\(deckName)」的薄弱点记录？", isPresented: $showClear) {
                Button("取消", role: .cancel) { }
                Button("清空", role: .destructive) { ai.clearTags(deckID: deckID) }
            }
        }
        .tint(T.accent)
    }

    private func color(_ w: Double) -> Color {
        if w >= 0.6 { return T.red }
        if w >= 0.4 { return T.amber }
        return T.green
    }
}
