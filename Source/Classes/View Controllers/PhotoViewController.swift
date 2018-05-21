//
//  PhotoViewController.swift
//  AXPhotoViewer
//
//  Created by Alex Hill on 5/7/17.
//  Copyright © 2017 Alex Hill. All rights reserved.
//

import UIKit
import FLAnimatedImage
import NVActivityIndicatorView

@objc(AXPhotoViewController) open class PhotoViewController: UIViewController, PageableViewControllerProtocol, ZoomingImageViewDelegate, BMPlayerDelegate {

    
    
    public weak var delegate: PhotoViewControllerDelegate?
    public var pageIndex: Int = 0
    
    public var isTransitioning = false
    
    public var isLoading = false
    
    fileprivate(set) var loadingView: LoadingViewProtocol?
    private var playVideoButton: UIButton?

    var zoomingImageView = ZoomingImageView()
    var videoPlayerView : BMPlayer?
    
    fileprivate var photo: PhotoProtocol?
    fileprivate weak var notificationCenter: NotificationCenter?

    
    public init(loadingView: LoadingViewProtocol, notificationCenter: NotificationCenter) {
        self.loadingView = loadingView
        self.notificationCenter = notificationCenter
        
        super.init(nibName: nil, bundle: nil)
        
        notificationCenter.addObserver(self,
                                       selector: #selector(photoLoadingProgressDidUpdate(_:)),
                                       name: .photoLoadingProgressUpdate,
                                       object: nil)
        
        notificationCenter.addObserver(self,
                                       selector: #selector(photoImageDidUpdate(_:)),
                                       name: .photoImageUpdate,
                                       object: nil)
        
        self.playVideoButton = setupPlayVideoButton()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.notificationCenter?.removeObserver(self)
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.addSubview(self.zoomingImageView)
        self.zoomingImageView.translatesAutoresizingMaskIntoConstraints = false
        self.zoomingImageView.frame = self.view.frame
        self.zoomingImageView.zoomScaleDelegate = self
        
        if let loadingView = self.loadingView as? UIView {
            self.view.addSubview(loadingView)
        }
        
        if let playVideoButton = self.playVideoButton {
            self.view.addSubview(playVideoButton)
        }

        setupVideoPlayerView()
    }
    
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let loadingViewSize = self.loadingView?.sizeThatFits(self.view.bounds.size) ?? .zero
        (self.loadingView as? UIView)?.frame = CGRect(origin: CGPoint(x: floor((self.view.bounds.size.width - loadingViewSize.width) / 2),
                                                                      y: floor((self.view.bounds.size.height - loadingViewSize.height) / 2)),
                                                      size: loadingViewSize)
        self.playVideoButton?.center = self.view.center
        
        videoPlayerView?.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view).inset(UIEdgeInsets.zero)
        }
    }
    
    open func didBecameActive() {
        isTransitioning = false
        if (self.delegate?.photoViewControllerShouldAutoPlayVideo(self))! {
            playIfVideo()
        }else{
            self.videoPlayerView?.isHidden = true
        }
    }
    
    
    open func didResignActive() {
        videoPlayerView?.seek(0)
        videoPlayerView?.pause()
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !isTransitioning {
            didResignActive()
        }
    }
    
    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let showVideo =  (photo?.isVideo ?? false) &&  (self.delegate?.photoViewControllerShouldAutoPlayVideo(self) ?? false)
        self.videoPlayerView?.isHidden = !showVideo
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isTransitioning {
            didBecameActive()
        }
    }
    
    private func setupPlayVideoButton() -> UIButton? {
        guard let image = UIImage(named: "playIcon", in: Bundle(for: PhotoViewController.self), compatibleWith: nil) else { return nil }
        
        let button = UIButton()
        button.isHidden = true
        button.setImage(image, for: .normal)
        button.frame.size = image.size
        button.addTarget(self, action: #selector(playIfVideo), for: .touchUpInside)
        return button
    }
    
    public func applyPhoto(_ photo: PhotoProtocol) {
        self.photo = photo
        
        weak var weakSelf = self
        func resetImageView() {
            weakSelf?.zoomingImageView.image = nil
            weakSelf?.zoomingImageView.animatedImage = nil
        }
        
        self.loadingView?.removeError()
        
        switch photo.ax_loadingState {
        case .loading, .notLoaded, .loadingCancelled:
            resetImageView()
            self.isLoading = true
            self.loadingView?.startLoading(initialProgress: photo.ax_progress)
        case .loadingFailed:
            resetImageView()
            let error = photo.ax_error ?? NSError()
            self.isLoading = false
            self.loadingView?.showError(error, retryHandler: { [weak self] in
                guard let uSelf = self else {
                    return
                }
                
                self?.delegate?.photoViewController(uSelf, retryDownloadFor: photo)
                self?.loadingView?.removeError()
                self?.isLoading = true
                self?.loadingView?.startLoading(initialProgress: photo.ax_progress)
            })
        case .loaded:
            guard photo.image != nil || photo.imageData != nil else {
                assertionFailure("Must provide valid `UIImage` in \(#function)")
                return
            }
            
            self.loadingView?.stopLoading()
            self.isLoading = false
            
            if let imageData = photo.imageData {
                self.zoomingImageView.animatedImage = FLAnimatedImage(animatedGIFData: imageData)
            } else if let image = photo.image {
                self.zoomingImageView.image = image
            }
            
            if photo.isVideo {
                self.playVideoButton?.isHidden = false
                self.zoomingImageView.isUserInteractionEnabled = false
            }
        }
        
        self.view.setNeedsLayout()
    }
    
    // MARK: - PageableViewControllerProtocol
    func prepareForReuse() {
        self.zoomingImageView.image = nil
        self.zoomingImageView.animatedImage = nil
        self.playVideoButton?.isHidden = true
        self.zoomingImageView.isUserInteractionEnabled = true
        self.isLoading = false
        isTransitioning = false
        
        setupVideoPlayerView()
    }
    
    // MARK: - ZoomingImageViewDelegate
    func zoomingImageView(_ zoomingImageView: ZoomingImageView, maximumZoomScaleFor imageSize: CGSize) -> CGFloat {
        return self.delegate?.photoViewController(self,
                                                  maximumZoomScaleForPhotoAt: self.pageIndex,
                                                  minimumZoomScale: zoomingImageView.minimumZoomScale,
                                                  imageSize: imageSize) ?? .leastNormalMagnitude
    }
    
    // MARK: - Notifications
    @objc fileprivate func photoLoadingProgressDidUpdate(_ notification: Notification) {
        guard let photo = notification.object as? PhotoProtocol else {
            assertionFailure("Photos must conform to the AXPhoto protocol.")
            return
        }
        
        guard photo === self.photo, let progress = notification.userInfo?[PhotosViewControllerNotification.ProgressKey] as? CGFloat else {
            return
        }
        
        self.loadingView?.updateProgress?(progress)
    }
    
    @objc fileprivate func photoImageDidUpdate(_ notification: Notification) {
        guard let photo = notification.object as? PhotoProtocol else {
            assertionFailure("Photos must conform to the AXPhoto protocol.")
            return
        }
        
        guard photo === self.photo, let userInfo = notification.userInfo else {
            return
        }
        
        if userInfo[PhotosViewControllerNotification.ImageDataKey] != nil || userInfo[PhotosViewControllerNotification.ImageKey] != nil {
            self.applyPhoto(photo)
        } else if let referenceView = userInfo[PhotosViewControllerNotification.ReferenceViewKey] as? FLAnimatedImageView {
            self.zoomingImageView.imageView.ax_syncFrames(with: referenceView)
        } else if let error = userInfo[PhotosViewControllerNotification.ErrorKey] as? Error {
            self.loadingView?.showError(error, retryHandler: { [weak self] in
                guard let uSelf = self, let photo = uSelf.photo else {
                    return
                }
                
                self?.delegate?.photoViewController(uSelf, retryDownloadFor: photo)
                self?.loadingView?.removeError()
                self?.isLoading = true
                self?.loadingView?.startLoading(initialProgress: photo.ax_progress)
                self?.view.setNeedsLayout()
            })
            self.view.setNeedsLayout()
        }
    }

    @objc fileprivate func playIfVideo() {
        guard let photo = photo, photo.isVideo else {
            videoPlayerView?.isHidden = true
            return
        }
        videoPlayerView?.isHidden = false
        isLoading = true
        let asset = BMPlayerResource(url: photo.videoPlaybackUrl!,
                                     name: photo.attributedTitle??.string ?? "")
        videoPlayerView?.setVideo(resource: asset)
        videoPlayerView?.delegate = self
        videoPlayerView?.play()
        showVideoControls(visible: self.delegate?.photoViewControllerShouldShowVideoControls(self) ?? false)
        self.delegate?.photoViewController(self, didStartPlayingVideoAt: self.pageIndex, asset: photo)
    }
    
    public func bmPlayer(player: BMPlayer, playerStateDidChange state: BMPlayerState) {
         guard let photo = photo else { return }

        if state == BMPlayerState.playedToTheEnd {
            self.delegate?.photoViewController(self, didEndPlayingVideoAt: self.pageIndex, asset: photo)
            videoPlayerView?.isHidden = true
        }
    }
    
    public func bmPlayer(player: BMPlayer, loadedTimeDidChange loadedDuration: TimeInterval, totalDuration: TimeInterval) {
        
    }
    
    public func bmPlayer(player: BMPlayer, playTimeDidChange currentTime: TimeInterval, totalTime: TimeInterval) {
        
    }
    
    public func bmPlayer(player: BMPlayer, playerIsPlaying playing: Bool) {
        if isLoading && playing {
            isLoading = false
        }
    }
    
    func setupVideoPlayerView() {
        BMPlayerConf.allowLog = false
        BMPlayerConf.shouldAutoPlay = true
        BMPlayerConf.tintColor = .white
        BMPlayerConf.topBarShowInCase = .none
        BMPlayerConf.loaderType  = NVActivityIndicatorType.ballRotateChase
        BMPlayerConf.enablePanGestures = false
        BMPlayerConf.enableTouchGesture = false
        BMPlayerConf.enableAutoHideControls = false
        BMPlayerConf.enableBrightnessGestures = false
        BMPlayerConf.enableVolumeGestures = false
        BMPlayerConf.enablePlaytimeGestures = false
        
        videoPlayerView?.removeFromSuperview()
        videoPlayerView = nil
        videoPlayerView = BMPlayer()
        self.view.addSubview(videoPlayerView!)
        videoPlayerView?.isHidden = false
    }
    
    func showVideoControls(visible: Bool) {
        videoPlayerView?.showControlView(visible: visible)
    }
    
    func isPlayingVideo() -> Bool {
        guard let videoPlayerView = videoPlayerView else {
                return false
        }
    
        return videoPlayerView.isPlaying
    }
}

@objc(AXPhotoViewControllerDelegate) public protocol PhotoViewControllerDelegate: AnyObject, NSObjectProtocol {
    
    @objc(photoViewController:retryDownloadForPhoto:)
    func photoViewController(_ photoViewController: PhotoViewController, retryDownloadFor photo: PhotoProtocol)
    
    @objc(photoViewController:maximumZoomScaleForPhotoAtIndex:minimumZoomScale:imageSize:)
    func photoViewController(_ photoViewController: PhotoViewController,
                             maximumZoomScaleForPhotoAt index: Int,
                             minimumZoomScale: CGFloat,
                             imageSize: CGSize) -> CGFloat
    
    @objc(photoViewController:didStartPlayingVideoAt:forAsset:)
    func photoViewController(_ photoViewController: PhotoViewController, didStartPlayingVideoAt index: Int, asset: PhotoProtocol)
    func photoViewController(_ photoViewController: PhotoViewController, didEndPlayingVideoAt index: Int, asset: PhotoProtocol)
    func photoViewControllerShouldAutoPlayVideo(_ photoViewController: PhotoViewController) -> Bool
    func photoViewControllerShouldShowVideoControls(_ photoViewController: PhotoViewController) -> Bool
}
