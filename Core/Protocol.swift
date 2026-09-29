import Foundation
import CommonCrypto

public enum CubeKind:String,CaseIterable { case gan4,gan3,moyu,qiyi
    public var service:String {
        switch self {case .gan4:return "00000010-0000-fff7-fff6-fff5fff4fff0"
        case .gan3:return "8653000a-43e6-47b7-9cb0-5fc21d4ae340"
        case .moyu:return "0783b03e-7735-b5a0-1760-a305d2795cb0"
        case .qiyi:return "0000fff0-0000-1000-8000-00805f9b34fb"}
    }
    public var read:String {
        switch self {case .gan4:return "0000fff6-0000-1000-8000-00805f9b34fb"
        case .gan3:return "8653000b-43e6-47b7-9cb0-5fc21d4ae340"
        case .moyu:return "0783b03e-7735-b5a0-1760-a305d2795cb1"
        case .qiyi:return "0000fff6-0000-1000-8000-00805f9b34fb"}
    }
    public var write:String {
        switch self {case .gan4:return "0000fff5-0000-1000-8000-00805f9b34fb"
        case .gan3:return "8653000c-43e6-47b7-9cb0-5fc21d4ae340"
        case .moyu:return "0783b03e-7735-b5a0-1760-a305d2795cb2"
        case .qiyi:return read}
    }
}
public enum CubePacket {
    case state(Int,String),move(Int,Move),battery(Int),reply([UInt8]),lost
}
public final class CubeProtocol {
    public let kind:CubeKind
    private var key:[UInt8],iv:[UInt8]
    private var timestamp:UInt32=0
    private let mac:[UInt8]
    public static func address(_ s:String)->[UInt8]? {
        let a=s.trimmingCharacters(in:.whitespacesAndNewlines).split(separator:":")
        guard a.count==6,a.allSatisfy({$0.count==2}) else{return nil}
        let b=a.compactMap{UInt8($0,radix:16)};return b.count==6 ? b:nil
    }
    public init(kind:CubeKind,address:String) throws {
        guard let mac=Self.address(address) else {throw CubeError.invalid("需要六段蓝牙地址，例如 AA:BB:CC:DD:EE:FF")}
        self.kind=kind;self.mac=mac
        if kind == .qiyi {
            key=[87,177,249,171,205,90,232,167,156,185,140,231,87,140,81,8];iv=Array(repeating:0,count:16)
        } else {
            key=kind == .moyu ? [21,119,58,92,103,14,45,31,23,103,42,19,155,103,82,87] : [1,2,66,40,49,145,22,7,32,5,24,84,66,17,18,83]
            iv=kind == .moyu ? [17,35,38,37,134,42,44,59,85,6,127,49,126,103,33,87] : [17,3,50,40,33,1,118,39,32,149,120,20,50,18,2,67]
            for i in 0..<6 {key[i]=UInt8((Int(key[i])+Int(mac[5-i]))%255);iv[i]=UInt8((Int(iv[i])+Int(mac[5-i]))%255)}
        }
    }
    public func crypt(_ input:[UInt8],encrypt:Bool) throws->[UInt8] {
        guard input.count>=16,kind != .qiyi || input.count%16==0 else{throw CubeError.invalid("蓝牙帧长度无效")}
        func block(_ bytes:[UInt8],ecb:Bool)throws->[UInt8]{
            var out=[UInt8](repeating:0,count:bytes.count+16),written=0
            let capacity=out.count
            let result=key.withUnsafeBytes { k in iv.withUnsafeBytes { v in bytes.withUnsafeBytes { b in out.withUnsafeMutableBytes { o in
                CCCrypt(CCOperation(encrypt ? kCCEncrypt:kCCDecrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(ecb ? kCCOptionECBMode:0),k.baseAddress,16,ecb ? nil:v.baseAddress,b.baseAddress,bytes.count,o.baseAddress,capacity,&written)
            }}}}
            guard result==kCCSuccess else {throw CubeError.invalid("蓝牙解密失败")}
            return Array(out.prefix(written))
        }
        if kind == .qiyi {return try block(input,ecb:true)}
        var out=input
        let offsets=encrypt ? (out.count>16 ? [0,out.count-16]:[0]) : (out.count>16 ? [out.count-16,0]:[0])
        for offset in offsets {let b=try block(Array(out[offset..<offset+16]),ecb:false);out.replaceSubrange(offset..<offset+16,with:b)}
        return out
    }
    private func padded(_ a:[UInt8],_ size:Int=20)->[UInt8] {a+Array(repeating:0,count:max(0,size-a.count))}
    public var stateRequest:[UInt8] {
        switch kind {case .gan4:return padded([0xdd,4,0,0xed,0,0])
        case .gan3:return padded([0x68,1],16)
        case .moyu:return padded([163])
        case .qiyi:return Self.frame([5,5,5,5,5])}
    }
    public var initialization:[[UInt8]] {
        switch kind {case .qiyi:return [Self.frame([0,0x6b,1,0,0,0x22,6,0,2,8,0]+mac.reversed())]
        case .moyu:return [padded([161]),stateRequest,padded([164])]
        case .gan3:return [stateRequest,padded([0x68,4],16),padded([0x68,7],16)]
        case .gan4:return [padded([0xdf,3]),padded([0xdd,4,0,0xef]),stateRequest]}
    }
    public var resetRequest:[UInt8]? {
        switch kind {
        case .gan4:return padded([0xd2,13,5,57,119,0,0,1,35,69,103,137,171,0,0,0])
        case .gan3:return padded([0x68,5,5,57,119,0,0,1,35,69,103,137,171,0,0,0],16)
        default:return nil
        }
    }
    public static func crc(_ bytes:[UInt8])->UInt16 {
        var c:UInt16=0xffff
        for b in bytes {c ^= UInt16(b);for _ in 0..<8 {c=(c&1) != 0 ? (c>>1)^0xa001:c>>1}}
        return c
    }
    public static func frame(_ content:[UInt8])->[UInt8] {
        var raw:[UInt8]=[0xfe,UInt8(content.count+4)]+content;let c=crc(raw)
        raw += [UInt8(c&255),UInt8(c>>8)]
        raw += Array(repeating:0,count:(16-raw.count%16)%16)
        return raw
    }
    public func decode(_ encrypted:[UInt8]) throws->[CubePacket] {try parse(crypt(encrypted,encrypt:false))}
    public func parse(_ b:[UInt8]) throws->[CubePacket] {
        guard b.count>=16 else{return []}
        func bits(_ start:Int,_ length:Int)throws->Int {
            guard start>=0,start+length<=b.count*8 else{throw CubeError.invalid("状态包不完整")}
            return (start..<start+length).reduce(0){($0<<1)|Int((b[$1/8]>>UInt8(7-$1%8))&1)}
        }
        func le(_ start:Int)throws->Int {try bits(start,8)|(bits(start+8,8)<<8)}
        if kind == .qiyi {return try parseQiyi(b)}
        if kind == .moyu {
            switch b[0] {
            case 163:
                guard b.count>=20 else{return []}
                var out=""
                for f in [2,5,0,3,4,1] {
                    for i in 0..<8 {
                        let color=try bits(8+f*24+i*3,3)
                        guard color<6 else{throw CubeError.invalid("魔域颜色错误")}
                        out.append(Array("FBUDLR")[color])
                        if i==3 {out.append(Array("FBUDLR")[f])}
                    }
                }
                return [.state(Int(b[19]),try Cube(out).facelets)]
            case 164:return [.battery(min(100,Int(b[1])))]
            case 165:
                guard b.count>=20 else{return []}
                let m=try bits(96,5);guard m<12 else{return []}
                return [.move(Int(b[11]),try Move(String(Array("FBUDLR")[m/2])+(m%2==0 ? "":"'")))]
            default:return []
            }
        }
        let gen3=kind == .gan3
        if gen3 && b[0] != 0x55 {return []}
        let type=Int(b[gen3 ? 1:0])
        if type==1 {
            let shift=gen3 ? 8:0, code=try bits(66+shift,6),direction=try bits(64+shift,2)
            guard let f=[2,32,8,1,16,4].firstIndex(of:code),direction<2 else{return []}
            return [.move(try le(48+shift),try Move(String(Array("URFDLB")[f])+(direction==0 ? "":"'")))]
        }
        if type==(gen3 ? 2:237) {
            let shift=gen3 ? 8:0
            var cp=[Int](repeating:0,count:8),co=cp,ep=[Int](repeating:0,count:12),eo=ep
            for i in 0..<7 {cp[i]=try bits(32+shift+i*3,3);co[i]=try bits(53+shift+i*2,2)}
            cp[7]=28-cp.reduce(0,+);co[7]=(3-co.reduce(0,+)%3)%3
            for i in 0..<11 {ep[i]=try bits(69+shift+i*4,4);eo[i]=try bits(113+shift+i,1)}
            ep[11]=66-ep.reduce(0,+);eo[11]=(2-eo.reduce(0,+)%2)%2
            return [.state(try le(16+shift),try Self.facelets(cp,co,ep,eo))]
        }
        if type==(gen3 ? 16:239) {return [.battery(min(100,gen3 ? Int(b[3]):try bits(Int(b[1])*8+8,8)))]}
        if type==(gen3 ? 17:234) {return [.lost]}
        return []
    }
    private func parseQiyi(_ b:[UInt8])throws->[CubePacket] {
        let length=Int(b[1])
        guard b[0]==0xfe,length>=9,length<=b.count,Self.crc(Array(b.prefix(length)))==0 else{return []}
        func u32(_ i:Int)->UInt32 {UInt32(b[i])<<24|UInt32(b[i+1])<<16|UInt32(b[i+2])<<8|UInt32(b[i+3])}
        let time=u32(3);var out:[CubePacket]=[]
        if b[2]==2 || (b[2]==3 && length>91 && b[91] != 0) {out.append(.reply(Self.frame(Array(b[2...6]))))}
        if [2,4,5].contains(b[2]),length>=38 {
            var s=""
            for i in 0..<54 {let c=Int((b[7+i/2]>>UInt8((i%2)*4))&15);guard c<6 else{throw CubeError.invalid("奇艺颜色错误")};s.append(Array("LRDUFB")[c])}
            timestamp=time;out += [.state(Int(time&65535),try Cube(s).facelets),.battery(Int(b[35]))]
        }else if b[2]==3,length>=38 {
            var history:[(UInt32,Int)]=[(time,Int(b[34]))]
            for i in 0..<11 {
                let p=36+i*5;guard p+5<=length-2 else{break}
                if b[p..<p+5].allSatisfy({$0==255}){continue}
                history.append((u32(p),Int(b[p+4])))
            }
            let previous=timestamp
            history=history.filter{let d=$0.0 &- previous;return $0.1>=1 && $0.1<=12 && d>0 && d<0x80000000}.sorted{($0.0 &- previous)<($1.0 &- previous)}
            for (t,c) in history where t != timestamp {
                let face=[4,1,3,0,2,5][(c-1)/2]
                out.append(.move(Int(t&65535),try Move(String(Array("URFDLB")[face])+(c%2==1 ? "'":""))));timestamp=t
            }
            out.append(.battery(Int(b[35])))
        }
        return out
    }
    private static func facelets(_ cp:[Int],_ co:[Int],_ ep:[Int],_ eo:[Int])throws->String {
        guard Set(cp)==Set(0..<8),Set(ep)==Set(0..<12),co.allSatisfy({(0..<3).contains($0)}),eo.allSatisfy({(0..<2).contains($0)}) else{throw CubeError.invalid("解密状态无效，请检查蓝牙地址")}
        let cf=[[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
        let cc=["URF","UFL","ULB","UBR","DFR","DLF","DBL","DRB"].map{Array($0)}
        let ef=[[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]
        let ec=["UR","UF","UL","UB","DR","DF","DL","DB","FR","FL","BL","BR"].map{Array($0)}
        var f=Array(Cube.solved)
        for c in 0..<8 {for n in 0..<3 {f[cf[c][(n+co[c])%3]]=cc[cp[c]][n]}}
        for e in 0..<12 {for n in 0..<2 {f[ef[e][(n+eo[e])%2]]=ec[ep[e]][n]}}
        return try Cube(String(f)).facelets
    }
}

