import Foundation
public struct ModeSettings: Codable, Equatable {
    public var speech=false, compatibility=false, leadIn=true
    public var group=1
    public var rate=1.2, letterGap=0.2, groupGap=0.2, quiet=5.0
    public var gallery=false, onlyChanged=true, autoImages=true
    public var imageDelay=5.0
}
public struct Target: Identifiable, Codable, Equatable {
    public var id=UUID().uuidString
    public var name: String
    public var algorithm: String
    public var facelets: String { (try? Cube().applying(Move.parse(algorithm)).facelets) ?? Cube.solved }
    public static let builtins: [Target] = [
        Target(id:"solved",name:"六面复原",algorithm:""),
        Target(id:"three",name:"三面复原",algorithm:"D'R2D2L2UF2L2F2L2F2U'F2L'U'FDR2D2BUB"),
        Target(id:"advanced",name:"高级摇晃",algorithm:"LD'FR'FU'"),
        Target(id:"beginner",name:"初级摇晃",algorithm:"LD'FR'"),
        Target(id:"toss",name:"抛接还原",algorithm:"RU'D'RL'")
    ]
}
public struct Settings: Codable {
    public var single=ModeSettings(), dual=ModeSettings()
    public var dualIdle=4.0, transition=5.0, matchImageDelay=3.0
    public var target="solved", s2Target="solved"
    public var fontSize=24.0, opacity=0.92
    public var aliases:[String:String]=[:], addresses:[String:String]=[:]
    public var targets=Target.builtins
    public init() {}
}

