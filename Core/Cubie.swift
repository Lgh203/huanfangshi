import Foundation
/// Cubie composition for software calibration of devices without a reset command.
public struct Cubie {
    private static let cf=[[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
    private static let cc=["URF","UFL","ULB","UBR","DFR","DLF","DBL","DRB"].map{Array($0)}
    private static let ef=[[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]
    private static let ec=["UR","UF","UL","UB","DR","DF","DL","DB","FR","FL","BL","BR"].map{Array($0)}
    private var cp=Array(0..<8),co=[Int](repeating:0,count:8),ep=Array(0..<12),eo=[Int](repeating:0,count:12)
    private init(){}
    public init(_ state:String)throws {
        let f=Array(try Cube(state).facelets)
        for i in 0..<8 {
            guard let orientation=(0..<3).first(where:{f[Self.cf[i][$0]]=="U" || f[Self.cf[i][$0]]=="D"}),
                  let piece=(0..<8).first(where:{Self.cc[$0][1]==f[Self.cf[i][(orientation+1)%3]] && Self.cc[$0][2]==f[Self.cf[i][(orientation+2)%3]]}) else{throw CubeError.invalid("角块状态错误")}
            cp[i]=piece;co[i]=orientation
        }
        for i in 0..<12 {
            var found=false
            for p in 0..<12 {for o in 0..<2 {
                if f[Self.ef[i][0]]==Self.ec[p][o] && f[Self.ef[i][1]]==Self.ec[p][1-o]{ep[i]=p;eo[i]=o;found=true}
            }}
            if !found{throw CubeError.invalid("棱块状态错误")}
        }
        func parity(_ a:[Int])->Int {var p=0;for i in a.indices{for j in a.indices where j>i && a[i]>a[j]{p ^= 1}};return p}
        guard Set(cp).count==8,Set(ep).count==12,co.reduce(0,+)%3==0,eo.reduce(0,+)%2==0,parity(cp)==parity(ep) else{throw CubeError.invalid("魔方状态不可达")}
    }
    public var inverse:Cubie {
        var d=Cubie()
        for i in 0..<8{d.cp[cp[i]]=i;d.co[cp[i]]=(3-co[i])%3}
        for i in 0..<12{d.ep[ep[i]]=i;d.eo[ep[i]]=eo[i]}
        return d
    }
    public func multiplied(_ b:Cubie)->Cubie {
        var d=Cubie()
        for i in 0..<8{d.cp[i]=cp[b.cp[i]];d.co[i]=(co[b.cp[i]]+b.co[i])%3}
        for i in 0..<12{d.ep[i]=ep[b.ep[i]];d.eo[i]=(eo[b.ep[i]]+b.eo[i])%2}
        return d
    }
    public var facelets:String {
        var f=Array(Cube.solved)
        for i in 0..<8{for n in 0..<3{f[Self.cf[i][(n+co[i])%3]]=Self.cc[cp[i]][n]}}
        for i in 0..<12{for n in 0..<2{f[Self.ef[i][(n+eo[i])%2]]=Self.ec[ep[i]][n]}}
        return String(f)
    }
}

