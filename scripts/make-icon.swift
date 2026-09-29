import Foundation
import CoreGraphics
import ImageIO
let root="App/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath:root,withIntermediateDirectories:true)
for size in [40,58,60,80,87,120,180,152,167,1024] {
    let colorSpace=CGColorSpaceCreateDeviceRGB()
    let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,space:colorSpace,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    ctx.setFillColor(CGColor(red:0.30,green:0.10,blue:0.58,alpha:1));ctx.fill(CGRect(x:0,y:0,width:1024,height:1024))
    let faces:[([CGPoint],CGColor)]=[
      ([CGPoint(x:512,y:850),CGPoint(x:862,y:670),CGPoint(x:512,y:490),CGPoint(x:162,y:670)],CGColor(gray:1,alpha:1)),
      ([CGPoint(x:162,y:670),CGPoint(x:512,y:490),CGPoint(x:512,y:130),CGPoint(x:162,y:310)],CGColor(red:0,green:0.82,blue:0.4,alpha:1)),
      ([CGPoint(x:512,y:490),CGPoint(x:862,y:670),CGPoint(x:862,y:310),CGPoint(x:512,y:130)],CGColor(red:1,green:0.08,blue:0.27,alpha:1))]
    for (q,color) in faces {
      func uv(_ u:CGFloat,_ v:CGFloat)->CGPoint {CGPoint(x:(1-v)*((1-u)*q[0].x+u*q[1].x)+v*((1-u)*q[3].x+u*q[2].x),y:(1-v)*((1-u)*q[0].y+u*q[1].y)+v*((1-u)*q[3].y+u*q[2].y))}
      for row in 0..<3 {for col in 0..<3 {
        let a=CGFloat(col)/3+0.012,b=CGFloat(row)/3+0.012,c=CGFloat(col+1)/3-0.012,d=CGFloat(row+1)/3-0.012
        ctx.beginPath();ctx.move(to:uv(a,b));for p in [uv(c,b),uv(c,d),uv(a,d)]{ctx.addLine(to:p)};ctx.closePath();ctx.setFillColor(color);ctx.fillPath()
      }}
    }
    let url=URL(fileURLWithPath:root+"/icon-\(size).png")
    let dest=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(dest,ctx.makeImage()!,nil)
    guard CGImageDestinationFinalize(dest) else{fatalError("Could not write icon")}
}
