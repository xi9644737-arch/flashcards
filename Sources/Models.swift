import Foundation
import UIKit

// MARK: - 卡片

struct Card: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    var frontImage: Data? = nil
    var backImage: Data? = nil

    /// 到期时间。新卡是 1970，永远算「已到期」
    var due: Date = Date(timeIntervalSince1970: 0)
    /// 当前间隔，单位天
    var interval: Double = 0
    /// SM-2 用的难度系数
    var ease: Double = 2.5
    var reps: Int = 0
    var lapses: Int = 0
    /// 0 新卡 / 1 学习或重学中 / 2 复习中
    var state: Int = 0

    /// FSRS 记忆状态：稳定性（天）
    var stability: Double = 0
    /// FSRS 记忆状态：难度 1–10
    var difficulty: Double = 0
    /// 上一次复习时间，算 FSRS 的可提取性要用
    var lastReview: Date? = nil

    /// 出过的题，只存原题。变体从原题现生成，不入库，免得越变越飘
    var quizBank: [StoredQuiz] = []
    /// 上一次 AI 出题答错没有。错了下次就出全新的，不复用
    var lastQuizWrong: Bool = false
    /// 出题难度：0 认得出 / 1 会套用 / 2 会变形。从最低档起步，答对了才往上走
    var quizLevel: Int = 0
    /// 当前档连对几次。连对两次升一档
    var quizStreak: Int = 0

    init(front: String = "", back: String = "") {
        self.front = front
        self.back = back
    }

    /// 手写解码：以后再加字段，旧的 json 也不会解不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = (try? c.decode(UUID.self,   forKey: .id))         ?? UUID()
        front      = (try? c.decode(String.self, forKey: .front))      ?? ""
        back       = (try? c.decode(String.self, forKey: .back))       ?? ""
        frontImage = try? c.decodeIfPresent(Data.self, forKey: .frontImage) ?? nil
        backImage  = try? c.decodeIfPresent(Data.self, forKey: .backImage)  ?? nil
        due        = (try? c.decode(Date.self,   forKey: .due))        ?? Date(timeIntervalSince1970: 0)
        interval   = (try? c.decode(Double.self, forKey: .interval))   ?? 0
        ease       = (try? c.decode(Double.self, forKey: .ease))       ?? 2.5
        reps       = (try? c.decode(Int.self,    forKey: .reps))       ?? 0
        lapses     = (try? c.decode(Int.self,    forKey: .lapses))     ?? 0
        state      = (try? c.decode(Int.self,    forKey: .state))      ?? 0
        stability  = (try? c.decode(Double.self, forKey: .stability))  ?? 0
        difficulty = (try? c.decode(Double.self, forKey: .difficulty)) ?? 0
        lastReview = try? c.decodeIfPresent(Date.self, forKey: .lastReview) ?? nil
        quizBank   = (try? c.decode([StoredQuiz].self, forKey: .quizBank)) ?? []
        lastQuizWrong = (try? c.decode(Bool.self, forKey: .lastQuizWrong)) ?? false
        quizLevel     = (try? c.decode(Int.self,  forKey: .quizLevel))     ?? 0
        quizStreak    = (try? c.decode(Int.self,  forKey: .quizStreak))    ?? 0
    }

    var stateName: String {
        switch state {
        case 0:  return "新"
        case 1:  return "学习"
        default: return "复习"
        }
    }

    var hasText: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isBlank: Bool {
        front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && frontImage == nil && backImage == nil
    }
}

/// 一次月考的成绩
struct ExamRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var total: Int = 0
    var correct: Int = 0
    /// 判分的平均分，比对错率细一点
    var avgScore: Int = 0
    /// 这次考砸的知识点
    var weakTags: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = (try? c.decode(UUID.self,     forKey: .id))       ?? UUID()
        date     = (try? c.decode(Date.self,     forKey: .date))     ?? Date()
        total    = (try? c.decode(Int.self,      forKey: .total))    ?? 0
        correct  = (try? c.decode(Int.self,      forKey: .correct))  ?? 0
        avgScore = (try? c.decode(Int.self,      forKey: .avgScore)) ?? 0
        weakTags = (try? c.decode([String].self, forKey: .weakTags)) ?? []
    }

    var rate: Int { total == 0 ? 0 : Int((Double(correct) / Double(total) * 100).rounded()) }
}

struct Deck: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var cards: [Card] = []
    /// 历次月考成绩，按时间正序
    var exams: [ExamRecord] = []

    init(name: String = "", cards: [Card] = []) {
        self.name = name
        self.cards = cards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = (try? c.decode(UUID.self,   forKey: .id))    ?? UUID()
        name  = (try? c.decode(String.self, forKey: .name))  ?? ""
        cards = (try? c.decode([Card].self, forKey: .cards)) ?? []
        exams = (try? c.decode([ExamRecord].self, forKey: .exams)) ?? []
    }

    var lastExam: ExamRecord? { exams.last }

    /// 够不够格开考：卡片够多，且从没考过或者上次考完满一个月了
    var examDue: Bool {
        guard cards.filter({ $0.hasText }).count >= 10 else { return false }
        guard let last = lastExam else { return true }
        return Date().timeIntervalSince(last.date) >= 30 * 86400
    }

    var daysSinceExam: Int? {
        guard let last = lastExam else { return nil }
        return Int(Date().timeIntervalSince(last.date) / 86400)
    }

    func dueCards(at date: Date = Date()) -> [Card] {
        cards.filter { $0.due <= date }.sorted { $0.due < $1.due }
    }

    func counts(at date: Date = Date()) -> (new: Int, learn: Int, review: Int) {
        var n = 0, l = 0, r = 0
        for c in cards where c.due <= date {
            switch c.state {
            case 0:  n += 1
            case 1:  l += 1
            default: r += 1
            }
        }
        return (n, l, r)
    }

    var dueTotal: Int {
        let c = counts()
        return c.new + c.learn + c.review
    }
}

// MARK: - 评分

enum Grade: Int, CaseIterable, Identifiable {
    case again = 0, hard, good, easy
    var id: Int { rawValue }

    /// FSRS 里的 1–4
    var rating: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .again: return "重来"
        case .hard:  return "困难"
        case .good:  return "良好"
        case .easy:  return "简单"
        }
    }
}

// MARK: - 调度配置

enum Algorithm: String, Codable, CaseIterable, Identifiable {
    case fsrs, sm2
    var id: String { rawValue }
    var label: String { self == .fsrs ? "FSRS" : "SM-2" }
    var blurb: String {
        switch self {
        case .fsrs:
            return "按记忆模型算：每张卡单独估「稳定性」和「难度」，再倒推什么时候会忘到设定的比例。间隔更贴合你自己，长期下来复习量明显更少。"
        case .sm2:
            return "老式的倍数递增：答对就把上次间隔乘一个系数。简单、可预测，但对难卡和易卡一视同仁。"
        }
    }
}

struct SchedulerConfig: Codable, Equatable {
    var algorithm: Algorithm = .fsrs
    /// 目标记忆保持率：到期那天你还记得的概率
    var requestRetention: Double = 0.9
    /// 间隔上限，天
    var maximumInterval: Double = 365 * 5
}

// MARK: - FSRS-4.5

enum FSRS {
    static let decay: Double = -0.5
    /// 0.9 ^ (1/decay) - 1
    static let factor: Double = pow(0.9, 1.0 / -0.5) - 1.0

    /// FSRS-4.5 默认参数。以后攒够复习记录可以重新拟合，先用官方默认值
    static let w: [Double] = [
        0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.0310,
        1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.5870, 0.2272, 2.8755
    ]

    /// 距上次复习 t 天之后，还记得的概率
    static func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        guard s > 0 else { return 0 }
        return pow(1 + factor * t / s, decay)
    }

    /// 让记忆衰减到 requestRetention 需要多少天
    static func interval(stability s: Double, config: SchedulerConfig) -> Double {
        guard s > 0 else { return 1 }
        let raw = s / factor * (pow(config.requestRetention, 1.0 / decay) - 1)
        return min(max(raw.rounded(), 1), config.maximumInterval)
    }

    static func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    static func initStability(_ rating: Int) -> Double {
        max(w[max(0, min(3, rating - 1))], 0.1)
    }

    static func initDifficulty(_ rating: Int) -> Double {
        clampDifficulty(w[4] - w[5] * Double(rating - 3))
    }

    static func nextDifficulty(_ d: Double, _ rating: Int) -> Double {
        let moved = d - w[6] * Double(rating - 3)
        // 往初始难度收一点，免得一路漂到两头
        return clampDifficulty(w[7] * w[4] + (1 - w[7]) * moved)
    }

    static func nextRecallStability(d: Double, s: Double, r: Double, rating: Int) -> Double {
        let hardPenalty = rating == 2 ? w[15] : 1.0
        let easyBonus   = rating == 4 ? w[16] : 1.0
        let grow = exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1)
        return max(0.1, s * (1 + grow * hardPenalty * easyBonus))
    }

    static func nextForgetStability(d: Double, s: Double, r: Double) -> Double {
        max(0.1, w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14]))
    }
}

// MARK: - 调度

enum Scheduler {
    static let day: TimeInterval = 86400
    static let minute: TimeInterval = 60

    static func apply(_ card: inout Card, _ grade: Grade,
                      config: SchedulerConfig = SchedulerConfig(),
                      now: Date = Date()) {
        switch config.algorithm {
        case .fsrs: applyFSRS(&card, grade, config: config, now: now)
        case .sm2:  applySM2(&card, grade, now: now)
        }
        card.reps += 1
    }

    // MARK: FSRS

    private static func applyFSRS(_ card: inout Card, _ grade: Grade,
                                  config: SchedulerConfig, now: Date) {
        let rating = grade.rating

        if card.state == 0 || card.state == 1 {
            // 新卡和重学中的卡先走分钟级短步骤，跟 Anki 一个思路
            switch grade {
            case .again:
                card.state = 1
                card.due = now.addingTimeInterval(1 * minute)
            case .hard:
                card.state = 1
                card.due = now.addingTimeInterval(6 * minute)
            case .good:
                if card.state == 1 && card.reps > 0 {
                    graduate(&card, rating: rating, config: config, now: now)
                } else {
                    card.state = 1
                    card.due = now.addingTimeInterval(10 * minute)
                }
            case .easy:
                graduate(&card, rating: rating, config: config, now: now)
            }
            return
        }

        // 已经在复习状态
        let elapsed = max(0, now.timeIntervalSince(card.lastReview ?? now) / day)
        let r = FSRS.retrievability(elapsedDays: elapsed, stability: card.stability)
        let newD = FSRS.nextDifficulty(card.difficulty, rating)

        if grade == .again {
            card.lapses += 1
            card.stability = FSRS.nextForgetStability(d: card.difficulty, s: card.stability, r: r)
            card.difficulty = newD
            card.state = 1                       // 进重学
            card.interval = 0
            card.due = now.addingTimeInterval(10 * minute)
        } else {
            card.stability = FSRS.nextRecallStability(
                d: card.difficulty, s: card.stability, r: r, rating: rating)
            card.difficulty = newD
            card.interval = FSRS.interval(stability: card.stability, config: config)
            card.due = now.addingTimeInterval(card.interval * day)
        }
        card.lastReview = now
    }

    /// 从学习状态毕业进复习。重学过的卡保留已有的稳定性，不重新初始化
    private static func graduate(_ card: inout Card, rating: Int,
                                 config: SchedulerConfig, now: Date) {
        if card.stability <= 0 {
            card.stability = FSRS.initStability(rating)
            card.difficulty = FSRS.initDifficulty(rating)
        }
        card.state = 2
        card.interval = FSRS.interval(stability: card.stability, config: config)
        card.due = now.addingTimeInterval(card.interval * day)
        card.lastReview = now
    }

    // MARK: SM-2

    private static func applySM2(_ card: inout Card, _ grade: Grade, now: Date) {
        if card.state == 0 || card.state == 1 {
            switch grade {
            case .again:
                card.state = 1
                card.due = now.addingTimeInterval(1 * minute)
            case .hard:
                card.state = 1
                card.due = now.addingTimeInterval(6 * minute)
            case .good:
                if card.state == 1 && card.reps > 0 {
                    card.state = 2; card.interval = 1
                    card.due = now.addingTimeInterval(day)
                } else {
                    card.state = 1
                    card.due = now.addingTimeInterval(10 * minute)
                }
            case .easy:
                card.state = 2; card.interval = 4
                card.due = now.addingTimeInterval(4 * day)
            }
        } else {
            switch grade {
            case .again:
                card.lapses += 1
                card.ease = max(1.3, card.ease - 0.2)
                card.state = 1; card.interval = 0
                card.due = now.addingTimeInterval(10 * minute)
            case .hard:
                card.ease = max(1.3, card.ease - 0.15)
                card.interval = max(1, (card.interval * 1.2).rounded())
                card.due = now.addingTimeInterval(card.interval * day)
            case .good:
                card.interval = max(1, (card.interval * card.ease).rounded())
                card.due = now.addingTimeInterval(card.interval * day)
            case .easy:
                card.ease += 0.15
                card.interval = max(1, (card.interval * card.ease * 1.3).rounded())
                card.due = now.addingTimeInterval(card.interval * day)
            }
        }
        card.lastReview = now
    }

    /// 按钮上显示的「按这个评分，下次什么时候再见」
    static func preview(_ card: Card, _ grade: Grade, config: SchedulerConfig) -> String {
        var copy = card
        apply(&copy, grade, config: config)
        let d = copy.due.timeIntervalSinceNow
        if d < 50 * minute { return "\(max(1, Int((d / minute).rounded())))分" }
        if d < day         { return "\(max(1, Int((d / (60 * minute)).rounded())))时" }
        if d < 30 * day    { return "\(max(1, Int((d / day).rounded())))天" }
        if d < 365 * day   { return String(format: "%.1f月", d / (30 * day)) }
        return String(format: "%.1f年", d / (365 * day))
    }
}

// MARK: - 复习流水（留着以后拟合 FSRS 参数用）

struct ReviewLog: Codable {
    var cardID: UUID
    var date: Date
    var rating: Int
    var stateBefore: Int
    var elapsedDays: Double
    var stabilityAfter: Double
    var difficultyAfter: Double
}

// MARK: - 存储

final class Store: ObservableObject {
    @Published var decks: [Deck] = []
    @Published var config: SchedulerConfig {
        didSet { saveConfig() }
    }

    private let configKey = "scheduler.config.v1"
    private let maxLogs = 8000

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var fileURL: URL { dir.appendingPathComponent("decks.json") }
    private var logURL: URL { dir.appendingPathComponent("reviewlog.json") }

    init() {
        if let d = UserDefaults.standard.data(forKey: configKey),
           let c = try? JSONDecoder().decode(SchedulerConfig.self, from: d) {
            config = c
        } else {
            config = SchedulerConfig()
        }
        load()
        if decks.isEmpty {
            decks = [Store.starterDeck]
            save()
        }
    }

    private func saveConfig() {
        if let d = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(d, forKey: configKey)
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Deck].self, from: data)
        else { return }
        decks = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(decks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func index(of id: UUID) -> Int? { decks.firstIndex { $0.id == id } }

    // MARK: 导入合并

    /// 用正面当主键：去掉空格、统一大小写。同一张卡不管导几次都认得出来
    static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .lowercased()
    }

    /// 合并导入：正面相同的改答案、保留复习进度；没见过的才新增
    @discardableResult
    func merge(_ incoming: [Card], into deckID: UUID) -> ImportResult {
        guard let di = index(of: deckID) else { return ImportResult() }
        var result = ImportResult()

        var map: [String: Int] = [:]
        for (i, c) in decks[di].cards.enumerated() {
            let k = Store.key(c.front)
            if !k.isEmpty && map[k] == nil { map[k] = i }
        }

        for card in incoming {
            let k = Store.key(card.front)
            if k.isEmpty { continue }
            if let i = map[k] {
                if decks[di].cards[i].back == card.back {
                    result.unchanged += 1
                } else {
                    // 只换答案，due / stability / difficulty / reps 全部留着
                    decks[di].cards[i].back = card.back
                    result.updated += 1
                }
            } else {
                decks[di].cards.append(card)
                map[k] = decks[di].cards.count - 1
                result.added += 1
            }
        }

        // 卡库里有、这次文件里没有的，报一下但不删
        let incomingKeys = Set(incoming.map { Store.key($0.front) })
        result.orphans = decks[di].cards.filter {
            let k = Store.key($0.front)
            return !k.isEmpty && !incomingKeys.contains(k)
        }.count

        save()
        return result
    }

    // MARK: 题库

    private func withCard(_ deckID: UUID, _ cardID: UUID, _ body: (inout Card) -> Void) {
        guard let di = index(of: deckID),
              let ci = decks[di].cards.firstIndex(where: { $0.id == cardID }) else { return }
        body(&decks[di].cards[ci])
        save()
    }

    /// 新题入库。超上限就淘汰用得最多、最久没用的那道
    func addQuiz(_ quiz: Quiz, cardID: UUID, in deckID: UUID) {
        withCard(deckID, cardID) { card in
            var stored = StoredQuiz(quiz)
            stored.uses = 1
            stored.lastUsed = Date()
            card.quizBank.append(stored)
            if card.quizBank.count > QuizPlanner.cap {
                card.quizBank.sort { a, b in
                    if a.uses != b.uses { return a.uses > b.uses }
                    return (a.lastUsed ?? .distantPast) < (b.lastUsed ?? .distantPast)
                }
                card.quizBank.removeFirst(card.quizBank.count - QuizPlanner.cap)
            }
        }
    }

    func markQuizUsed(_ quizID: UUID, cardID: UUID, in deckID: UUID) {
        withCard(deckID, cardID) { card in
            guard let i = card.quizBank.firstIndex(where: { $0.id == quizID }) else { return }
            card.quizBank[i].uses += 1
            card.quizBank[i].lastUsed = Date()
        }
    }

    /// 答完一题：记对错，按表现升降档。返回档位变没变，好在界面上说一声
    @discardableResult
    func recordQuizResult(correct: Bool, cardID: UUID, in deckID: UUID) -> LevelChange {
        var change = LevelChange.none
        withCard(deckID, cardID) { card in
            card.lastQuizWrong = !correct
            let before = card.quizLevel
            if correct {
                card.quizStreak += 1
                if card.quizStreak >= QuizPlanner.promoteAfter && card.quizLevel < 2 {
                    card.quizLevel += 1
                    card.quizStreak = 0
                }
            } else {
                card.quizStreak = 0
                card.quizLevel = max(0, card.quizLevel - 1)
            }
            if card.quizLevel > before { change = .up(card.quizLevel) }
            else if card.quizLevel < before { change = .down(card.quizLevel) }
        }
        return change
    }

    func addExam(_ record: ExamRecord, to deckID: UUID) {
        guard let di = index(of: deckID) else { return }
        decks[di].exams.append(record)
        if decks[di].exams.count > 24 { decks[di].exams.removeFirst() }
        save()
    }

    /// 手动升降一档。降档时顺手把刚才那道题从库里扔掉
    func nudgeQuizLevel(by delta: Int, dropQuiz quizID: UUID?, cardID: UUID, in deckID: UUID) {
        withCard(deckID, cardID) { card in
            card.quizLevel = min(2, max(0, card.quizLevel + delta))
            card.quizStreak = 0
            if delta < 0, let quizID { card.quizBank.removeAll { $0.id == quizID } }
        }
    }

    /// 纯追加，不查重
    func appendCards(_ incoming: [Card], into deckID: UUID) -> ImportResult {
        guard let di = index(of: deckID) else { return ImportResult() }
        decks[di].cards.append(contentsOf: incoming)
        save()
        var r = ImportResult()
        r.added = incoming.count
        return r
    }

    /// 统一的答题入口：改状态、写流水、存盘
    func answer(deckID: UUID, cardID: UUID, grade: Grade) {
        guard let di = index(of: deckID),
              let ci = decks[di].cards.firstIndex(where: { $0.id == cardID })
        else { return }

        let before = decks[di].cards[ci]
        let elapsed = before.lastReview.map { max(0, Date().timeIntervalSince($0) / 86400) } ?? 0

        Scheduler.apply(&decks[di].cards[ci], grade, config: config)
        let after = decks[di].cards[ci]

        appendLog(ReviewLog(cardID: cardID, date: Date(), rating: grade.rating,
                            stateBefore: before.state, elapsedDays: elapsed,
                            stabilityAfter: after.stability,
                            difficultyAfter: after.difficulty))
        save()
    }

    private func appendLog(_ log: ReviewLog) {
        var logs = loadLogs()
        logs.append(log)
        if logs.count > maxLogs { logs.removeFirst(logs.count - maxLogs) }
        if let d = try? JSONEncoder().encode(logs) {
            try? d.write(to: logURL, options: .atomic)
        }
    }

    func loadLogs() -> [ReviewLog] {
        guard let d = try? Data(contentsOf: logURL),
              let l = try? JSONDecoder().decode([ReviewLog].self, from: d)
        else { return [] }
        return l
    }

    var logCount: Int { loadLogs().count }

    func exportData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return (try? encoder.encode(decks)) ?? Data()
    }

    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode([Deck].self, from: data) else { return false }
        decks = decoded
        save()
        return true
    }

    static var starterDeck: Deck {
        Deck(name: "公式", cards: [
            Card(front: "二次函数 y = ax² + bx + c，顶点横坐标", back: "x = −b / (2a)"),
            Card(front: "A ∩ B", back: "交集：既属于 A，又属于 B"),
            Card(front: "A ∪ B", back: "并集：属于 A，或属于 B，或两个都属于"),
            Card(front: "等差数列通项公式", back: "aₙ = a₁ + (n − 1)d"),
            Card(front: "等比数列通项公式", back: "aₙ = a₁ · qⁿ⁻¹"),
        ])
    }
}

// MARK: - 导入

struct ImportResult {
    var added = 0
    var updated = 0
    var unchanged = 0
    /// 卡库里有、但这次导入的文件里没有的
    var orphans = 0

    var summary: String {
        var parts: [String] = []
        if added > 0     { parts.append("新增 \(added)") }
        if updated > 0   { parts.append("更新 \(updated)") }
        if unchanged > 0 { parts.append("没变 \(unchanged)") }
        if parts.isEmpty { return "什么也没导进去。" }
        var s = parts.joined(separator: " · ")
        if orphans > 0 { s += "\n另有 \(orphans) 张卡这份文件里没有，已保留。" }
        return s
    }
}

enum ImportStrategy: String, CaseIterable, Identifiable {
    case merge  = "合并更新"
    case append = "直接追加"
    var id: String { rawValue }

    var hint: String {
        switch self {
        case .merge:
            return "用正面当主键。已有的卡只换答案，复习进度全部保留；没见过的才新增。资料改了重导一遍就行，不会变成两份。"
        case .append:
            return "不查重，全部当新卡加进去。只在确实要放一批全新内容时用。"
        }
    }
}

// MARK: - 批量导入的解析

enum ImportMode: String, CaseIterable, Identifiable {
    case oneLine = "一行一张"
    case blank   = "空行分隔"
    case csv     = "CSV"
    var id: String { rawValue }

    var hint: String {
        switch self {
        case .oneLine:
            return "每行一张卡。正面和背面用 Tab、竖线、逗号或破折号隔开都行。\n例：顶点横坐标 | x = −b/(2a)"
        case .blank:
            return "第一行正面，后面几行是背面，卡与卡之间空一行。"
        case .csv:
            return "标准 CSV，前两列当正面和背面。带引号、字段里有逗号都能正确处理。表头会自动跳过。"
        }
    }

    /// 按文件名猜格式
    static func guess(from filename: String) -> ImportMode {
        filename.lowercased().hasSuffix(".csv") ? .csv : .oneLine
    }
}

enum CardParser {
    static func parse(_ raw: String, mode: ImportMode) -> [Card] {
        switch mode {
        case .oneLine: return parseOneLine(raw)
        case .blank:   return parseBlank(raw)
        case .csv:     return parseCSV(raw)
        }
    }

    /// RFC4180 那一套：双引号包裹，字段内的引号写成两个
    private static func parseCSV(_ raw: String) -> [Card] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .makeIterator()
        var pending: Character? = nil

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",":  row.append(field); field = ""
                case "\n": row.append(field); field = ""; rows.append(row); row = []
                default:   field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }

        var out: [Card] = []
        for (i, r) in rows.enumerated() {
            guard r.count >= 2 else { continue }
            var front = r[0].trimmingCharacters(in: .whitespaces)
            let back = r[1].trimmingCharacters(in: .whitespaces)
            // 去掉 BOM
            if front.hasPrefix("\u{FEFF}") { front.removeFirst() }
            if front.isEmpty && back.isEmpty { continue }
            // 第一行看着像表头就跳过
            if i == 0 && (front.contains("名称") || front.lowercased() == "front" || front == "正面") { continue }
            out.append(Card(front: front, back: back))
        }
        return out
    }

    private static func parseOneLine(_ raw: String) -> [Card] {
        var out: [Card] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var parts = split(line, by: ["\t", "|", "｜", "——", "—"])
            if parts.count < 2 { parts = split(line, by: [",", "，"]) }
            guard parts.count >= 2 else { continue }
            let front = parts[0].trimmingCharacters(in: .whitespaces)
            let back = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if front.isEmpty && back.isEmpty { continue }
            out.append(Card(front: front, back: back))
        }
        return out
    }

    private static func parseBlank(_ raw: String) -> [Card] {
        var out: [Card] = []
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
            out.append(Card(front: lines[0], back: lines.dropFirst().joined(separator: "\n")))
        }
        return out
    }

    private static func split(_ line: String, by seps: [String]) -> [String] {
        var result = [line]
        for sep in seps {
            if result.count > 1 { break }
            if line.contains(sep) { result = line.components(separatedBy: sep) }
        }
        return result.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - 图片压缩

enum ImageTool {
    static func downscale(_ data: Data, maxWidth: CGFloat = 900) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let width = image.size.width
        if width <= maxWidth { return image.jpegData(compressionQuality: 0.82) ?? data }
        let scale = maxWidth / width
        let size = CGSize(width: maxWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }
}
