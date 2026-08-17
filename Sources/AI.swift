import Foundation

// MARK: - 配置

struct AISettings: Codable, Equatable {
    /// 任何 OpenAI 兼容的地址都行。填到域名就够，/v1/chat/completions 会自动补
    var baseURL: String = "https://api.deepseek.com"
    var apiKey: String = ""
    var model: String = "deepseek-v4-flash"
    /// 出题时最多参考几个薄弱知识点
    var weakHintCount: Int = 5

    var configured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 归一化成带 /v1 的根地址。填 .../zen/go 或 .../zen/go/v1 都能对
    var root: String {
        var s = baseURL.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/chat/completions") {
            s = String(s.dropLast("/chat/completions".count))
        }
        if !s.hasSuffix("/v1") { s += "/v1" }
        return s
    }

    var endpoint: URL? { URL(string: root + "/chat/completions") }
    var modelsEndpoint: URL? { URL(string: root + "/models") }
}

/// 几个常用接口，填的时候可以直接点
struct Preset: Identifiable {
    var id: String { name }
    let name: String
    let url: String
    let model: String
    let note: String

    static let all: [Preset] = [
        .init(name: "DeepSeek Flash", url: "https://api.deepseek.com",
              model: "deepseek-v4-flash",
              note: "便宜，中文数学够用。这个场景选它就行"),
        .init(name: "DeepSeek Pro", url: "https://api.deepseek.com",
              model: "deepseek-v4-pro",
              note: "贵十倍多，出公式题用不上。留给难题批改"),
        .init(name: "OpenCode Go", url: "https://opencode.ai/zen/go/v1",
              model: "", note: "订阅制。有 /v1/models，模型可以拉取"),
        .init(name: "OpenCode Zen", url: "https://opencode.ai/zen/v1",
              model: "", note: "按量付费。没有 /v1/models，模型名要手填"),
        .init(name: "硅基流动", url: "https://api.siliconflow.cn/v1",
              model: "", note: "国内，模型多"),
        .init(name: "OpenRouter", url: "https://openrouter.ai/api/v1",
              model: "", note: "聚合，什么模型都有"),
    ]
}

// MARK: - 题目与判分

enum QuizKind: String, Codable, CaseIterable {
    case reverse   // 给结果，要公式
    case scenario  // 给情景，要用法
    case cloze     // 挖空默写

    var label: String {
        switch self {
        case .reverse:  return "反着考"
        case .scenario: return "情景题"
        case .cloze:    return "挖空默写"
        }
    }
}

struct Quiz: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: QuizKind = .reverse
    var question: String = ""
    var reference: String = ""
    var hint: String = ""

    private enum CodingKeys: String, CodingKey { case kind, question, reference, hint }

    init(kind: QuizKind, question: String, reference: String, hint: String) {
        self.kind = kind; self.question = question; self.reference = reference; self.hint = hint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decode(String.self, forKey: .kind)) ?? "reverse"
        kind = QuizKind(rawValue: raw) ?? .reverse
        question  = (try? c.decode(String.self, forKey: .question))  ?? ""
        reference = (try? c.decode(String.self, forKey: .reference)) ?? ""
        hint      = (try? c.decode(String.self, forKey: .hint))      ?? ""
        id = UUID()
    }
}

/// 存进卡片里的原题。变体不入库，只从这里派生
struct StoredQuiz: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: QuizKind = .reverse
    var question: String = ""
    var reference: String = ""
    var hint: String = ""
    /// 这道题（含它派生出的变体）被用过几次
    var uses: Int = 0
    var lastUsed: Date? = nil

    init() {}

    init(_ quiz: Quiz) {
        kind = quiz.kind
        question = quiz.question
        reference = quiz.reference
        hint = quiz.hint
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = (try? c.decode(UUID.self,   forKey: .id))        ?? UUID()
        let raw   = (try? c.decode(String.self, forKey: .kind))      ?? "reverse"
        kind      = QuizKind(rawValue: raw) ?? .reverse
        question  = (try? c.decode(String.self, forKey: .question))  ?? ""
        reference = (try? c.decode(String.self, forKey: .reference)) ?? ""
        hint      = (try? c.decode(String.self, forKey: .hint))      ?? ""
        uses      = (try? c.decode(Int.self,    forKey: .uses))      ?? 0
        lastUsed  = try? c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? nil
    }

    var asQuiz: Quiz {
        Quiz(kind: kind, question: question, reference: reference, hint: hint)
    }
}

/// 这一轮出题怎么来
enum QuizPlan {
    /// 全新生成，一次完整调用
    case fresh
    /// 原样复用库里的题，零调用
    case reuse(StoredQuiz)
    /// 拿库里的原题现生成一个变体，一次小调用
    case variant(StoredQuiz)

    var label: String {
        switch self {
        case .fresh:   return "新题"
        case .reuse:   return "复习旧题"
        case .variant: return "旧题变体"
        }
    }
}

enum QuizPlanner {
    /// 题库存到几道就可以开始复用
    static let minBank = 3
    /// 最多存几道原题
    static let cap = 8

    static func plan(for card: Card) -> QuizPlan {
        // 上次答错了，说明这个点还没通，出新的正面刚一次
        if card.lastQuizWrong { return .fresh }
        if card.quizBank.count < minBank { return .fresh }

        // 挑用得最少的；用得一样多就挑最久没见的
        let candidate = card.quizBank.min { a, b in
            if a.uses != b.uses { return a.uses < b.uses }
            return (a.lastUsed ?? .distantPast) < (b.lastUsed ?? .distantPast)
        }
        guard let candidate else { return .fresh }

        // 存了还没上过场的，原样用，省一次调用
        if candidate.uses == 0 { return .reuse(candidate) }
        // 见过了，换个数字换个情境，免得变成背答案
        return .variant(candidate)
    }

    /// 断网或者接口挂了的兜底：库里随便挑一道最久没见的
    static func fallback(for card: Card) -> StoredQuiz? {
        card.quizBank.min { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    }
}

struct Judgement: Codable, Equatable {
    var correct: Bool = false
    var score: Int = 0
    var comment: String = ""
    var wrongStep: String = ""
    var tags: [String] = []

    private enum CodingKeys: String, CodingKey { case correct, score, comment, wrongStep, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        correct   = (try? c.decode(Bool.self, forKey: .correct))     ?? false
        score     = (try? c.decode(Int.self, forKey: .score))        ?? (correct ? 100 : 0)
        comment   = (try? c.decode(String.self, forKey: .comment))   ?? ""
        wrongStep = (try? c.decode(String.self, forKey: .wrongStep)) ?? ""
        tags      = (try? c.decode([String].self, forKey: .tags))    ?? []
    }

    /// 判分结果映射到复习按钮的默认选择，用户还能改
    var suggestedGrade: Grade {
        if !correct { return .again }
        if score >= 95 { return .easy }
        if score >= 75 { return .good }
        return .hard
    }
}

// MARK: - 薄弱知识点

struct TagStat: Codable, Equatable {
    var tag: String = ""
    var wrong: Int = 0
    var right: Int = 0
    var lastSeen: Date = Date()

    var total: Int { wrong + right }
    /// 错误率，样本少的时候往中间收一点，免得一次错就排到最前面
    var weakness: Double {
        Double(wrong + 1) / Double(total + 2)
    }
}

final class AIStore: ObservableObject {
    @Published var settings: AISettings {
        didSet { saveSettings() }
    }
    @Published var tags: [String: TagStat] = [:]

    private let settingsKey = "ai.settings.v1"

    private var tagsURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("weakpoints.json")
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(AISettings.self, from: data) {
            settings = s
        } else {
            settings = AISettings()
        }
        loadTags()
    }

    private func saveSettings() {
        if let d = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(d, forKey: settingsKey)
        }
    }

    private func loadTags() {
        guard let d = try? Data(contentsOf: tagsURL),
              let t = try? JSONDecoder().decode([String: TagStat].self, from: d) else { return }
        tags = t
    }

    private func saveTags() {
        guard let d = try? JSONEncoder().encode(tags) else { return }
        try? d.write(to: tagsURL, options: .atomic)
    }

    func record(_ judgement: Judgement) {
        for raw in judgement.tags {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.count <= 20 else { continue }
            var s = tags[t] ?? TagStat(tag: t)
            if judgement.correct { s.right += 1 } else { s.wrong += 1 }
            s.lastSeen = Date()
            tags[t] = s
        }
        saveTags()
    }

    func clearTags() {
        tags = [:]
        saveTags()
    }

    /// 最该练的几个知识点
    func weakest(_ n: Int) -> [TagStat] {
        tags.values
            .filter { $0.wrong > 0 }
            .sorted {
                if $0.weakness == $1.weakness { return $0.wrong > $1.wrong }
                return $0.weakness > $1.weakness
            }
            .prefix(n)
            .map { $0 }
    }

    var sortedAll: [TagStat] {
        tags.values.sorted {
            if $0.weakness == $1.weakness { return $0.total > $1.total }
            return $0.weakness > $1.weakness
        }
    }
}

// MARK: - 调 API

enum AIError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int, String)
    case emptyReply
    case badJSON(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没填 API 地址和 key。"
        case .badURL:        return "API 地址填得不对。"
        case .http(let c, let b):
            return "接口返回 \(c)。\(b.prefix(300))"
        case .emptyReply:    return "模型没返回内容。"
        case .badJSON(let s):
            return "模型返回的不是能用的 JSON：\n\(s.prefix(300))"
        case .network(let s): return "网络出错：\(s)"
        }
    }
}

struct AIClient {
    let settings: AISettings

    private struct ChatRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        let choices: [Choice]?
    }

    func chat(system: String, user: String, temperature: Double = 0.7) async throws -> String {
        guard settings.configured else { throw AIError.notConfigured }
        guard let url = settings.endpoint else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(settings.apiKey.trimmingCharacters(in: .whitespaces))",
                     forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: settings.model.trimmingCharacters(in: .whitespaces),
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ],
            temperature: temperature
        )
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices?.first?.message?.content,
              !content.isEmpty
        else { throw AIError.emptyReply }

        return content
    }

    // 下面两段 system 是**每次调用完全一样**的，放在最前面，
    // 变量只出现在 user 里且尽量短 —— 这样前缀缓存才有可能命中。
    // 顺序反了的话（长规则在变量后面）公共前缀就只剩几个字，等于没有缓存。

    private static let quizSystem = """
    你是一个数学公式训练的出题器。

    用户会给你一张公式卡的正面和背面，以及这个学生最近做错过的知识点。
    你据此出一道题。

    题型三选一，优先挑能戳到学生弱点的那一种：
    1. reverse —— 给出结果、形式或者一句描述，让学生说出对应的公式
    2. scenario —— 给一个具体的小情景或小题目，让学生说该用哪个公式、怎么代进去
    3. cloze —— 把公式挖掉一部分，让学生把缺的补出来

    硬性要求：
    - 一两句话或者一个式子就能作答，不要出需要长篇演算的大题
    - 题面里不许出现答案
    - reference 写完整的参考答案
    - hint 写一句提示，给卡住的学生看，不要直接把答案说了
    - 学生用手机作答，不要求写完整过程

    只输出 JSON，不要 markdown 代码块，不要任何多余的话，格式：
    {"kind":"reverse","question":"","reference":"","hint":""}
    """

    private static let judgeSystem = """
    你是一个严格但讲道理的数学批改老师。

    用户会给你：题目、参考答案、这道题考的原始公式卡、学生的作答。
    你判断学生答得对不对。

    判断标准：
    - 数学上等价的写法都算对。比如 -b/2a、−b/(2a)、x=-b/2a 是同一个答案
    - 学生在手机上打字，符号、括号、上下标的小笔误只要不影响意思就算对，但要在 comment 里点一句
    - 题目没要求过程的，只写结果也算对
    - 空着、完全不会、答非所问，算错

    各字段怎么填：
    - comment：讲清楚为什么对或错。错的话要把正确思路完整说一遍，别只甩答案
    - wrongStep：具体错在哪一步。答对就填空字符串
    - tags：这道题涉及的知识点，2 到 4 个短词，用统一的叫法，
      比如「二次函数顶点」「等差数列通项」「余弦定理」，不要每次换说法
    - score：0 到 100

    只输出 JSON，不要 markdown 代码块，不要任何多余的话，格式：
    {"correct":true,"score":0,"comment":"","wrongStep":"","tags":[]}
    """

    /// 出题
    func makeQuiz(card: Card, weak: [TagStat]) async throws -> Quiz {
        let weakLine = weak.isEmpty
            ? "（暂时没有记录）"
            : weak.map { "\($0.tag)（错 \($0.wrong) 次）" }.joined(separator: "、")

        let user = """
        正面：\(card.front)
        背面：\(card.back)
        最近错过：\(weakLine)
        """

        let raw = try await chat(system: AIClient.quizSystem, user: user, temperature: 0.9)

        guard let json = AIClient.extractJSON(raw),
              let data = json.data(using: .utf8),
              let quiz = try? JSONDecoder().decode(Quiz.self, from: data),
              !quiz.question.isEmpty
        else { throw AIError.badJSON(raw) }

        return quiz
    }

    /// 判分
    func judge(quiz: Quiz, answer: String, card: Card) async throws -> Judgement {
        let user = """
        题目：\(quiz.question)
        参考答案：\(quiz.reference)
        原始公式卡：\(card.front) → \(card.back)
        学生作答：\(answer.isEmpty ? "（空着没答）" : answer)
        """

        let raw = try await chat(system: AIClient.judgeSystem, user: user, temperature: 0.2)

        guard let json = AIClient.extractJSON(raw),
              let data = json.data(using: .utf8),
              let j = try? JSONDecoder().decode(Judgement.self, from: data)
        else { throw AIError.badJSON(raw) }

        return j
    }

    private static let variantSystem = """
    你是一个出题变体生成器。

    用户会给你一道已经出过的题、它的参考答案，以及这道题背后的公式卡。
    你把它改写成一道等价难度的新题。

    硬性要求：
    - 考的知识点必须完全一样，难度不许升也不许降
    - 换数字、换情境、换问法，三样至少动两样
    - 不许只改标点或者调语序。学生见过原题，要让他没法凭印象直接背出答案
    - 换了数字就必须把参考答案重新算一遍，算准
    - 题面里不许出现答案
    - 一两句话或者一个式子就能作答

    只输出 JSON，不要 markdown 代码块，不要任何多余的话，格式：
    {"kind":"reverse","question":"","reference":"","hint":""}
    """

    /// 拿一道旧题现生成变体。prompt 比出新题小得多
    func makeVariant(of stored: StoredQuiz, card: Card) async throws -> Quiz {
        let user = """
        原题：\(stored.question)
        参考答案：\(stored.reference)
        公式卡：\(card.front) → \(card.back)
        """

        let raw = try await chat(system: AIClient.variantSystem, user: user, temperature: 1.0)

        guard let json = AIClient.extractJSON(raw),
              let data = json.data(using: .utf8),
              let quiz = try? JSONDecoder().decode(Quiz.self, from: data),
              !quiz.question.isEmpty
        else { throw AIError.badJSON(raw) }

        return quiz
    }

    /// 拉可用模型列表。OpenCode Go、硅基流动、OpenRouter 都支持；Zen 不支持，会报 404
    func listModels() async throws -> [String] {
        guard !settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIError.notConfigured
        }
        guard let url = settings.modelsEndpoint else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        req.setValue("Bearer \(settings.apiKey.trimmingCharacters(in: .whitespaces))",
                     forHTTPHeaderField: "Authorization")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIError.http(http.statusCode,
                               http.statusCode == 404
                               ? "这个接口没有 /v1/models，模型名只能手填。"
                               : (String(data: data, encoding: .utf8) ?? ""))
        }

        struct ModelList: Decodable {
            struct Item: Decodable { let id: String }
            let data: [Item]?
        }
        guard let decoded = try? JSONDecoder().decode(ModelList.self, from: data),
              let items = decoded.data, !items.isEmpty
        else { throw AIError.badJSON(String(data: data, encoding: .utf8) ?? "") }

        return items.map { $0.id }.sorted()
    }

    func testConnection() async throws -> String {
        try await chat(system: "你是一个测试用的助手。",
                       user: "只回复两个字：正常", temperature: 0)
    }

    /// 模型爱在 JSON 外面裹一层 ```json 或者说明文字，这里剥掉
    static func extractJSON(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "```") {
            s = String(s[r.upperBound...])
            if s.lowercased().hasPrefix("json") { s = String(s.dropFirst(4)) }
            if let end = s.range(of: "```") { s = String(s[..<end.lowerBound]) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end
        else { return nil }
        return String(s[start...end])
    }
}

// MARK: - 数学符号快捷输入

enum MathKeys {
    static let all: [String] = [
        "=", "≠", "≤", "≥", "±", "×", "÷", "√", "^", "_",
        "²", "³", "ⁿ", "₁", "₂", "ₙ", "π", "∞", "°",
        "α", "β", "θ", "Δ", "Σ", "∫", "→", "∈", "∩", "∪", "⊆", "∅",
        "(", ")", "|"
    ]
}
