import XCTest
@testable import HuanFangCore
final class CoreTests:XCTestCase {
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

