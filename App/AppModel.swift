import Foundation
import Combine
import UIKit

enum DualPhase:String {case initial="请观众打乱两个魔方",armed="请选择一个魔方开始同步",copying="S1：匹配另一魔方",matched="两个打乱状态已一致",finalReady="请选择魔方执行 S2",final="S2：到达预设状态"}
final class AppModel:ObservableObject {
    @Published var settings:Settings {didSet{save()}}
    @Published var dual=false
    @Published var states=[Cube.solved,Cube.solved]
    @Published var ready=[false,false]
    @Published var message="请连接智能魔方"
    @Published var formula:[Move]=[]
    @Published var frozen=false
    @Published var preset=1
    @Published var phase=DualPhase.initial
    @Published var targetSlot:Int?
    @Published var busy=false
    @Published var savedStatus=""
    @Published var elapsed=0.0
    @Published var timerRunning=false
    let bluetooth=BluetoothHub()
    let speech=SpeechPlayer()
    private let solver=Solver()
    private var guide=Guide()
    private var generation=0
    private var active=0
    private var manualPreset=false
    private var scrambled=[false,false]
    private var lastMove=[Date.distantPast,Date.distantPast]
    private var histories:[[Move]?]=[nil,nil]
    private var quietWork:DispatchWorkItem?,stageWork:DispatchWorkItem?,imageWork:DispatchWorkItem?,speechWork:DispatchWorkItem?
    private var speechEnd=0
    private var correctingHalf=""
    private var lastImage=""
    private var imageGeneration=0
    private var imageSaving=false
    private var timer:Timer?
    private var timerStart:Date?
    private var mode:ModeSettings {dual ? settings.dual:settings.single}
    init(){
        if let data=UserDefaults.standard.data(forKey:"settings"),let s=try? JSONDecoder().decode(Settings.self,from:data){settings=s}else{settings=Settings()}
        bluetooth.onState={[weak self] i,s,m in self?.receive(i,s,m)}
        solver.prepare()
        bluetooth.onLost={[weak self] i,why in guard let self=self else{return};self.ready[i]=false;self.clearPlan();self.message=why}
        speech.onRecovery={[weak self] in self?.speakRemainder()}
        speech.onIdle={[weak self] in self?.scheduleNextSpeechIfNeeded()}
    }
    private func save(){if let d=try? JSONEncoder().encode(settings){UserDefaults.standard.set(d,forKey:"settings")}}
    var selectedTarget:Target {settings.targets.first{$0.id==(dual ? settings.s2Target:settings.target)} ?? Target.builtins[0]}
    var activeSlot:Int {active}
    func setDual(_ value:Bool){
        clearPlan();imageWork?.cancel();stageWork?.cancel();imageGeneration+=1;dual=value;active=0;targetSlot=nil;frozen=false;preset=1;phase = .initial;manualPreset=false
        scrambled=[false,false];lastMove=[.distantPast,.distantPast];lastImage=""
        message=value ? "请连接两个魔方，先由观众打乱":"单魔方模式"
        if !value {bluetooth.disconnect(1);if ready[0]{scheduleSolve()}}
    }
    func settingsChanged(){
        imageGeneration+=1;imageWork?.cancel();lastImage="";speech.stop();speechEnd=0
        clearPlan();scheduleSolve()
        if dual && isMatched {scheduleImage(matched:true)}else if !dual && ready[0]{scheduleImage(matched:false)}
    }
    func reset(_ slot:Int){clearPlan();bluetooth.reset(slot);message="已请求设备重置或重新读取真实状态"}
    private func clearPlan(){
        generation+=1;quietWork?.cancel();speechWork?.cancel();guide.reset();busy=false;speech.stop();speechEnd=0;correctingHalf=""
        if !frozen{formula=[]}
    }
    private var isMatched:Bool {ready.allSatisfy{$0} && states[0]==states[1] && states[0] != Cube.solved}
    private func receive(_ slot:Int,_ state:String,_ move:Move?){
        let changed=states[slot] != state
        if state==Cube.solved {histories[slot]=[]}
        else if let move=move,let history=histories[slot] {
            let reduced=MoveReduction.simplify(history+[move]);histories[slot]=reduced.count<=400 ? reduced:nil
        }else if changed {histories[slot]=nil}
        ready[slot]=true;states[slot]=state
        if move != nil || changed {lastMove[slot]=Date()}
        if state != Cube.solved {scrambled[slot]=true}
        if !dual && slot==0 {
            if let move=move,guide.locked {consume(move)}
            else if changed || !guide.locked {scheduleSolve()}
            if changed {scheduleImage(matched:false)}
            return
        }
        guard dual,ready.allSatisfy({$0}) else{return}
        if states.allSatisfy({$0==Cube.solved}) {
            if phase == .initial {return}
            clearPlan();phase = .initial;scrambled=[false,false];stageWork?.cancel();imageWork?.cancel();imageGeneration+=1
            if !manualPreset{preset=1};return
        }
        if phase == .initial {
            guard scrambled.allSatisfy({$0}) else{return}
            stageWork?.cancel()
            let job=DispatchWorkItem{[weak self] in
                guard let self=self,self.ready.allSatisfy({$0}),self.scrambled.allSatisfy({$0}),self.phase == .initial else{return}
                self.phase = .armed;self.message="已停止打乱，转动任意一个魔方开始 S1"
            };stageWork=job
            let since=Date().timeIntervalSince(lastMove.max() ?? Date())
            DispatchQueue.main.asyncAfter(deadline:.now()+max(0,settings.dualIdle-since),execute:job)
            return
        }
        if phase == .armed || phase == .finalReady {
            guard move != nil else{return}
            active=slot;targetSlot=slot;phase=preset==1 ? .copying:.final;scheduleSolve();return
        }
        if phase == .matched {
            if !isMatched {
                imageWork?.cancel();imageGeneration+=1;stageWork?.cancel()
                if move != nil {active=slot}
                phase = preset==1 ? .copying:.final;scheduleSolve();return
            }
            if !manualPreset{return}
            guard move != nil else{return}
            active=slot;phase=preset==1 ? .copying:.final;scheduleSolve();return
        }
        if phase == .copying && slot != active && changed {clearPlan();scheduleSolve()}
        else if slot==active {
            if let move=move,guide.locked {consume(move)}else if changed || !guide.locked{scheduleSolve()}
        }
        if phase == .copying && isMatched {matched()}
    }
    private func matched(){
        clearPlan();phase = .matched;message="两个魔方的打乱状态已一致";scheduleImage(matched:true)
        guard !manualPreset else{return}
        stageWork?.cancel()
        let job=DispatchWorkItem{[weak self] in
            guard let self=self,self.phase == .matched,self.isMatched,!self.manualPreset else{return}
            self.preset=2;self.phase = .finalReady;self.message="已到 S2，转动任意一个魔方开始"
        };stageWork=job;DispatchQueue.main.asyncAfter(deadline:.now()+settings.transition,execute:job)
    }
    func togglePreset(){
        guard dual else{return}
        manualPreset=true;preset=preset==1 ? 2:1;stageWork?.cancel();clearPlan()
        phase = preset==1 ? .armed:.finalReady
        message="手动 \(preset==1 ? "S1":"S2")：转动要操作的魔方；不再自动切换"
    }
    func lockDisplay(){
        if dual && !isMatched && !frozen {message="双魔方需先匹配为相同打乱状态，才能锁定并关闭图片同步";return}
        frozen.toggle()
        if frozen {
            if dual {settings.dual.gallery=false}else{settings.single.gallery=false}
            imageWork?.cancel();imageGeneration+=1;message="公式显示已锁定，相册同步已关闭"
        }else{formula=guide.display;message="恢复实时公式显示（相册开关仍保持关闭）"}
    }
    private func goal()->String {dual && preset==1 ? states[1-active]:selectedTarget.facelets}
    func calculateNow(){guard ready[active] else{message="尚未取得真实魔方状态";return};if dual && phase == .initial {message="请先打乱两个魔方";return};clearPlan();solve()}
    private func scheduleSolve(){
        guard ready[active],(!dual || phase == .copying || phase == .final) else{return}
        generation+=1;quietWork?.cancel();busy=false
        let job=DispatchWorkItem{[weak self] in self?.solve()};quietWork=job
        DispatchQueue.main.asyncAfter(deadline:.now()+mode.quiet,execute:job)
    }
    private func solve(){
        guard ready[active],!guide.locked else{return}
        let source=states[active],target=goal()
        if source==target {message="已到目标状态";if dual && preset==1 && isMatched{matched()};return}
        let token=generation;busy=true;message="正在计算并校验解法…"
        var knownRoute:[Move]?
        let targetHistory=dual && preset==1 ? histories[1-active] : try? Move.parse(selectedTarget.algorithm)
        if let currentHistory=histories[active],let targetHistory=targetHistory {
            let route=MoveReduction.route(currentHistory:currentHistory,targetHistory:targetHistory)
            if (try? Cube(source).applying(route).facelets)==target{knownRoute=route}
        }
        solver.solve(source,to:target){[weak self] result in
            guard let self=self,self.generation==token,self.states[self.active]==source,self.goal()==target else{return}
            self.busy=false
            switch result {
            case .failure(let error):self.message=error.localizedDescription
            case .success(let resultMoves):
                let moves=knownRoute.map{$0.count<resultMoves.count ? $0:resultMoves} ?? resultMoves
                self.guide.lock(moves);self.speechEnd=0
                if !self.frozen{self.formula=self.guide.display}
                self.message="固定解法 \(moves.count) 步";self.speakRemainder()
            }
        }
    }
    private func consume(_ move:Move){
        let result=guide.accept(move)
        if !frozen{formula=guide.display}
        if guide.correcting {
            speechWork?.cancel()
            if guide.required>23 {clearPlan();message="纠错加剩余超过 23 步，静止后重新求解";scheduleSolve();return}
            message="请先纠正，再继续后面的公式"
            if let first=guide.display.first {
                if result == .correcting,correctingHalf.hasSuffix("2"),first.turns != 2,first.face==correctingHalf.first {correctingHalf="";return}
                correctingHalf=first.turns==2 ? first.text:""
                speech.say([first],settings:mode)
            }
            return
        }
        if guide.finished {
            speech.stop();speechWork?.cancel()
            if states[active]==goal() {message="已到目标状态";if !dual{clearPlan()}}
            else {clearPlan();message="终点与目标不一致，重新获取状态";bluetooth.requestState(active);scheduleSolve()}
            return
        }
        if result == .recovered || result == .cancelled {correctingHalf="";speakRemainder()}
        else {scheduleNextSpeechIfNeeded()}
    }
    private func scheduleNextSpeechIfNeeded(){
        guard mode.speech,guide.locked,!guide.correcting,!guide.finished,guide.index>=speechEnd else{return}
        speechWork?.cancel()
        let job=DispatchWorkItem{[weak self] in guard let self=self else{return};if self.speech.busy{self.scheduleNextSpeechIfNeeded()}else{self.speakRemainder()}}
        speechWork=job;DispatchQueue.main.asyncAfter(deadline:.now()+max(0.05,mode.groupGap),execute:job)
    }
    private func speakRemainder(){
        guard mode.speech,guide.locked,!guide.finished else{return}
        if guide.correcting {if let m=guide.display.first{speech.say([m],settings:mode)};return}
        if speechEnd<=guide.index {speechEnd=min(guide.plan.count,guide.index+mode.group)}
        let remaining=guide.remaining
        speech.say(Array(remaining.prefix(speechEnd-guide.index)),settings:mode)
    }
    private func scheduleImage(matched:Bool){
        imageWork?.cancel();imageGeneration+=1
        guard mode.gallery,mode.autoImages,(!dual || matched) else{return}
        let token=imageGeneration,snapshot=states[active],delay=matched ? settings.matchImageDelay:mode.imageDelay
        let job=DispatchWorkItem{[weak self] in
            guard let self=self,self.imageGeneration==token,self.mode.gallery,self.ready[self.active],self.states[self.active]==snapshot,(!matched || self.isMatched) else{return}
            self.exportImage(automatic:true,matched:matched)
        };imageWork=job;DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:job)
    }
    func exportImage(automatic:Bool=false,matched:Bool=false){
        guard !imageSaving else{savedStatus="正在保存上一张图片，请稍候";return}
        let state=states[active]
        if automatic && mode.onlyChanged && state==lastImage{return}
        imageSaving=true
        let token=imageGeneration,wasDual=dual
        PhotoExporter.save(state:state){[weak self] result in
            guard let self=self else{return}
            self.imageSaving=false
            switch result {
            case .success:self.lastImage=state;self.savedStatus="已保存魔方图片到相册"
                if matched && token==self.imageGeneration && wasDual==self.dual && self.isMatched {self.settings.dual.gallery=false;self.savedStatus+="，双魔方自动保存已关闭"}
            case .failure(let e):self.savedStatus="保存失败："+e.localizedDescription
            }
            if automatic && self.dual==wasDual && self.states[self.active] != state {
                self.scheduleImage(matched:self.dual && self.isMatched)
            }
        }
    }
    func unlocked(){
        guard !dual else{return}
        settings.single.gallery=false;imageGeneration+=1;imageWork?.cancel()
        message="手机解锁，相册自动同步已关闭"
    }
    func toggleTimer(){
        if timerRunning{timer?.invalidate();timerRunning=false;return}
        elapsed=0;timerStart=Date();timerRunning=true
        timer=Timer.scheduledTimer(withTimeInterval:0.05,repeats:true){[weak self] _ in
            guard let self=self,let start=self.timerStart else{return};self.elapsed=Date().timeIntervalSince(start)
        }
    }
    func addTarget(name:String,algorithm:String)throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw CubeError.invalid("请输入名称")}
        _=try Move.parse(algorithm)
        settings.targets.append(Target(name:name,algorithm:algorithm))
    }
}

