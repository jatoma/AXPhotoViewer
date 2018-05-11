//
//  SlideshowNavigator.swift
//  AXPhotoViewer
//
//  Created by Tomasz Studziński on 11.05.2018.
//

import UIKit



///Handles states of slideshow and
///measures time to swap next slide
open class AutomaticSlideshow: NSObject {
    private var timer: Timer?
    var nextSlideActionHandler : (()->())?
    open var timeInterval: TimeInterval = 2
    private(set) var isPlaying = false
    var isSuspended = false

    func stop() {
        isPlaying = false
        timer?.invalidate();
    }

    func play() {
        timer?.invalidate();
        timer = Timer.scheduledTimer(timeInterval: timeInterval, target: TimerTargetWrapper(interactor: self),
                                     selector: (#selector(TimerTargetWrapper.timerFunction)),
                                     userInfo: nil, repeats: true)
        isPlaying = true
    }

    func toggle() {
        isPlaying ? stop() : play()
    }

    func restart() {
        if(isPlaying){
            play()
        }
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    /// Wrapper for storing weak reference.
    /// Used in Timer to eliminate retain cycle
    private class TimerTargetWrapper {
        weak var interactor: AutomaticSlideshow?
        init(interactor: AutomaticSlideshow) {
            self.interactor = interactor
        }

        @objc func timerFunction(timer: Timer?) {
            guard let interactor = interactor else { return }
            
            if interactor.isSuspended { return }
            
            DispatchQueue.main.async { [weak self] in
                self?.interactor?.nextSlideActionHandler?()
            }
        }
    }
}
