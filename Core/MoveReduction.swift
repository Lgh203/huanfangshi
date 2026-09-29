import Foundation
public enum MoveReduction {
    public static func simplify(_ moves:[Move])->[Move] {
        var out:[Move]=[]
        for move in moves {
            if let last=out.last,last.face==move.face {
                out.removeLast();let power=(last.turns+move.turns)%4
                if power>0{out.append(try! Move(String(move.face)+(power==2 ? "2":power==3 ? "'":"")))}
            }else{out.append(move)}
        }
        return out
    }
    public static func route(currentHistory:[Move],targetHistory:[Move])->[Move] {
        simplify(currentHistory.reversed().map(\.inverse)+targetHistory)
    }
}
