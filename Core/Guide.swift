import Foundation

/// Physical quarter turns remain distinct; only presentation merges correction halves.
public struct Guide {
    public enum Outcome { case ignored, half, cancelled, advanced, wrong, correcting, recovered, finished }
    public private(set) var plan: [Move] = []
    public private(set) var errors: [Move] = []
    public private(set) var index = 0
    private var half: Move?
    public var locked: Bool { !plan.isEmpty }
    public var correcting: Bool { !errors.isEmpty }
    public var finished: Bool { locked && index == plan.count && errors.isEmpty }
    public var required: Int { errors.count + plan.count-index }
    public var remaining: [Move] {
        var out=Array(plan.dropFirst(index))
        if let half=half, !out.isEmpty { out[0]=half };return out
    }
    public var display: [Move] {
        var out: [Move]=[], i=errors.count-1
        while i >= 0 {
            if i > 0 && errors[i] == errors[i-1] { out.append(try! Move(String(errors[i].face)+"2"));i-=2 }
            else { out.append(errors[i].inverse);i-=1 }
        }
        return out+remaining
    }
    public mutating func lock(_ moves:[Move]) { self=Guide();plan=moves }
    public mutating func reset() { self=Guide() }
    private mutating func push(_ m:Move) {
        var power=m.turns,direction=m
        while let tail=errors.last,tail.face==m.face { power+=tail.turns;direction=tail;errors.removeLast() }
        switch power%4 {
        case 1:errors.append(try! Move(String(m.face)))
        case 2:errors += [direction,direction]
        case 3:errors.append(try! Move(String(m.face)+"'"))
        default:break
        }
    }
    public mutating func accept(_ m:Move)->Outcome {
        guard locked else { return .ignored }
        if m.turns == 2 { _=quarter(try! Move(String(m.face)));return quarter(try! Move(String(m.face))) }
        return quarter(m)
    }
    private mutating func quarter(_ m:Move)->Outcome {
        if correcting {
            let n=errors.count
            if n>=2 && errors[n-1]==errors[n-2] && m.face==errors[n-1].face {
                errors.removeLast(2);errors.append(m.inverse);return .correcting
            }
            if m==errors.last!.inverse { errors.removeLast();return errors.isEmpty ? .recovered : .correcting }
            push(m);return .wrong
        }
        guard index<plan.count else { push(m);return .wrong }
        let e=plan[index]
        if e.turns==2 && e.face==m.face {
            if half == nil { half=m;return .half }
            if half==m { half=nil;index+=1;return index==plan.count ? .finished : .advanced }
            half=nil;return .cancelled
        }
        if e==m { index+=1;return index==plan.count ? .finished : .advanced }
        push(m);return .wrong
    }
}

