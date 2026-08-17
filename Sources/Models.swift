import Foundation
import UIKit

// MARK: - 数据

struct Card: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    var frontImage: Data? = nil
    var backImage: Data? = nil

    /// 到期时间。新卡是 1970，所以永远算「已到期」
    var due: Date = Date(timeIntervalSince1970: 0)
    /// 当前间隔，单位天
    var interval: Double = 0
    /// 难度系数
    var ease: Double = 2.5
    var reps: Int = 0
    var lapses: Int = 0
    /// 0 新卡 / 1 学习中 / 2 复习中
    var state: Int = 0

    var stateName: String {
        switch state {
        case 0: return "新"
        case 1: return "学习"
        default: return "复习"
        }
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

    func dueCards(at date: Date = Date()) -> [Card] {
        cards.filter { $0.due <= date }.sorted { $0.due < $1.due }
    }

    func counts(at date: Date = Date()) -> (new: Int, learn: Int, review: Int) {
        var n = 0, l = 0, r = 0
        for c in cards where c.due <= date {
            switch c.state {
            case 0: n += 1
            case 1: l += 1
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

    var title: String {
        switch self {
        case .again: return "重来"
        case .hard:  return "困难"
        case .good:  return "良好"
        case .easy:  return "简单"
        }
    }
}

// MARK: - 间隔重复（SM-2 简化版）

enum Scheduler {
    static let day: TimeInterval = 86400
    static let minute: TimeInterval = 60

    static func apply(_ card: inout Card, _ grade: Grade, now: Date = Date()) {
        if card.state == 0 || card.state == 1 {
            // 新卡和学习中的卡，走分钟级的短步骤
            switch grade {
            case .again:
                card.state = 1
                card.due = now.addingTimeInterval(1 * minute)
            case .hard:
                card.state = 1
                card.due = now.addingTimeInterval(6 * minute)
            case .good:
                if card.state == 1 && card.reps > 0 {
                    card.state = 2
                    card.interval = 1
                    card.due = now.addingTimeInterval(day)
                } else {
                    card.state = 1
                    card.due = now.addingTimeInterval(10 * minute)
                }
            case .easy:
                card.state = 2
                card.interval = 4
                card.due = now.addingTimeInterval(4 * day)
            }
        } else {
            // 已经进入复习的卡，走天级间隔
            switch grade {
            case .again:
                card.lapses += 1
                card.ease = max(1.3, card.ease - 0.2)
                card.state = 1
                card.interval = 0
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
        card.reps += 1
    }

    /// 按钮上显示的「按这个评分，下次什么时候再见」
    static func preview(_ card: Card, _ grade: Grade) -> String {
        var copy = card
        apply(&copy, grade)
        let d = copy.due.timeIntervalSinceNow
        if d < 50 * minute { return "\(max(1, Int((d / minute).rounded())))分" }
        if d < day        { return "\(max(1, Int((d / (60 * minute)).rounded())))时" }
        if d < 30 * day   { return "\(max(1, Int((d / day).rounded())))天" }
        return String(format: "%.1f月", d / (30 * day))
    }
}

// MARK: - 存储

final class Store: ObservableObject {
    @Published var decks: [Deck] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("decks.json")
    }

    init() {
        load()
        if decks.isEmpty {
            decks = [Store.starterDeck]
            save()
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

    func index(of id: UUID) -> Int? {
        decks.firstIndex { $0.id == id }
    }

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
        switch mode {
        case .oneLine:  return parseOneLine(raw)
        case .blank:    return parseBlank(raw)
        }
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
            if line.contains(sep) {
                result = line.components(separatedBy: sep)
            }
        }
        return result.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

// MARK: - 图片压缩

enum ImageTool {
    static func downscale(_ data: Data, maxWidth: CGFloat = 900) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let width = image.size.width
        if width <= maxWidth {
            return image.jpegData(compressionQuality: 0.82) ?? data
        }
        let scale = maxWidth / width
        let size = CGSize(width: maxWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82) ?? data
    }
}
