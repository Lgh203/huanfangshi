import XCTest
@testable import HuanFangCore
final class CoreTests:XCTestCase {
 func testRecordedScrambleUpperBound() throws {
   let history=try Move.parse("R U F2 D B' R2 U L' D2 F")
   let route=MoveReduction.route(currentHistory:history,targetHistory:[])
   XCTAssertLessThanOrEqual(route.count,10)
   XCTAssertEqual(try Cube().applying(history).applying(route).facelets,Cube.solved)
   XCTAssertEqual(try MoveReduction.simplify(Move.parse("U U B' B' R R'")),try Move.parse("U2 B2"))
 }
 func testSoftwareCalibrationTracksActualQuarterTurns() throws {
   let raw=try Cube().applying(Move.parse("R U F2 D' L"))
   let anchor=try Cubie(raw.facelets)
   XCTAssertEqual(anchor.inverse.multiplied(anchor).facelets,Cube.solved)
   let moves=try Move.parse("B U' R2 D F L'")
   let result=try anchor.inverse.multiplied(Cubie(raw.applying(moves).facelets)).facelets
   XCTAssertEqual(result,try Cube().applying(moves).facelets)
 }
 func testKnownOrientation() throws {
   let expected=["R":"UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB","U":"UUUUUUUUUBBBRRRRRRRRRFFFFFFDDDDDDDDDFFFLLLLLLLLLBBBBBB","F":"UUUUUULLLURRURRURRFFFFFFFFFRRRDDDDDDLLDLLDLLDBBBBBBBBB","D":"UUUUUUUUURRRRRRFFFFFFFFFLLLDDDDDDDDDLLLLLLBBBBBBBBBRRR","L":"BUUBUUBUURRRRRRRRRUFFUFFUFFFDDFDDFDDLLLLLLLLLBBDBBDBBD","B":"RRRUUUUUURRDRRDRRDFFFFFFFFFDDDDDDLLLULLULLULLBBBBBBBBB"]
   for (move,state) in expected {XCTAssertEqual(try Cube().applying([Move(move)]).facelets,state)}
 }
 func testProtocolRoundTripsAndCounters() throws {
   for kind in CubeKind.allCases {
     let wire=try CubeProtocol(kind:kind,address:"AA:BB:CC:DD:EE:FF")
     for clear in wire.initialization {XCTAssertEqual(try wire.crypt(wire.crypt(clear,encrypt:true),encrypt:false),clear)}
   }
   let wire=try CubeProtocol(kind:.gan3,address:"AA:BB:CC:DD:EE:FF")
   var b=[UInt8](repeating:0,count:16);b[0]=0x55;b[1]=1;b[2]=10;b[7]=0x34;b[8]=0x12;b[9]=0x20
   let packets=try wire.parse(b)
   guard case .move(let serial,let move)=packets.first else{return XCTFail("Missing GAN3 move")}
   XCTAssertEqual(serial,0x1234);XCTAssertEqual(move.text,"R")
   let frame=CubeProtocol.frame([5,5,5,5,5]);XCTAssertEqual(CubeProtocol.crc(Array(frame.prefix(Int(frame[1])))),0)
 }
 func testMoves() throws {
   XCTAssertEqual(try Move.parse("U'DL2"),try ["U'","D","L2"].map(Move.init))
   XCTAssertThrowsError(try Move.parse("R3"));XCTAssertThrowsError(try Move.parse("S1"))
   for f in "URFDLB" {
     let m=try Move(String(f)),c=try Cube()
     XCTAssertEqual(c.applying([m,m,m,m]),c)
     XCTAssertEqual(c.applying([m,m.inverse]),c)
   }
 }
 func testCorrectionHalfTurn() throws {
   for correction in ["B","B'"] {
     var g=Guide();g.lock(try Move.parse("R U2 F"))
     _=g.accept(try Move("B"));_=g.accept(try Move("B"))
     XCTAssertEqual(g.display.first?.text,"B2")
     _=g.accept(try Move(correction));_=g.accept(try Move(correction))
     XCTAssertFalse(g.correcting);XCTAssertEqual(g.index,0)
     _=g.accept(try Move("R"));_=g.accept(try Move("U'"));_=g.accept(try Move("U'"));_=g.accept(try Move("F"));XCTAssertTrue(g.finished)
   }
 }
 func testCorrectionEndpoint() throws {
   var cube=try Cube().applying(Move.parse("F' U' R'")),g=Guide()
   g.lock(try Move.parse("R U F"))
   for m in try Move.parse("R B D") { cube.apply(m);_=g.accept(m) }
   let remaining=g.display
   XCTAssertEqual(cube.applying(remaining).facelets,Cube.solved)
 }
 func testPresets() throws {
   for target in Target.builtins { let m=try Move.parse(target.algorithm);XCTAssertEqual(try Cube(target.facelets).applying(m.reversed().map(\.inverse)).facelets,Cube.solved) }
 }
 func testSolverBothDirections() throws {
   let s=Solver(),done=expectation(description:"solver");done.expectedFulfillmentCount=3
   for (a,b) in [("R U F2",""),("R U F2","D L B'"),("","R U")] {
      let current=try Cube().applying(Move.parse(a)).facelets,target=try Cube().applying(Move.parse(b)).facelets
      s.solve(current,to:target){ result in
        switch result {case .success(let moves):XCTAssertEqual(try? Cube(current).applying(moves).facelets,target)
        case .failure(let e):XCTFail(e.localizedDescription)}
        done.fulfill()
      }
   }
   wait(for:[done],timeout:120)
 }
}

