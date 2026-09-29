import Foundation
import CoreBluetooth
import Combine

struct DiscoveredCube: Identifiable {
    let id:UUID
    var name:String, address:String, recognized:Bool, rssi:Int
}
final class CubeLink {
    let peripheral:CBPeripheral, slot:Int, address:String
    var wire:CubeProtocol?
    var writer:CBCharacteristic?, reader:CBCharacteristic?
    var writes:[Data]=[], busy=false, wanted=true, ready=false
    var counter:Int?, cube:Cube?, retries=0, initializationAttempts=0
    var calibration:Cubie?
    func displayState(_ raw:String)throws->String {
        let physical=try Cubie(raw)
        return calibration?.inverse.multiplied(physical).facelets ?? raw
    }
    var retry:DispatchWorkItem?
    init(_ p:CBPeripheral,slot:Int,address:String){peripheral=p;self.slot=slot;self.address=address}
}
final class BluetoothHub:NSObject,ObservableObject,CBCentralManagerDelegate,CBPeripheralDelegate {
    @Published var devices:[DiscoveredCube]=[]
    @Published var scanning=false
    @Published var status="等待连接智能魔方"
    @Published var names=["未连接","未连接"]
    @Published var battery=[0,0]
    var onState:((Int,String,Move?)->Void)?
    var onLost:((Int,String)->Void)?
    private var manager:CBCentralManager!
    private var found:[UUID:CBPeripheral]=[:], links:[UUID:CubeLink]=[:]
    private var scanTimeout:DispatchWorkItem?
    override init(){super.init();manager=CBCentralManager(delegate:self,queue:.main)}
    func centralManagerDidUpdateState(_ central:CBCentralManager){
        switch central.state {
        case .poweredOn:status="蓝牙已开启"
        case .unauthorized:status="请在 iPhone 设置中允许幻方师使用蓝牙"
        case .poweredOff:status="请开启手机蓝牙";invalidateAll()
        default:status="蓝牙暂不可用";invalidateAll()
        }
    }
    private func invalidateAll(){for link in links.values {link.ready=false;link.cube=nil;onLost?(link.slot,"蓝牙不可用")}}
    func scan(){
        guard manager.state == .poweredOn else {centralManagerDidUpdateState(manager);return}
        stopScan();devices=[];scanning=true;status="搜索附近设备，请转动魔方唤醒"
        manager.scanForPeripherals(withServices:nil,options:[CBCentralManagerScanOptionAllowDuplicatesKey:true])
        let task=DispatchWorkItem{[weak self] in self?.stopScan()};scanTimeout=task;DispatchQueue.main.asyncAfter(deadline:.now()+20,execute:task)
    }
    func stopScan(){scanTimeout?.cancel();manager.stopScan();scanning=false}
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber){
        found[peripheral.identifier]=peripheral
        let name=advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未命名设备"
        let services=advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let u=name.uppercased()
        let known=u.contains("GAN")||u.contains("QYSC")||u.contains("QIYI")||u.hasPrefix("WCU_")||u.hasPrefix("^S")||services.contains{service in CubeKind.allCases.contains{service==CBUUID(string:$0.service)}}
        var address=""
        if let data=advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,data.count>=8,data[0]==1 {
            address=data.suffix(6).reversed().map{String(format:"%02X",$0)}.joined(separator:":")
        }
        if u.contains("QYSC")||u.contains("QIYI") {
            let tail=String(u.suffix(4))
            if tail.count==4,UInt16(tail,radix:16) != nil {address="CC:A3:00:00:"+tail.prefix(2)+":"+tail.suffix(2)}
        }
        let row=DiscoveredCube(id:peripheral.identifier,name:name,address:address,recognized:known,rssi:RSSI.intValue)
        // Update in place: never sort every RSSI packet (avoids moving tap targets).
        if let index=devices.firstIndex(where:{$0.id==row.id}){devices[index]=row}else{devices.append(row)}
    }
    func connectedID(_ slot:Int)->UUID? {links.values.first{$0.slot==slot && $0.wanted}?.peripheral.identifier}
    func connect(_ id:UUID,slot:Int,address:String){
        guard CubeProtocol.address(address) != nil else {status="需要有效蓝牙地址。可从安卓版本设备信息获取。";return}
        guard let p=found[id] else {status="请重新搜索设备";return}
        guard !links.values.contains(where:{$0.peripheral.identifier==id && $0.slot != slot}) else {status="同一个魔方不能同时连接到 A 和 B";return}
        disconnect(slot)
        let link=CubeLink(p,slot:slot,address:address);links[id]=link;p.delegate=self
        names[slot]=p.name ?? "智能魔方";status="正在连接 "+names[slot]
        manager.connect(p);armConnectionTimeout(link)
    }
    private func armConnectionTimeout(_ link:CubeLink){
        link.retry?.cancel()
        let t=DispatchWorkItem{[weak self,weak link] in
            guard let self=self,let link=link,link.wanted,!link.ready else{return}
            self.status="连接或同步超时，正在重连";self.manager.cancelPeripheralConnection(link.peripheral)
        };link.retry=t;DispatchQueue.main.asyncAfter(deadline:.now()+15,execute:t)
    }
    func disconnect(_ slot:Int){
        for (id,link) in links where link.slot==slot {
            link.wanted=false;link.retry?.cancel();manager.cancelPeripheralConnection(link.peripheral);links.removeValue(forKey:id)
        }
        names[slot]="未连接";onLost?(slot,"设备已断开")
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral){
        guard let link=links[peripheral.identifier] else{return}
        link.counter=nil;link.cube=nil;link.ready=false;link.busy=false;link.writes=[];link.initializationAttempts=0
        peripheral.discoverServices(CubeKind.allCases.map{CBUUID(string:$0.service)})
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?){
        guard let link=links[peripheral.identifier] else{return}
        if let error=error {status=error.localizedDescription;return}
        guard let service=peripheral.services?.first(where:{s in CubeKind.allCases.contains{CBUUID(string:$0.service)==s.uuid}}),
              let kind=CubeKind.allCases.first(where:{CBUUID(string:$0.service)==service.uuid}) else {
            status="设备没有支持的魔方服务";link.wanted=false;manager.cancelPeripheralConnection(peripheral);return
        }
        do {link.wire=try CubeProtocol(kind:kind,address:link.address)}catch{status=error.localizedDescription;return}
        peripheral.discoverCharacteristics([CBUUID(string:kind.read),CBUUID(string:kind.write)],for:service)
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?){
        guard let link=links[peripheral.identifier],let kind=link.wire?.kind else{return}
        link.reader=service.characteristics?.first{$0.uuid==CBUUID(string:kind.read)}
        link.writer=service.characteristics?.first{$0.uuid==CBUUID(string:kind.write)}
        guard let reader=link.reader,link.writer != nil else{status="设备缺少数据通道";return}
        peripheral.setNotifyValue(true,for:reader)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?){
        guard let link=links[peripheral.identifier],let wire=link.wire else{return}
        guard characteristic.isNotifying else{status=error?.localizedDescription ?? "无法订阅魔方转动";return}
        for request in wire.initialization {send(request,link)}
        requestUntilReady(link)
    }
    private func requestUntilReady(_ link:CubeLink){
        link.retry?.cancel()
        let task=DispatchWorkItem{[weak self,weak link] in
            guard let self=self,let link=link,!link.ready,link.wanted else{return}
            link.initializationAttempts+=1
            if link.initializationAttempts>5 {
                self.status="已连接但未收到有效状态，请检查蓝牙地址或型号";link.wanted=false;self.manager.cancelPeripheralConnection(link.peripheral);return
            }
            if let wire=link.wire {for request in wire.initialization {self.send(request,link)}}
            self.requestUntilReady(link)
        };link.retry=task;DispatchQueue.main.asyncAfter(deadline:.now()+2,execute:task)
    }
    private func send(_ clear:[UInt8],_ link:CubeLink){
        guard let wire=link.wire else{return}
        do {link.writes.append(Data(try wire.crypt(clear,encrypt:true)));drain(link)}catch{status=error.localizedDescription}
    }
    private func drain(_ link:CubeLink){
        guard !link.busy,!link.writes.isEmpty,let writer=link.writer,link.peripheral.state == .connected else{return}
        let response=writer.properties.contains(.write),type:CBCharacteristicWriteType=response ? .withResponse:.withoutResponse
        guard response || link.peripheral.canSendWriteWithoutResponse else{return}
        let data=link.writes[0]
        guard data.count<=link.peripheral.maximumWriteValueLength(for:type) else{status="设备写入长度不支持";link.writes=[];return}
        link.busy=true;link.peripheral.writeValue(data,for:writer,type:type)
        if !response {link.writes.removeFirst();link.busy=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.08){[weak self] in self?.drain(link)}}
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral:CBPeripheral){if let link=links[peripheral.identifier]{drain(link)}}
    func peripheral(_ peripheral:CBPeripheral,didWriteValueFor characteristic:CBCharacteristic,error:Error?){
        guard let link=links[peripheral.identifier] else{return}
        link.busy=false
        if let error=error {status="写入失败："+error.localizedDescription;manager.cancelPeripheralConnection(peripheral);return}
        if !link.writes.isEmpty{link.writes.removeFirst()};drain(link)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?){
        guard let link=links[peripheral.identifier],let wire=link.wire,let data=characteristic.value else{return}
        do {
            for packet in try wire.decode(Array(data)) {
                switch packet {
                case .reply(let bytes):send(bytes,link)
                case .battery(let value):battery[link.slot]=max(0,min(100,value))
                case .lost:manager.cancelPeripheralConnection(peripheral)
                case .state(let serial,let facelets):
                    let mask=wire.kind == .moyu ? 255:65535
                    if wire.kind != .qiyi,let previous=link.counter,((serial-previous)&mask)>mask/2{continue}
                    if link.ready,let cube=link.cube,cube.facelets != facelets {onLost?(link.slot,"收到完整状态，重新校准解法")}
                    let displayed=try link.displayState(facelets)
                    link.cube=try Cube(facelets);link.counter=serial;link.ready=true;link.retries=0;link.retry?.cancel()
                    status=names[link.slot]+" 已同步"
                    onState?(link.slot,displayed,nil)
                case .move(let serial,let move):
                    guard link.ready,var cube=link.cube else {requestState(link.slot);continue}
                    if wire.kind != .qiyi,let previous=link.counter {
                        let mask=wire.kind == .moyu ? 255:65535,delta=(serial-previous)&mask
                        if delta==0 || delta>mask/2 {continue}
                        if delta != 1 {
                            link.ready=false;link.counter=serial;onLost?(link.slot,"转动数据缺步，重新获取状态")
                            requestState(link.slot);requestUntilReady(link);continue
                        }
                    }
                    cube.apply(move);link.cube=cube;link.counter=serial
                    onState?(link.slot,try link.displayState(cube.facelets),move)
                }
            }
        }catch{status=error.localizedDescription}
    }
    func requestState(_ slot:Int){if let link=links.values.first(where:{$0.slot==slot}),let wire=link.wire{send(wire.stateRequest,link)}}
    func reset(_ slot:Int){
        guard let link=links.values.first(where:{$0.slot==slot}) else{return}
        if let reset=link.wire?.resetRequest {link.ready=false;send(reset,link);requestState(slot)}
        else {
            guard let raw=link.cube?.facelets,let anchor=try? Cubie(raw),link.ready else{status="尚未取得状态，不能校准";requestState(slot);return}
            link.calibration=anchor
            status="手机端已校准为六面复原（实物必须已复原）"
            onState?(slot,Cube.solved,nil)
        }
    }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?){disconnected(peripheral,error)}
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?){disconnected(peripheral,error)}
    private func disconnected(_ p:CBPeripheral,_ error:Error?){
        guard let link=links[p.identifier] else{return}
        link.ready=false;link.cube=nil;link.counter=nil;link.retry?.cancel()
        onLost?(link.slot,error?.localizedDescription ?? "蓝牙连接中断")
        guard link.wanted,link.retries<5 else{status="设备已断开，请重新连接";return}
        link.retries+=1;status="连接中断，正在重连（\(link.retries)/5）"
        let task=DispatchWorkItem{[weak self,weak link] in guard let self=self,let link=link,link.wanted else{return};self.manager.connect(p);self.armConnectionTimeout(link)}
        link.retry=task;DispatchQueue.main.asyncAfter(deadline:.now()+Double(link.retries),execute:task)
    }
}

