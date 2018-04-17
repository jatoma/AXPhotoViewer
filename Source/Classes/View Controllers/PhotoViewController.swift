//
//  PhotoViewController.swift
//  AXPhotoViewer
//
//  Created by Alex Hill on 5/7/17.
//  Copyright © 2017 Alex Hill. All rights reserved.
//

import UIKit
import FLAnimatedImage

@objc(AXPhotoViewController) open class PhotoViewController: UIViewController, PageableViewControllerProtocol, ZoomingImageViewDelegate {
    
    public weak var delegate: PhotoViewControllerDelegate?
    public var pageIndex: Int = 0
    
    fileprivate(set) var loadingView: LoadingViewProtocol?
    private var playVideoButton: UIButton?

    var zoomingImageView = ZoomingImageView()
    
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
    }
    
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        let loadingViewSize = self.loadingView?.sizeThatFits(self.view.bounds.size) ?? .zero
        (self.loadingView as? UIView)?.frame = CGRect(origin: CGPoint(x: floor((self.view.bounds.size.width - loadingViewSize.width) / 2),
                                                                      y: floor((self.view.bounds.size.height - loadingViewSize.height) / 2)),
                                                      size: loadingViewSize)
        self.playVideoButton?.center = self.view.center
    }
    
    private func setupPlayVideoButton() -> UIButton? {
        guard let image = UIImage(named: "playIcon", in: Bundle(for: PhotoViewController.self), compatibleWith: nil) else { return nil }
        
        let button = UIButton()
        button.isHidden = true
        button.setImage(image, for: .normal)
        button.frame.size = image.size
        button.addTarget(self, action: #selector(playVideo), for: .touchUpInside)
        
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
            self.loadingView?.startLoading(initialProgress: photo.ax_progress)
        case .loadingFailed:
            resetImageView()
            let error = photo.ax_error ?? NSError()
            self.loadingView?.showError(error, retryHandler: { [weak self] in
                guard let uSelf = self else {
                    return
                }
                
                self?.delegate?.photoViewController(uSelf, retryDownloadFor: photo)
                self?.loadingView?.removeError()
                self?.loadingView?.startLoading(initialProgress: photo.ax_progress)
            })
        case .loaded:
            guard photo.image != nil || photo.imageData != nil else {
                assertionFailure("Must provide valid `UIImage` in \(#function)")
                return
            }
            
            self.loadingView?.stopLoading()
            
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
                self?.loadingView?.startLoading(initialProgress: photo.ax_progress)
                self?.view.setNeedsLayout()
            })
            
            self.view.setNeedsLayout()
        }
    }

    @objc fileprivate func playVideo() {
        guard let photo = photo else { return }
        
        self.delegate?.photoViewController(self, playVideoAt: self.pageIndex, asset: photo)
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
    
    @objc(photoViewController:playVideoAtIndex:forAsset:)
    func photoViewController(_ photoViewController: PhotoViewController, playVideoAt index: Int, asset: PhotoProtocol)
}
