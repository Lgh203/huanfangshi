import UIKit
import SwiftUI
import Photos

enum CubePicture {
    static let colors:[Character:UIColor]=["U":.white,"R":UIColor(red:1,green:0.04,blue:0.22,alpha:1),"F":UIColor(red:0,green:0.78,blue:0.30,alpha:1),"D":.systemYellow,"L":.systemOrange,"B":.systemBlue]
    static var backgroundURL:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("picture-background.jpg")}
    static func image(_ state:String,wallpaper:Bool)->UIImage {
        let width:CGFloat=wallpaper ? 1080:600
        let height:CGFloat=wallpaper ? width*UIScreen.main.bounds.height/UIScreen.main.bounds.width:600
        let size=CGSize(width:width,height:height)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=wallpaper
        return UIGraphicsImageRenderer(size:size,format:format).image{renderer in
            let ctx=renderer.cgContext
            if wallpaper {
                if let bg=UIImage(contentsOfFile:backgroundURL.path){
                    let scale=max(width/bg.size.width,height/bg.size.height),w=bg.size.width*scale,h=bg.size.height*scale
                    bg.draw(in:CGRect(x:(width-w)/2,y:(height-h)/2,width:w,height:h))
                }else{
                    let colors=[UIColor(red:0.73,green:0.91,blue:0.95,alpha:1).cgColor,UIColor(red:1,green:0.97,blue:0.84,alpha:1).cgColor,UIColor(red:0.80,green:0.95,blue:0.94,alpha:1).cgColor]
                    if let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors as CFArray,locations:[0,0.5,1]){ctx.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:0,y:height),options:[])}
                }
            }
            let scale=width*(wallpaper ? 0.60:0.85)
            let origin=CGPoint(x:width/2,y:height*(wallpaper ? 0.64:0.49))
            func pt(_ x:CGFloat,_ y:CGFloat)->CGPoint {CGPoint(x:origin.x+x*scale,y:origin.y+y*scale)}
            let top=pt(0,-0.53),left=pt(-0.5,-0.27),center=pt(0,0),right=pt(0.5,-0.27),bottom=pt(0,0.56),bl=pt(-0.5,0.29),br=pt(0.5,0.29)
            let faces:[(Int,[CGPoint])]=[(0,[top,right,center,left]),(2,[left,center,bottom,bl]),(1,[center,right,br,bottom])]
            let stickers=Array(state.count==54 ? state:Cube.solved)
            for (face,quad) in faces {
                func uv(_ u:CGFloat,_ v:CGFloat)->CGPoint {
                    let a=quad[0],b=quad[1],c=quad[2],d=quad[3]
                    return CGPoint(x:(1-v)*((1-u)*a.x+u*b.x)+v*((1-u)*d.x+u*c.x),y:(1-v)*((1-u)*a.y+u*b.y)+v*((1-u)*d.y+u*c.y))
                }
                for r in 0..<3 {for c in 0..<3 {
                    let gap:CGFloat=0.005,u=CGFloat(c)/3+gap,v=CGFloat(r)/3+gap,u2=CGFloat(c+1)/3-gap,v2=CGFloat(r+1)/3-gap
                    let points=[uv(u,v),uv(u2,v),uv(u2,v2),uv(u,v2)]
                    let path=UIBezierPath()
                    // Rounded polygon corners, uniform face color (no dark shaded face).
                    for i in 0..<4 {
                        let p=points[i],prev=points[(i+3)%4],next=points[(i+1)%4]
                        let enter=CGPoint(x:p.x+(prev.x-p.x)*0.055,y:p.y+(prev.y-p.y)*0.055)
                        let leave=CGPoint(x:p.x+(next.x-p.x)*0.055,y:p.y+(next.y-p.y)*0.055)
                        if i==0{path.move(to:enter)}else{path.addLine(to:enter)}
                        path.addQuadCurve(to:leave,controlPoint:p)
                    }
                    path.close();(colors[stickers[face*9+r*3+c]] ?? .gray).setFill();path.fill()
                    UIColor(white:0.85,alpha:1).setStroke();path.lineWidth=wallpaper ? 1.2:0.6;path.stroke()
                }}
            }
        }
    }
}
struct CubePreview:View {
    let state:String
    var body:some View {Image(uiImage:CubePicture.image(state,wallpaper:false)).resizable().scaledToFit().accessibilityLabel("当前魔方状态")}
}
enum PhotoExporter {
    static func save(state:String,completion:@escaping(Result<Void,Error>)->Void){
        let image=CubePicture.image(state,wallpaper:true)
        let exportURL=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("latest-cube.jpg")
        do {try image.jpegData(compressionQuality:0.95)?.write(to:exportURL,options:.atomic)}catch{completion(.failure(error));return}
        func write(_ status:PHAuthorizationStatus){
            guard status == .authorized || status == .limited else{completion(.failure(CubeError.invalid("请允许访问相册")));return}
            let previousID=UserDefaults.standard.string(forKey:"lastCubePhoto")
            var createdID:String?
            PHPhotoLibrary.shared().performChanges({
                let request=PHAssetChangeRequest.creationRequestForAsset(from:image);createdID=request.placeholderForCreatedAsset?.localIdentifier
                if let id=previousID {
                    let assets=PHAsset.fetchAssets(withLocalIdentifiers:[id],options:nil)
                    if assets.count>0 {PHAssetChangeRequest.deleteAssets(assets)}
                }
            }){ok,error in DispatchQueue.main.async {
                if ok {UserDefaults.standard.set(createdID,forKey:"lastCubePhoto");completion(.success(()))}
                else{completion(.failure(error ?? CubeError.invalid("相册保存或旧图删除未获批准")))}
            }}
        }
        let status=PHPhotoLibrary.authorizationStatus(for:.readWrite)
        if status == .notDetermined {
            guard UIApplication.shared.applicationState == .active else{completion(.failure(CubeError.invalid("请先在应用内保存一次并授权相册")));return}
            PHPhotoLibrary.requestAuthorization(for:.readWrite){status in DispatchQueue.main.async{write(status)}}
        }else{write(status)}
    }
}

