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

struct Deck: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var cards: [Card] = []

    init(name: String = "", cards: [Card] = []) {
        self.name = name
        self.cards = cards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = (try? c.decode(UUID.self,   forKey: .id))    ?? UUID()
        name  = (try? c.decode(String.self, forKey: .name))  ?? ""
        cards = (try? c.decode([Card].self, forKey: .cards)) ?? []
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

// MARK: - 批量导入的解析

enum ImportMode: String, CaseIterable, Identifiable {
    case oneLine = "一行一张"
    case blank   = "空行分隔"
    var id: String { rawValue }

    var hint: String {
        switch self {
        case .oneLine:
            return "每行一张卡。正面和背面用 Tab、竖线、逗号或破折号隔开都行。\n例：顶点横坐标 | x = −b/(2a)"
        case .blank:
            return "第一行正面，后面几行是背面，卡与卡之间空一行。"
        }
    }
}

enum CardParser {
    static func parse(_ raw: String, mode: ImportMode) -> [Card] {
        mode == .oneLine ? parseOneLine(raw) : parseBlank(raw)
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
