//
//  SlideshowNavigator.swift
//  AXPhotoViewer
//
//  Created by Tomasz Studziński on 11.05.2018.
//

import UIKit

///Handles states of slideshow and
///measures time to swap next slide
class AutomaticSlideshow: NSObject {
    private var timer: Timer?
    var nextSlideActionHandler : (()->())?
    open var timeInterval: TimeInterval = 5
    private(set) var isPlaying = false
    var isSuspended = false

    func stop() {
        isPlaying = false
        timer?.invalidate();
    }

    func play() {
        timer?.invalidate();
        timer = Timer.scheduledTimer(timeInterval: timeInterval, target: self,  selector: (#selector(updateTimer)),
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

    @objc fileprivate func updateTimer(){
        guard isSuspended else { return }

        DispatchQueue.main.async { [weak self] in
            self?.nextSlideActionHandler?()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
