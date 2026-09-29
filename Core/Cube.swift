import Foundation

public enum CubeError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
public struct Move: Equatable, Codable {
    public let face: Character
    public let turns: Int
    public init(_ value: String) throws {
        let v = value.uppercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "′", with: "'")
        guard let f = v.first, "URFDLB".contains(f), v.count <= 2,
              v.count == 1 || v.last == "'" || v.last == "2" else { throw CubeError.invalid("公式无效：\(value)") }
        face = f; turns = v.hasSuffix("2") ? 2 : v.hasSuffix("'") ? 3 : 1
    }
    public var text: String { String(face) + (turns == 2 ? "2" : turns == 3 ? "'" : "") }
    public var inverse: Move { try! Move(String(face) + (turns == 1 ? "'" : turns == 2 ? "2" : "")) }
    public static func parse(_ text: String) throws -> [Move] {
        let s = text.uppercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "′", with: "'")
        var tokens: [String] = []
        for c in s {
            if c.isWhitespace { continue }
            if "URFDLB".contains(c) { tokens.append(String(c)) }
            else if (c == "'" || c == "2"), !tokens.isEmpty, tokens[tokens.count-1].count == 1 { tokens[tokens.count-1].append(c) }
            else { throw CubeError.invalid("公式包含不支持的字符：\(c)") }
        }
        return try tokens.map(Move.init)
    }
    public var spoken: String { (face == "B" ? "波" : face == "D" ? "大" : String(face)) + (turns == 2 ? "二" : turns == 3 ? "反" : "") }
    // Character does not conform to Codable on all Swift toolchains.
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(text) }
}
private struct V: Equatable {
    var x: Int; var y: Int; var z: Int
    static func + (a: V,b: V)->V { V(x:a.x+b.x,y:a.y+b.y,z:a.z+b.z) }
    static func * (a: V,b: Int)->V { V(x:a.x*b,y:a.y*b,z:a.z*b) }
    func dot(_ b: V)->Int { x*b.x+y*b.y+z*b.z }
    func cross(_ b: V)->V { V(x:y*b.z-z*b.y,y:z*b.x-x*b.z,z:x*b.y-y*b.x) }
    func clockwise(_ n: V)->V { n.cross(self) * -1 + n * n.dot(self) }
}
public struct Cube: Equatable {
    public static let solved = String(repeating:"U",count:9)+String(repeating:"R",count:9)+String(repeating:"F",count:9)+String(repeating:"D",count:9)+String(repeating:"L",count:9)+String(repeating:"B",count:9)
    public private(set) var facelets: String
    public init(_ state: String = Cube.solved) throws {
        guard state.count == 54, "URFDLB".allSatisfy({ f in state.filter{$0 == f}.count == 9 }),
              Array(state).enumerated().allSatisfy({ i,c in i % 9 != 4 || c == Array("URFDLB")[i/9] })
        else { throw CubeError.invalid("魔方颜色或中心状态无效") }
        facelets = state
    }
    private static let normals = [V(x:0,y:1,z:0),V(x:1,y:0,z:0),V(x:0,y:0,z:1),V(x:0,y:-1,z:0),V(x:-1,y:0,z:0),V(x:0,y:0,z:-1)]
    private static let stickers: [(V,V)] = (0..<54).map { i in
        let r=i%9/3,c=i%3,p: V
        switch i/9 {
        case 0: p=V(x:c-1,y:1,z:r-1)
        case 1: p=V(x:1,y:1-r,z:1-c)
        case 2: p=V(x:c-1,y:1-r,z:1)
        case 3: p=V(x:c-1,y:-1,z:1-r)
        case 4: p=V(x:-1,y:1-r,z:c-1)
        default:p=V(x:1-c,y:1-r,z:-1)
        }
        return (p,normals[i/9])
    }
    private static let permutations: [[Int]] = normals.map { n in stickers.map { p,d in
        let newP = p.dot(n) == 1 ? p.clockwise(n) : p
        let newD = p.dot(n) == 1 ? d.clockwise(n) : d
        return stickers.firstIndex(where: {$0.0 == newP && $0.1 == newD})!
    }}
    public mutating func apply(_ move: Move) {
        let perm=Self.permutations[Array("URFDLB").firstIndex(of:move.face)!]
        for _ in 0..<move.turns {
            let old=Array(facelets);var out=old
            for i in 0..<54 { out[perm[i]]=old[i] }
            facelets=String(out)
        }
    }
    public func applying(_ moves:[Move])->Cube { var c=self; for m in moves { c.apply(m) };return c }
}

