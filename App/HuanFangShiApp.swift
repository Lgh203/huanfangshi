import SwiftUI
import PhotosUI

@main struct HuanFangShiApp:App {
    @StateObject private var model=AppModel()
    var body:some Scene {
        WindowGroup {HomeView(model:model)
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.protectedDataDidBecomeAvailableNotification)){_ in model.unlocked()}
        }
    }
}
struct HomeView:View {
    @ObservedObject var model:AppModel
    @State private var showSettings=false,showLibrary=false,showTimer=false
    @State private var slot:Int?
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:16) {
                    Text(model.dual ? "双魔方同步还原":"幻方师").font(.largeTitle.bold())
                    BluetoothStatus(hub:model.bluetooth)
                    Text(model.message).font(.subheadline).foregroundStyle(.secondary)
                    if model.dual {Text(model.phase.rawValue).foregroundStyle(.purple)}
                    HStack {
                        cubePanel(0)
                        if model.dual{cubePanel(1)}
                    }
                    formulaCard
                    Button("计算并固定公式"){model.calculateNow()}.buttonStyle(PrimaryButton())
                    Button("计时器与公式"){showTimer=true}.buttonStyle(PrimaryButton())
                    Button("保存当前魔方图片到相册"){model.exportImage()}.buttonStyle(PrimaryButton())
                    if !model.savedStatus.isEmpty {Text(model.savedStatus).font(.caption)}
                    Button("目标状态库"){showLibrary=true}.buttonStyle(PrimaryButton())
                    Button(model.dual ? "返回单魔方模式":"双魔方模式"){model.setDual(!model.dual)}.buttonStyle(PrimaryButton())
                    Button("语音、公式与同步设置"){showSettings=true}.buttonStyle(PrimaryButton())
                    Text("iOS 测试版 · 真实蓝牙模式\n不包含跨应用悬浮窗或自动设置壁纸").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.background(Color(red:1,green:0.97,blue:1))
            .sheet(isPresented:Binding(get:{slot != nil},set:{if !$0{slot=nil}})){
                DevicePicker(model:model,slot:slot ?? 0)
            }
            .sheet(isPresented:$showSettings){SettingsView(model:model)}
            .sheet(isPresented:$showLibrary){LibraryView(model:model)}
            .sheet(isPresented:$showTimer){TimerView(model:model)}
        }.tint(.purple)
    }
    private func cubePanel(_ index:Int)->some View {
        VStack {
            if model.dual {Text(index==0 ? "魔方 A":"魔方 B").bold()}
            CubePreview(state:model.states[index]).frame(maxHeight:model.dual ? 180:260)
            Text(model.ready[index] ? "状态已同步":"尚未同步").font(.caption).foregroundStyle(model.ready[index] ? .green:.secondary)
            Button("连接智能魔方"){slot=index}.buttonStyle(.borderedProminent)
            Button("一键重置 / 重新同步"){model.reset(index)}.font(.caption)
        }.frame(maxWidth:.infinity)
    }
    private var formulaCard:some View {FormulaCard(model:model)}
}
struct PrimaryButton:ButtonStyle {
    func makeBody(configuration:Configuration)->some View{
        configuration.label.font(.headline).frame(maxWidth:.infinity).padding(14).background(Color.purple.opacity(configuration.isPressed ? 0.6:1)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius:18))
    }
}
struct BluetoothStatus:View {
    @ObservedObject var hub:BluetoothHub
    var body:some View {Text(hub.status).font(.caption).foregroundStyle(.secondary)}
}
struct FormulaCard:View {
    @ObservedObject var model:AppModel
    private var text:String {
        model.formula.enumerated().map{($0.offset>0 && $0.offset%4==0 ? "   ":"")+$0.element.text}.joined(separator:" ")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack(alignment:.top) {
                Text(text.isEmpty ? (model.dual ? "":"等待生成公式"):text).font(.system(size:model.settings.fontSize,weight:.medium,design:.monospaced))
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .onTapGesture(count:2){model.lockDisplay()}
                if model.dual {
                    Button("S\(model.preset)"){model.togglePreset()}.font(.system(size:model.settings.fontSize,weight:.bold,design:.monospaced)).foregroundStyle(.green)
                }
            }
            if model.busy{ProgressView()}
            Text(model.frozen ? "已锁定显示 · 双击公式解锁":"双击公式锁定；双魔方需先完成匹配").font(.caption2).foregroundStyle(.secondary)
        }.padding().background(Color.white.opacity(model.settings.opacity)).clipShape(RoundedRectangle(cornerRadius:14))
    }
}
struct DevicePicker:View {
    @ObservedObject var model:AppModel
    @ObservedObject private var hub:BluetoothHub
    let slot:Int
    @Environment(\.dismiss) private var dismiss
    @State private var selected:UUID?
    @State private var alias="",mac="",showAll=false
    init(model:AppModel,slot:Int){self.model=model;self.hub=model.bluetooth;self.slot=slot}
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Text(hub.status)
                    Button(hub.scanning ? "重新搜索":"搜索附近魔方"){hub.scan()}
                    Toggle("同时显示未识别设备",isOn:$showAll)
                    Text("绿色表示识别到魔方名称或服务；连接后仍需验证协议。先转动魔方唤醒，并断开其他手机上的连接。").font(.caption)
                }
                Section("选择设备（列表不会随信号强弱跳动）"){
                    ForEach(hub.devices.filter{showAll || $0.recognized}){device in
                        Button{
                            selected=device.id;alias=model.settings.aliases[device.id.uuidString] ?? device.name
                            mac=model.settings.addresses[device.id.uuidString] ?? device.address
                        }label:{
                            HStack {Image(systemName:selected==device.id ? "checkmark.circle.fill":"circle").foregroundStyle(device.recognized ? .green:.gray)
                                VStack(alignment:.leading){Text(model.settings.aliases[device.id.uuidString] ?? device.name);Text(device.name+" · \(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)}
                            }.foregroundStyle(device.recognized ? .green:.primary)
                        }
                    }
                }
                if let id=selected {
                    Section("此设备"){
                        TextField("自定义名称",text:$alias)
                        TextField("蓝牙地址 AA:BB:CC:DD:EE:FF",text:$mac).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Text("iOS 不提供设备的系统 MAC 地址。若未自动填写，请从安卓扫描页面复制该魔方地址，仅需填写一次。不要填 iPhone 的蓝牙地址。").font(.caption)
                        Button("连接到魔方 \(slot==0 ? "A":"B")"){
                            guard CubeProtocol.address(mac) != nil else{hub.status="蓝牙地址格式不正确";return}
                            model.settings.aliases[id.uuidString]=alias;model.settings.addresses[id.uuidString]=mac.uppercased()
                            hub.stopScan();hub.connect(id,slot:slot,address:mac);dismiss()
                        }
                    }
                }
                Button("断开此槽位"){hub.disconnect(slot);dismiss()}.foregroundStyle(.red)
            }.navigationTitle("连接智能魔方").toolbar{Button("完成"){dismiss()}}
                .onAppear{hub.scan()}.onDisappear{hub.stopScan()}
        }
    }
}
struct SettingsView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image:PhotosPickerItem?
    @State private var backgroundStatus=""
    private var mode:Binding<ModeSettings>{model.dual ? $model.settings.dual:$model.settings.single}
    var body:some View {
        NavigationStack {
            Form {
                Section("语音播报"){
                    Toggle("通过手机或蓝牙耳机播报",isOn:mode.speech)
                    Stepper("每组 \(mode.wrappedValue.group) 个转动",value:mode.group,in:1...6)
                    numberSlider("语速档位",value:mode.rate,range:0.5...4,step:0.1)
                    Text("iOS 语速刻度与安卓不同，4 档不保证等于实际四倍速。声音走系统当前音频输出。").font(.caption)
                    numberSlider("组内间隔（秒）",value:mode.letterGap,range:0...1,step:0.1)
                    numberSlider("完成一组后停顿（秒）",value:mode.groupGap,range:0...5,step:0.1)
                    Toggle("迷你耳机兼容模式",isOn:mode.compatibility)
                    Toggle("兼容模式首字保护（先读“好”）",isOn:mode.leadIn)
                    Text("兼容模式将整组作为一段语音，组内间隔由语音引擎控制。实际做完本组动作后才读下一组。").font(.caption)
                }
                Section("公式"){
                    numberSlider("停止转动后生成（秒）",value:mode.quiet,range:0.2...30,step:0.1)
                    numberSlider("公式字号",value:$model.settings.fontSize,range:14...42,step:1)
                    numberSlider("公式背景不透明度",value:$model.settings.opacity,range:0.1...1,step:0.01)
                    Picker(model.dual ? "S2 目标状态":"目标状态",selection:model.dual ? $model.settings.s2Target:$model.settings.target) {
                        ForEach(model.settings.targets){Text($0.name).tag($0.id)}
                    }
                }
                if model.dual {
                    Section("双魔方流程"){
                        numberSlider("双方停止打乱后就绪（秒）",value:$model.settings.dualIdle,range:0.2...30,step:0.1)
                        numberSlider("匹配后进入 S2（秒）",value:$model.settings.transition,range:0...30,step:0.1)
                        numberSlider("匹配后保存图片（秒）",value:$model.settings.matchImageDelay,range:0...30,step:0.1)
                        Text("两个六面复原的魔方属于初始状态，不触发匹配保存。点击公式末尾 S1/S2 后改为手动切换。").font(.caption)
                    }
                }
                Section("图片与相册"){
                    Toggle("自动保存到相册",isOn:mode.gallery)
                    Toggle("停止后自动处理",isOn:mode.autoImages)
                    Toggle("只在状态变化时保存",isOn:mode.onlyChanged)
                    if !model.dual {numberSlider("停止后保存（秒）",value:mode.imageDelay,range:0.2...30,step:0.1)}
                    Text(model.dual ? "匹配成功且保存完成后自动关闭保存开关，再次开启可再次使用。":"锁屏时继续按规则保存；解锁后关闭自动保存。")
                        .font(.caption)
                    Text("相册默认关闭，开启前请手动保存一次以授权。替换上一次图片时系统可能要求确认删除；相册权限受限或后台无法确认时会显示失败，不会假报成功。").font(.caption).foregroundStyle(.orange)
                    PhotosPicker("选择图片背景",selection:$image,matching:.images)
                    Button("恢复渐变背景"){
                        if FileManager.default.fileExists(atPath:CubePicture.backgroundURL.path){try? FileManager.default.removeItem(at:CubePicture.backgroundURL)}
                        backgroundStatus="已恢复默认背景"
                    }
                    Text(backgroundStatus).font(.caption)
                    Text("相册仅保存魔方图片，不含公式和提示词；双魔方同样只输出当前操作的一个魔方。").font(.caption)
                }
                Section("测试版说明"){
                    Text("GAN i4 / i Carry 2、魔域 V10 AI、奇艺 QYSC-S 为移植协议，需要逐款真机验证。后台蓝牙、音频受 iOS 调度限制；强制划掉应用后不会继续运行。")
                    Text("当前不需要激活；不含私钥或签名证书。")
                }
            }.navigationTitle(model.dual ? "双魔方设置":"单魔方设置")
                .toolbar{Button("保存"){model.settingsChanged();dismiss()}}
                .onChange(of:image){item in
                    Task {
                        if let data=try? await item?.loadTransferable(type:Data.self),let picture=UIImage(data:data),let jpeg=picture.jpegData(compressionQuality:0.9){
                            do{try jpeg.write(to:CubePicture.backgroundURL,options:.atomic);backgroundStatus="背景已保存"}catch{backgroundStatus=error.localizedDescription}
                        }
                    }
                }
        }
    }
    private func numberSlider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>,step:Double)->some View{
        VStack(alignment:.leading){Text(title+"："+String(format:"%.2f",value.wrappedValue));Slider(value:value,in:range,step:step)}
    }
}
struct LibraryView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name="",algorithm="",error=""
    var body:some View {
        NavigationStack {
            Form {
                Section("选择目标（绿色勾选表示当前选择）"){
                    ForEach(model.settings.targets){target in
                        Button{
                            if model.dual {model.settings.s2Target=target.id}else{model.settings.target=target.id}
                            model.settingsChanged()
                        }label:{
                            HStack{VStack(alignment:.leading){Text(target.name);Text(target.algorithm.isEmpty ? "完整六面复原":target.algorithm).font(.caption).foregroundStyle(.secondary)}
                                Spacer();if model.selectedTarget.id==target.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)}}
                        }
                    }.onDelete{indices in
                        model.settings.targets.remove(atOffsets:indices)
                        if model.settings.targets.isEmpty{model.settings.targets=Target.builtins}
                        if !model.settings.targets.contains(where:{$0.id==model.settings.target}){model.settings.target=model.settings.targets[0].id}
                        if !model.settings.targets.contains(where:{$0.id==model.settings.s2Target}){model.settings.s2Target=model.settings.targets[0].id}
                        model.settingsChanged()
                    }
                }
                Section("通过打乱公式创建"){
                    TextField("名称",text:$name)
                    TextField("例如 R U R' U' F2",text:$algorithm,axis:.vertical).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Text("从六面复原状态依次执行此打乱公式，得到目标状态。").font(.caption)
                    Button("创建状态"){do{try model.addTarget(name:name,algorithm:algorithm);name="";algorithm="";error=""}catch{self.error=error.localizedDescription}}
                    Text(error).foregroundStyle(.red)
                }
            }.navigationTitle("目标状态库").toolbar{Button("完成"){dismiss()}}
        }
    }
}
struct TimerView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack{
            VStack(spacing:24){
                FormulaCard(model:model)
                Spacer()
                Text(String(format:"%.2f",model.elapsed)).font(.system(size:76,weight:.light,design:.monospaced)).minimumScaleFactor(0.5)
                Button(model.timerRunning ? "停止":"开始"){model.toggleTimer()}.buttonStyle(PrimaryButton())
                Text("公式仅显示在本页面上方，不跨应用悬浮").foregroundStyle(.secondary)
                Spacer()
            }.padding().navigationTitle("计时器").toolbar{Button("完成"){dismiss()}}
        }
    }
}

