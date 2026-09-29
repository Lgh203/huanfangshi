import Foundation
import AVFoundation
import Combine

final class SpeechPlayer:NSObject,AVSpeechSynthesizerDelegate,ObservableObject {
    @Published var error=""
    private var synth=AVSpeechSynthesizer()
    private var pending:[AVSpeechUtterance]=[]
    private var current:AVSpeechUtterance?
    private var started=Date()
    private var timer:Timer?
    private var retry:DispatchWorkItem?
    var onRecovery:(()->Void)?
    var onIdle:(()->Void)?
    var busy:Bool {current != nil || !pending.isEmpty}
    override init(){
        super.init();synth.delegate=self
        NotificationCenter.default.addObserver(self,selector:#selector(interruption),name:AVAudioSession.interruptionNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(resetAudio),name:AVAudioSession.mediaServicesWereResetNotification,object:nil)
        timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in
            guard let self=self,self.current != nil,Date().timeIntervalSince(self.started)>30 else{return}
            self.recover("语音超时，恢复当前步骤")
        }
    }
    func stop(){retry?.cancel();pending=[];current=nil;synth.stopSpeaking(at:.immediate)}
    func say(_ moves:[Move],settings:ModeSettings){
        stop();guard settings.speech,!moves.isEmpty else{return}
        do {
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(.playback,mode:.spokenAudio,options:[.allowBluetoothA2DP])
            try session.setActive(true)
        }catch{self.error=error.localizedDescription;return}
        let lead=settings.compatibility && settings.leadIn ? "好，":""
        let phrases=settings.compatibility ? [lead+moves.map(\.spoken).joined(separator:"，")] : moves.map(\.spoken)
        for (index,text) in phrases.enumerated(){
            let u=AVSpeechUtterance(string:text);u.voice=AVSpeechSynthesisVoice(language:"zh-CN")
            // Apple's speech rate is nonlinear, not a duration multiplier.
            u.rate=Float(min(0.95,max(0.25,0.25+settings.rate*0.15)))
            u.volume=1
            u.postUtteranceDelay=settings.compatibility || index==phrases.count-1 ? 0:settings.letterGap
            pending.append(u)
        }
        next()
    }
    private func next(){
        guard current==nil,!pending.isEmpty else {if !busy{onIdle?()};return}
        current=pending.removeFirst();started=Date();synth.speak(current!)
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){
        guard synthesizer===synth,utterance===current else{return};current=nil;next()
    }
    func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didCancel utterance:AVSpeechUtterance){
        guard synthesizer===synth,utterance===current else{return};recover("播报意外停止，恢复当前步骤")
    }
    private func recover(_ message:String){
        error=message;stop();synth.delegate=nil;synth=AVSpeechSynthesizer();synth.delegate=self
        let work=DispatchWorkItem{[weak self] in self?.onRecovery?()};retry=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.5,execute:work)
    }
    @objc private func interruption(_ note:Notification){
        guard let type=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              type==AVAudioSession.InterruptionType.ended.rawValue else{return}
        let options=note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        if AVAudioSession.InterruptionOptions(rawValue:options).contains(.shouldResume){recover("音频中断结束")}
    }
    @objc private func resetAudio(){recover("音频服务重启")}
    deinit{timer?.invalidate();NotificationCenter.default.removeObserver(self)}
}

