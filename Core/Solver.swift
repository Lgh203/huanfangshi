import Foundation
import JavaScriptCore

/// One serial queue owns its JavaScript VM; never tied to a web view's foreground lifetime.
public final class Solver {
    private let queue=DispatchQueue(label:"huanfangshi.solver",qos:.userInitiated)
    private var context: JSContext?
    public init() {}
    public func prepare(){queue.async{_ = try? self.engine()}}
    private func engine() throws -> JSContext {
        if let context=context { return context }
        guard let js=JSContext() else { throw CubeError.invalid("无法初始化求解器") }
        #if SWIFT_PACKAGE
        let bundle=Bundle.module
        #else
        let bundle=Bundle.main
        #endif
        for name in ["cube","solve","bridge"] {
            guard let url=bundle.url(forResource:name,withExtension:"js") else { throw CubeError.invalid("缺少离线求解资源 "+name) }
            js.evaluateScript(try String(contentsOf:url))
            if let e=js.exception { throw CubeError.invalid(e.toString()) }
        }
        js.evaluateScript("Cube.initSolver();")
        if let e=js.exception { throw CubeError.invalid(e.toString()) }
        context=js;return js
    }
    public func solve(_ current: String,to target: String,completion:@escaping(Result<[Move],Error>)->Void) {
        queue.async {
            let result=Result<[Move],Error> {
                let js=try self.engine();js.exception=nil
                let value=js.objectForKeyedSubscript("solveBetween")?.call(withArguments:[current,target])
                if let error=js.exception { throw CubeError.invalid(error.toString()) }
                guard let formula=value?.toString() else { throw CubeError.invalid("未生成解法") }
                let moves=try Move.parse(formula)
                guard try Cube(current).applying(moves).facelets==target else { throw CubeError.invalid("解法终点校验失败") }
                return moves
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

