//
//  PhotosViewController.swift
//  AXPhotoViewer
//
//  Created by Alex Hill on 5/7/17.
//  Copyright © 2017 Alex Hill. All rights reserved.
//

import UIKit
import MobileCoreServices

@objc(AXPhotosViewController) open class PhotosViewController: UIViewController, UIPageViewControllerDelegate, UIPageViewControllerDataSource,
                                                               UIViewControllerTransitioningDelegate, PhotoViewControllerDelegate, NetworkIntegrationDelegate,
                                                               PhotosTransitionControllerDelegate {
    
    open weak var delegate: PhotosViewControllerDelegate?
    
    /// The underlying `OverlayView` that is used for displaying photo captions, titles, and actions.
    open let overlayView = OverlayView()
    
    open var shouldHaveHiddenNavigationInitially = true
    
    /// The photos to display in the PhotosViewController.
    open var dataSource = PhotosDataSource() {
        didSet {
            // this can occur during `commonInit(dataSource:pagingConfig:transitionInfo:networkIntegration:)`
            // if that's the case, this logic will be applied in `viewDidLoad()`
            if self.pageViewController == nil || self.networkIntegration == nil {
                return
            }
            
            self.pageViewController.dataSource = (self.dataSource.numberOfPhotos > 1) ? self : nil
            self.networkIntegration.cancelAllLoads()
            self.configureInitialPageViewController()
        }
    }
    
    /// The configuration object applied to the internal pager at initialization.
    open fileprivate(set) var pagingConfig = PagingConfig()
    
    /// The underlying UIPageViewController that is used for swiping horizontally and vertically.
    /// - Important: `AXPhotosViewController` is this page view controller's `UIPageViewControllerDelegate`, `UIPageViewControllerDataSource`.
    ///              Changing these values will result in breakage.
    /// - Note: Initialized by the end of `commonInit(dataSource:pagingConfig:transitionInfo:networkIntegration:)`.
    public fileprivate(set) var pageViewController: UIPageViewController!
    
    /// The internal tap gesture recognizer that is used to hide/show the overlay interface.
    public let singleTapGestureRecognizer = UITapGestureRecognizer()
    
    /// The close bar button item that is initially set in the overlay's navigation bar. Any 'target' or 'action' provided to this button will be overwritten.
    /// Overriding this is purely for customizing the look and feel of the button.
    /// Alternatively, you may create your own `UIBarButtonItem`s and directly set them _and_ their actions on the `overlayView` property.
    open var closeBarButtonItem: UIBarButtonItem {
        get {
            return UIBarButtonItem(barButtonSystemItem: .stop, target: nil, action: nil)
        }
    }
    
    /// The action bar button item that is initially set in the overlay's navigation bar. Any 'target' or 'action' provided to this button will be overwritten.
    /// Overriding this is purely for customizing the look and feel of the button.
    /// Alternatively, you may create your own `UIBarButtonItem`s and directly set them _and_ their actions on the `overlayView` property.
    open var actionBarButtonItem: UIBarButtonItem {
        get {
            return UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareAction(_:)))
        }
    }
    
    open var automaticSlideshowLoopEnabled = false

    open let automaticSlideshow = AutomaticSlideshow()

    open var slideshowBarButtonItem: UIBarButtonItem {
        get {
            let type = automaticSlideshow.isPlaying ? UIBarButtonSystemItem.pause : UIBarButtonSystemItem.play
            let button = UIBarButtonItem(barButtonSystemItem: type, target: self, action: #selector(slideshowAction(_:)))
            let topImageOffset: CGFloat = 4.0
            button.imageInsets = UIEdgeInsets(top: topImageOffset, left: 0, bottom: 0, right: 0)
            return button
        }
    }

    /// The `TransitionInfo` passed in at initialization. This object is used to define functionality for the presentation and dismissal
    /// of the `PhotosViewController`.
    open fileprivate(set) var transitionInfo = TransitionInfo()
    
    /// The `NetworkIntegration` passed in at initialization. This object is used to fetch images asynchronously from a cache or URL.
    /// - Initialized by the end of `commonInit(dataSource:pagingConfig:transitionInfo:networkIntegration:)`.
    public fileprivate(set) var networkIntegration: NetworkIntegrationProtocol!
    
    /// The view controller containing the photo currently being shown.
    public var currentPhotoViewController: PhotoViewController? {
        get {
            //return self.cachedPhotoViewControllers.filter({ $0.pageIndex == currentPhotoIndex }).first
            return self.pageViewController.viewControllers?.first as? PhotoViewController
        }
    }
    
    /// The index of the photo currently being shown.
    public fileprivate(set) var currentPhotoIndex: Int = 0 {
        didSet {
            self.updateOverlay(for: currentPhotoIndex)
        }
    }
    
    public fileprivate(set) var previousPhotoIndex: Int = 0
    
    // MARK: - Private/internal variables
    fileprivate enum SwipeDirection {
        case none, left, right
    }
    
    /// If the `PhotosViewController` is being presented in a fullscreen container, this value is set when the `PhotosViewController`
    /// is added to a parent view controller to allow `PhotosViewController` to be its transitioning delegate.
    fileprivate weak var containerViewController: UIViewController? {
        didSet {
            oldValue?.transitioningDelegate = nil
            
            if let containerViewController = self.containerViewController {
                containerViewController.transitioningDelegate = self
                self.transitioningDelegate = nil
                self.transitionController?.containerViewController = containerViewController
            } else {
                self.transitioningDelegate = self
                self.transitionController?.containerViewController = nil
            }
        }
    }
    
    fileprivate var isSizeTransitioning = false
    fileprivate var isViewTransitioning = false
    fileprivate var isForcingNonInteractiveDismissal = false
    fileprivate var isFirstAppearance = true
    
    fileprivate var transitionController: PhotosTransitionController?
    fileprivate let notificationCenter = NotificationCenter()
    
    fileprivate var _prefersStatusBarHidden: Bool = false
    open override var prefersStatusBarHidden: Bool {
        get {
            return _prefersStatusBarHidden
        }
        set {
            _prefersStatusBarHidden = newValue
        }
    }
    
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        get {
            return .lightContent
        }
    }
    
    // MARK: - Initialization
    #if AX_SDWEBIMAGE_SUPPORT || AX_PINREMOTEIMAGE_SUPPORT || AX_AFNETWORKING_SUPPORT || AX_KINGFISHER_SUPPORT || AX_LITE_SUPPORT
    public init() {
        super.init(nibName: nil, bundle: nil)
        self.commonInit()
    }
    
    public init(dataSource: PhotosDataSource?) {
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource)
    }
    
    public init(dataSource: PhotosDataSource?,
                pagingConfig: PagingConfig?) {
        
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource,
                        pagingConfig: pagingConfig)
    }
    
    public init(pagingConfig: PagingConfig?,
                transitionInfo: TransitionInfo?) {
        
        super.init(nibName: nil, bundle: nil)
        self.commonInit(pagingConfig: pagingConfig,
                        transitionInfo: transitionInfo)
    }
    
    public init(dataSource: PhotosDataSource?,
                pagingConfig: PagingConfig?,
                transitionInfo: TransitionInfo?) {
        
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource,
                        pagingConfig: pagingConfig,
                        transitionInfo: transitionInfo)
    }
    #else
    public init(networkIntegration: NetworkIntegrationProtocol) {
        super.init(nibName: nil, bundle: nil)
        self.commonInit(networkIntegration: networkIntegration)
    }
    
    public init(dataSource: PhotosDataSource?,
                networkIntegration: NetworkIntegrationProtocol) {
    
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource,
                        networkIntegration: networkIntegration)
    }
    
    public init(dataSource: PhotosDataSource?,
                pagingConfig: PagingConfig?,
                networkIntegration: NetworkIntegrationProtocol) {
    
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource,
                        pagingConfig: pagingConfig,
                        networkIntegration: networkIntegration)
    }
    
    public init(pagingConfig: PagingConfig?,
                transitionInfo: TransitionInfo?,
                networkIntegration: NetworkIntegrationProtocol) {
    
        super.init(nibName: nil, bundle: nil)
        self.commonInit(pagingConfig: pagingConfig,
                        transitionInfo: transitionInfo,
                        networkIntegration: networkIntegration)
    }
    
    public init(dataSource: PhotosDataSource?,
                pagingConfig: PagingConfig?,
                transitionInfo: TransitionInfo?,
                networkIntegration: NetworkIntegrationProtocol) {

        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource,
                        pagingConfig: pagingConfig,
                        transitionInfo: transitionInfo,
                        networkIntegration: networkIntegration)
    }
    #endif
    
    @objc(initFromPreviewingPhotosViewController:)
    public init(from previewingPhotosViewController: PreviewingPhotosViewController) {
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: previewingPhotosViewController.dataSource,
                        networkIntegration: previewingPhotosViewController.networkIntegration)
        
        self.loadViewIfNeeded()
        self.currentPhotoViewController?.zoomingImageView.imageView.ax_syncFrames(with: previewingPhotosViewController.imageView)
    }
    
    @objc(initFromPreviewingPhotosViewController:pagingConfig:)
    public init(from previewingPhotosViewController: PreviewingPhotosViewController,
                pagingConfig: PagingConfig?) {
        
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: previewingPhotosViewController.dataSource,
                        pagingConfig: pagingConfig,
                        networkIntegration: previewingPhotosViewController.networkIntegration)
        
        self.loadViewIfNeeded()
        self.currentPhotoViewController?.zoomingImageView.imageView.ax_syncFrames(with: previewingPhotosViewController.imageView)
    }
    
    @objc(initFromPreviewingPhotosViewController:pagingConfig:transitionInfo:)
    public init(from previewingPhotosViewController: PreviewingPhotosViewController,
                pagingConfig: PagingConfig?,
                transitionInfo: TransitionInfo?) {
        
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: previewingPhotosViewController.dataSource,
                        pagingConfig: pagingConfig,
                        transitionInfo: transitionInfo,
                        networkIntegration: previewingPhotosViewController.networkIntegration)
        
        self.loadViewIfNeeded()
        self.currentPhotoViewController?.zoomingImageView.imageView.ax_syncFrames(with: previewingPhotosViewController.imageView)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // init to be used internally by the library
    @nonobjc init(dataSource: PhotosDataSource? = nil,
                  pagingConfig: PagingConfig? = nil,
                  transitionInfo: TransitionInfo? = nil,
                  networkIntegration: NetworkIntegrationProtocol? = nil) {
        
        super.init(nibName: nil, bundle: nil)
        self.commonInit(dataSource: dataSource,
                        pagingConfig: pagingConfig,
                        transitionInfo: transitionInfo,
                        networkIntegration: networkIntegration)
    }
    
    fileprivate func commonInit(dataSource: PhotosDataSource? = nil,
                                pagingConfig: PagingConfig? = nil,
                                transitionInfo: TransitionInfo? = nil,
                                networkIntegration: NetworkIntegrationProtocol? = nil) {
        
        if let uDataSource = dataSource {
            self.dataSource = uDataSource
        }
        
        if let uPagingConfig = pagingConfig {
            self.pagingConfig = uPagingConfig
        }
        
        if let uTransitionInfo = transitionInfo {
            self.transitionInfo = uTransitionInfo
        }
        
        var uNetworkIntegration = networkIntegration
        if networkIntegration == nil {
            #if AX_SDWEBIMAGE_SUPPORT
                uNetworkIntegration = SDWebImageIntegration()
            #elseif AX_PINREMOTEIMAGE_SUPPORT
                uNetworkIntegration = PINRemoteImageIntegration()
            #elseif AX_AFNETWORKING_SUPPORT
                uNetworkIntegration = AFNetworkingIntegration()
            #elseif AX_KINGFISHER_SUPPORT
                uNetworkIntegration = KingfisherIntegration()
            #elseif AX_LITE_SUPPORT
                uNetworkIntegration = SimpleNetworkIntegration()
            #else
                fatalError("Must be using one of the network integration subspecs if no `NetworkIntegration` is going to be provided.")
            #endif
        }
        
        self.networkIntegration = uNetworkIntegration
        self.networkIntegration.delegate = self
        
        self.pageViewController = UIPageViewController(transitionStyle: .scroll,
                                                       navigationOrientation: self.pagingConfig.navigationOrientation,
                                                       options: [UIPageViewControllerOptionInterPageSpacingKey: self.pagingConfig.interPhotoSpacing])
    }
    
   
    
    open override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        self.reduceMemoryForPhotos(at: self.currentPhotoIndex)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .black

        automaticSlideshow.nextSlideActionHandler = { [weak self] in
            if let weakSelf = self, weakSelf.canSlideToNext() {
                weakSelf.slideToNext()
            }
        }
        automaticSlideshow.play()
        
        self.transitionController = PhotosTransitionController(photosViewController: self, transitionInfo: self.transitionInfo)
        self.transitionController?.delegate = self
        
        if let containerViewController = self.containerViewController {
            containerViewController.transitioningDelegate = self
            self.transitionController?.containerViewController = containerViewController
        } else {
            self.transitioningDelegate = self
            self.transitionController?.containerViewController = nil
        }
   

        if self.pageViewController.view.superview == nil {
            self.pageViewController.delegate = self
            self.pageViewController.dataSource = (self.dataSource.numberOfPhotos > 1) ? self : nil
            
            self.singleTapGestureRecognizer.numberOfTapsRequired = 1
            self.singleTapGestureRecognizer.addTarget(self, action: #selector(singleTapAction(_:)))
            self.pageViewController.view.addGestureRecognizer(self.singleTapGestureRecognizer)
            
            self.addChildViewController(self.pageViewController)
            self.view.addSubview(self.pageViewController.view)
            self.pageViewController.didMove(toParentViewController: self)
            
            self.configureInitialPageViewController()
        }
        
        if self.overlayView.superview == nil {
            self.overlayView.tintColor = .white
            self.overlayView.setShowInterface(true, animated: false)
            let closeBarButtonItem = self.closeBarButtonItem
            closeBarButtonItem.target = self
            closeBarButtonItem.action = #selector(closeAction(_:))
            self.overlayView.leftBarButtonItem = closeBarButtonItem
            self.overlayView.setShowInterface(false, animated: false)
            self.currentPhotoViewController?.showVideoControls(visible: false)
            self.view.addSubview(self.overlayView)
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if self.isFirstAppearance && !shouldHaveHiddenNavigationInitially{
            self.overlayView.setShowInterface(true, animated: true, alongside: { [weak self] in
                self?.currentPhotoViewController?.showVideoControls(visible: true)
                self?.updateStatusBarAppearance(show: true)
            })
            self.isFirstAppearance = false
        }
    }
    
    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.isSizeTransitioning = true
        coordinator.animate(alongsideTransition: nil) { [weak self] (context) in
            self?.isSizeTransitioning = false
        }
    }
    
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.pageViewController.view.frame = self.view.bounds
        self.overlayView.frame = self.view.bounds
        self.overlayView.contentInset = UIEdgeInsets(top: (UIApplication.shared.statusBarFrame.size.height > 0) ? 20 : 0,
                                                     left: 0,
                                                     bottom: 0, 
                                                     right: 0)
    }
    
    open override func didMove(toParentViewController parent: UIViewController?) {
        super.didMove(toParentViewController: parent)
        
        if parent is UINavigationController {
            assertionFailure("Do not embed `PhotosViewController` in a navigation stack.")
            return
        }
        
        self.containerViewController = parent
    }

    // MARK: - UIViewControllerTransitioningDelegate, PhotosViewControllerTransitionAnimatorDelegate, PhotosViewControllerTransitionAnimatorDelegate
    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let photo = self.dataSource.photo(at: self.currentPhotoIndex) else {
            return nil
        }
        
        self.transitionInfo.resolveEndingViewClosure?(photo, self.currentPhotoIndex)
        guard let transitionController = self.transitionController, transitionController.supportsModalPresentationStyle(self.modalPresentationStyle) &&
                                                                    (transitionController.supportsContextualDismissal ||
                                                                    transitionController.supportsInteractiveDismissal) else {
            return nil
        }
        
        transitionController.mode = .dismissing
        return transitionController
    }
    
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let transitionController = self.transitionController, transitionController.supportsModalPresentationStyle(self.modalPresentationStyle) &&
                                                                    transitionController.supportsContextualPresentation else {
            return nil
        }
        
        transitionController.mode = .presenting
        return transitionController
    }
    
    public func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        guard let transitionController = self.transitionController, transitionController.supportsInteractiveDismissal &&
                                                                    !self.isForcingNonInteractiveDismissal else {
            return nil
        }
        
        return transitionController
    }
    
    func transitionController(_ transitionController: PhotosTransitionController,
                              didFinishAnimatingWith view: UIImageView, 
                              transitionControllerMode: PhotosTransitionControllerMode) {
        
        guard let photo = self.dataSource.photo(at: self.currentPhotoIndex) else {
            return
        }
        
        if transitionControllerMode == .presenting {
            self.notificationCenter.post(name: .photoImageUpdate,
                                         object: photo,
                                         userInfo: [
                                            PhotosViewControllerNotification.ReferenceViewKey: view
                                         ])
        }
    }
    
    
    func slideToNext(){
        let nextPhotoIndex = self.currentPhotoIndex + 1
        if let nextController = self.makePhotoViewController(for: nextPhotoIndex) {
            loadPhotos(at: nextController.pageIndex)
            self.isViewTransitioning = true
            slide(to: nextController, animated: true, completion: { [weak self] (result) in
               
                self?.reduceMemoryForPhotos(at: nextController.pageIndex)
                self?.isViewTransitioning = false
            })
        }else {
            //start from begining if enabled
            if !automaticSlideshowLoopEnabled { return }
            let initialPhotoIdex = 0
            self.isViewTransitioning = true
            if  let initialController = self.makePhotoViewController(for: initialPhotoIdex){
                loadPhotos(at: initialController.pageIndex)
                slide(to: initialController, animated: true, completion: { [weak self] (result) in
                    self?.reduceMemoryForPhotos(at: initialController.pageIndex)
                    self?.isViewTransitioning = false
                })
            }
        }
    }
    
    func canSlideToNext() -> Bool {
        if self.isViewTransitioning { return false }
        
        guard let currentPhotoViewController = self.currentPhotoViewController else { return false }
        
        let isPlayingVideo = currentPhotoViewController.isPlayingVideo()
        let isLoading = currentPhotoViewController.isLoading
        let canSlide = !isPlayingVideo && !isLoading
        return canSlide
    }
    

    
    func slide(to photoViewController: PhotoViewController, animated: Bool, completion: ((Bool) -> Swift.Void)? = nil) {
        configure(with: photoViewController, pageIndex: photoViewController.pageIndex, animated: animated, completion: completion)
    }
    
    func configure(with viewController: UIViewController, pageIndex: Int, animated: Bool, completion: ((Bool) -> Swift.Void)? = nil) {
        self.currentPhotoIndex = pageIndex
        self.pageViewController.setViewControllers([viewController], direction: .forward, animated: animated, completion: completion)
        self.overlayView.ignoresInternalTitle = false
        self.overlayView.titleView?.tweenBetweenLowIndex?(pageIndex, highIndex: pageIndex + 1, percent: 0)
    }
    
    // MARK: - Page VC Configuration
    fileprivate func configureInitialPageViewController() {
        guard let photoViewController = self.makePhotoViewController(for: self.dataSource.initialPhotoIndex) else {
            configure(with: UIViewController(), pageIndex: 0, animated: false)
            return
        }
        isViewTransitioning = true
        slide(to: photoViewController, animated: false , completion: { [weak self] (result) in
            self?.isViewTransitioning = false
            })
        self.loadPhotos(at: self.dataSource.initialPhotoIndex)
    }
    
    // MARK: - Overlay
    fileprivate func updateOverlay(for photoIndex: Int) {
        guard let photo = self.dataSource.photo(at: photoIndex) else {
            return
        }
        
        self.willUpdate(overlayView: self.overlayView, for: photo, at: photoIndex, totalNumberOfPhotos: self.dataSource.numberOfPhotos)
        
        if self.dataSource.numberOfPhotos > 1 {
            self.overlayView.internalTitle = NSLocalizedString("\(photoIndex + 1) of \(self.dataSource.numberOfPhotos)", comment: "")
        } else {
            self.overlayView.internalTitle = nil
        }
        
        self.overlayView.captionView.applyCaptionInfo(attributedTitle: photo.attributedTitle ?? nil,
                                                      attributedDescription: photo.attributedDescription ?? nil,
                                                      attributedCredit: photo.attributedCredit ?? nil)
        self.updateBarButtons(for: photoIndex)
    }
    
    private func updateBarButtons(for photoIndex: Int){
        guard let photo = self.dataSource.photo(at: photoIndex) else {
            return
        }

        if (photo.isVideo && !photo.isDownloaded) {
            self.overlayView.rightBarButtonItems = [slideshowBarButtonItem]
        }else {
            self.overlayView.rightBarButtonItems = [actionBarButtonItem, slideshowBarButtonItem]
        }
    }
    
    @objc fileprivate func singleTapAction(_ sender: UITapGestureRecognizer) {
        let show = (self.overlayView.alpha == 0)
        self.overlayView.setShowInterface(show, animated: true, alongside: { [weak self] in
            self?.currentPhotoViewController?.showVideoControls(visible: show)
            self?.updateStatusBarAppearance(show: show)
        })
    }
    
    fileprivate func updateStatusBarAppearance(show: Bool) {
        self.prefersStatusBarHidden = !show
        self.setNeedsStatusBarAppearanceUpdate()
        if show {
            UIView.performWithoutAnimation { [weak self] in
                self?.overlayView.contentInset = UIEdgeInsets(top: (UIApplication.shared.statusBarFrame.size.height > 0) ? 20 : 0,
                                                              left: 0,
                                                              bottom: 0,
                                                              right: 0)
                self?.overlayView.setNeedsLayout()
                self?.overlayView.layoutIfNeeded()
            }
        }
    }
    
    // MARK: - Default bar button actions
    @objc public func shareAction(_ barButtonItem: UIBarButtonItem) {
        guard let photo = self.dataSource.photo(at: self.currentPhotoIndex) else {
            return
        }
        
        if self.handleActionButtonTapped(photo: photo) {
            return
        }
        
        var anyRepresentation: Any?
        
        if photo.isVideo && photo.isDownloaded {
            anyRepresentation = photo.videoPlaybackUrl
        } else if let imageData = photo.imageData {
            anyRepresentation = imageData
        } else if let image = photo.image {
            anyRepresentation = image
        }

        guard let uAnyRepresentation = anyRepresentation else {
            return
        }
        
        let activityViewController = UIActivityViewController(activityItems: [uAnyRepresentation], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, activityError) in
            guard let uSelf = self else {
                return
            }
            
            if completed, let activityType = activityType {
                uSelf.actionCompleted(activityType: activityType, for: photo)
            }
        }
        
        activityViewController.popoverPresentationController?.barButtonItem = barButtonItem
        self.present(activityViewController, animated: true)
    }
    
    @objc public func closeAction(_ sender: UIBarButtonItem) {
        automaticSlideshow.stop()
        self.isForcingNonInteractiveDismissal = true
        self.presentingViewController?.dismiss(animated: true)
    }
    
    @objc public func slideshowAction(_ sender: UIBarButtonItem) {
        automaticSlideshow.toggle()
        self.overlayView.rightBarButtonItems = [actionBarButtonItem, slideshowBarButtonItem]
    }

    
    // MARK: - Loading helpers
    fileprivate func loadPhotos(at index: Int) {
        let numberOfPhotosToLoad = self.dataSource.prefetchBehavior.rawValue
        let startIndex = (((index - (numberOfPhotosToLoad / 2)) >= 0) ? (index - (numberOfPhotosToLoad / 2)) : 0)
        let indexes = startIndex...(startIndex + numberOfPhotosToLoad)
        
        for index in indexes {
            guard let photo = self.dataSource.photo(at: index) else {
                return
            }
            
            if photo.ax_loadingState == .notLoaded || photo.ax_loadingState == .loadingCancelled {
                photo.ax_loadingState = .loading
                self.networkIntegration.loadPhoto(photo)
            }
        }
    }
    
    fileprivate func reduceMemoryForPhotos(at index: Int) {
        let numberOfPhotosToLoad = self.dataSource.prefetchBehavior.rawValue
        let lowerIndex = (index - (numberOfPhotosToLoad / 2) - 1 >= 0) ? index - (numberOfPhotosToLoad / 2) - 1: NSNotFound
        let upperIndex = (index + (numberOfPhotosToLoad / 2) + 1 < self.dataSource.numberOfPhotos) ? index + (numberOfPhotosToLoad / 2) + 1 : NSNotFound
        
        weak var weakSelf = self
        func reduceMemory(for photo: PhotoProtocol) {
            guard let uSelf = weakSelf else {
                return
            }
            
            if photo.ax_loadingState == .loading {
                uSelf.networkIntegration.cancelLoad(for: photo)
                photo.ax_loadingState = .loadingCancelled
            } else if photo.ax_loadingState == .loaded && photo.ax_isReducible {
                photo.imageData = nil
                photo.image = nil
                photo.ax_loadingState = .notLoaded
            }
        }
        
        if lowerIndex != NSNotFound, let photo = self.dataSource.photo(at: lowerIndex) {
            reduceMemory(for: photo)
        }
        
        if upperIndex != NSNotFound, let photo = self.dataSource.photo(at: upperIndex) {
            reduceMemory(for: photo)
        }
    }
    
    // MARK: - Reuse / Factory
    fileprivate func makePhotoViewController(for pageIndex: Int) -> PhotoViewController? {
        guard let photo = self.dataSource.photo(at: pageIndex) else {
            return nil
        }
        
        guard let loadingView = self.makeLoadingView(for: pageIndex) else {
            return nil
        }
        
        let photoViewController = PhotoViewController(loadingView: loadingView, notificationCenter: self.notificationCenter)
        photoViewController.delegate = self
        
        self.singleTapGestureRecognizer.require(toFail: photoViewController.zoomingImageView.doubleTapGestureRecognizer)
    
        photoViewController.pageIndex = pageIndex
        photoViewController.applyPhoto(photo)
        return photoViewController
    }
    
    fileprivate func makeLoadingView(for pageIndex: Int) -> LoadingViewProtocol? {
        guard let loadingViewType = self.pagingConfig.loadingViewClass as? UIView.Type else {
            assertionFailure("`loadingViewType` must be a UIView.")
            return nil
        }
        
        return loadingViewType.init() as? LoadingViewProtocol
    }

 
    
    // MARK: - UIPageViewControllerDataSource
    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        guard let viewController = pendingViewControllers.first as? PhotoViewController else {
            return
        }
        self.currentPhotoViewController?.isTransitioning = true
        isViewTransitioning = true
        previousPhotoIndex = self.currentPhotoIndex
        self.currentPhotoIndex = viewController.pageIndex
        self.loadPhotos(at: viewController.pageIndex)
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard let viewController = pageViewController.viewControllers?.first as? PhotoViewController else {
            return
        }
        
        self.currentPhotoIndex = viewController.pageIndex
        self.reduceMemoryForPhotos(at: viewController.pageIndex)
        
        if let previousViewController = previousViewControllers.first as? PhotoViewController  {
            //only reload in case new page index
            if previousPhotoIndex != viewController.pageIndex {
                viewController.didBecameActive()
                previousViewController.didResignActive()
            }
        }else {
            viewController.didBecameActive()
        }
        isViewTransitioning = false
        automaticSlideshow.restart()
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let uViewController = viewController as? PhotoViewController else {
            assertionFailure("Paging VC must be a subclass of `PhotoViewController`.")
            return nil
        }
        
        return self.pageViewController(pageViewController, viewControllerAt: uViewController.pageIndex - 1)
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let uViewController = viewController as? PhotoViewController else {
            assertionFailure("Paging VC must be a subclass of `PhotoViewController`.")
            return nil
        }
        
        return self.pageViewController(pageViewController, viewControllerAt: uViewController.pageIndex + 1)
    }
    
    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAt index: Int) -> UIViewController? {
        guard index >= 0 && self.dataSource.numberOfPhotos > index else {
            return nil
        }
        
        return self.makePhotoViewController(for: index)
    }
    
    // MARK: - PhotoViewControllerDelegate
    public func photoViewController(_ photoViewController: PhotoViewController, retryDownloadFor photo: PhotoProtocol) {
        guard photo.ax_loadingState != .loading && photo.ax_loadingState != .loaded else {
            return
        }
        
        photo.ax_error = nil
        photo.ax_loadingState = .loading
        self.networkIntegration.loadPhoto(photo)
    }
    
    public func photoViewController(_ photoViewController: PhotoViewController,
                                    maximumZoomScaleForPhotoAt index: Int,
                                    minimumZoomScale: CGFloat,
                                    imageSize: CGSize) -> CGFloat {
        
        guard let photo = self.dataSource.photo(at: index) else {
            return .leastNormalMagnitude
        }
        
        return self.maximumZoomScale(for: photo, minimumZoomScale: minimumZoomScale, imageSize: imageSize)
    }
    
    public func photoViewController(_ photoViewController: PhotoViewController, didStartPlayingVideoAt index: Int, asset: PhotoProtocol) {
    }

    public func photoViewController(_ photoViewController: PhotoViewController, didEndPlayingVideoAt index: Int, asset: PhotoProtocol){
        if automaticSlideshow.isPlaying {
            slideToNext()
        }
    }

    public func photoViewControllerShouldAutoPlayVideo(_ photoViewController: PhotoViewController) -> Bool {
        return automaticSlideshow.isPlaying
    }
    
    public func photoViewControllerShouldShowVideoControls(_ photoViewController: PhotoViewController) -> Bool {
    
        return !self.overlayView.isHidden
    }
    
    // MARK: - PhotosViewControllerDelegate calls
    
    /// Called when the `PhotosViewController` navigates to a new photo. This is defined as when the swipe percent between pages
    /// is greater than the threshold (>0.5).
    ///
    /// If you override this and fail to call super, the corresponding delegate method **will not be called!**
    ///
    /// - Parameters:
    ///   - photo: The `Photo` that was navigated to.
    ///   - index: The `index` in the dataSource of the `Photo` being transitioned to.
    @objc(didNavigateToPhoto:atIndex:)
    open func didNavigateTo(photo: PhotoProtocol, at index: Int) {
       
        self.delegate?.photosViewController?(self, didNavigateTo: photo, at: index)
    }
    
    /// Called when the `PhotosViewController` is configuring its `OverlayView` for a new photo. This should be used to update the
    /// the overlay's title or any other overlay-specific properties.
    ///
    /// If you override this and fail to call super, the corresponding delegate method **will not be called!**
    ///
    /// - Parameters:
    ///   - overlayView: The `OverlayView` that is being updated.
    ///   - photo: The `Photo` the overlay is being configured for.
    ///   - index: The index of the `Photo` that the overlay is being configured for.
    ///   - totalNumberOfPhotos: The total number of photos in the current `dataSource`.
    @objc(willUpdateOverlayView:forPhoto:atIndex:totalNumberOfPhotos:)
    open func willUpdate(overlayView: OverlayView, for photo: PhotoProtocol, at index: Int, totalNumberOfPhotos: Int) {
        self.delegate?.photosViewController?(self,
                                             willUpdate: overlayView,
                                             for: photo,
                                             at: index,
                                             totalNumberOfPhotos: totalNumberOfPhotos)
    }
    
    /// If implemented and returns a valid zoom scale for the photo (valid meaning >= the photo's minimum zoom scale), the underlying
    /// zooming image view will adopt the returned `maximumZoomScale` instead of the default calculated by the library. A good implementation
    /// of this method will use a combination of the provided `minimumZoomScale` and `imageSize` to extrapolate a `maximumZoomScale` to return.
    /// If the `minimumZoomScale` is returned (ie. `minimumZoomScale` == `maximumZoomScale`), zooming will be disabled for this image.
    ///
    /// If you override this and fail to call super, the corresponding delegate method **will not be called!**
    ///
    /// - Parameters:
    ///   - photo: The `Photo` that the zoom scale will affect.
    ///   - minimumZoomScale: The minimum zoom scale that is calculated by the library. This value cannot be changed.
    ///   - imageSize: The size of the image that belongs to the `Photo`.
    /// - Returns: A "maximum" zoom scale that >= `minimumZoomScale`.
    @objc(maximumZoomScaleForPhoto:minimumZoomScale:imageSize:)
    open func maximumZoomScale(for photo: PhotoProtocol, minimumZoomScale: CGFloat, imageSize: CGSize) -> CGFloat {
        return self.delegate?.photosViewController?(self,
                                                    maximumZoomScaleFor: photo,
                                                    minimumZoomScale: minimumZoomScale,
                                                    imageSize: imageSize) ?? .leastNormalMagnitude
    }
    
    /// Called when the action button is tapped for a photo. If you override this and fail to call super, the corresponding
    /// delegate method **will not be called!**
    ///
    /// - Parameters:
    ///   - photo: The related `Photo`.
    /// 
    /// - Returns:
    ///   true if the action button tap was handled, false if the default action button behavior
    ///   should be invoked.
    @objc(handleActionButtonTappedForPhoto:)
    open func handleActionButtonTapped(photo: PhotoProtocol) -> Bool {
        if let _ = self.delegate?.photosViewController?(self, handleActionButtonTappedFor: photo) {
            return true
        }
        
        return false
    }
    
    /// Called when an action button action is completed. If you override this and fail to call super, the corresponding
    /// delegate method **will not be called!**
    ///
    /// - Parameters:
    ///   - photo: The related `Photo`.
    /// - Note: This is only called for the default action.
    @objc(actionCompletedWithActivityType:forPhoto:)
    open func actionCompleted(activityType: UIActivityType, for photo: PhotoProtocol) {
        self.delegate?.photosViewController?(self, actionCompletedWith: activityType, for: photo)
    }
    
  

    // MARK: - NetworkIntegrationDelegate
    public func networkIntegration(_ networkIntegration: NetworkIntegrationProtocol, loadDidFinishWith photo: PhotoProtocol) {
    
        if let imageData = photo.imageData {
            photo.ax_loadingState = .loaded
            DispatchQueue.main.async { [weak self] in
                self?.notificationCenter.post(name: .photoImageUpdate,
                                              object: photo,
                                              userInfo: [
                                                 PhotosViewControllerNotification.ImageDataKey: imageData,
                                                 PhotosViewControllerNotification.LoadingStateKey: PhotoLoadingState.loaded
                                              ])
            }
        } else if let image = photo.image {
            photo.ax_loadingState = .loaded
            DispatchQueue.main.async { [weak self] in
                self?.notificationCenter.post(name: .photoImageUpdate,
                                              object: photo,
                                              userInfo: [
                                                PhotosViewControllerNotification.ImageKey: image,
                                                PhotosViewControllerNotification.LoadingStateKey: PhotoLoadingState.loaded
                                              ])
            }
        }
    }
    
    public func networkIntegration(_ networkIntegration: NetworkIntegrationProtocol, loadDidFailWith error: Error, for photo: PhotoProtocol) {
        guard photo.ax_loadingState != .loadingCancelled else {
            return
        }
        
        photo.ax_loadingState = .loadingFailed
        photo.ax_error = error
        DispatchQueue.main.async { [weak self] in
            self?.notificationCenter.post(name: .photoImageUpdate,
                                          object: photo,
                                          userInfo: [
                                            PhotosViewControllerNotification.ErrorKey: error,
                                            PhotosViewControllerNotification.LoadingStateKey: PhotoLoadingState.loadingFailed
                                          ])
        }
    }
    
    public func networkIntegration(_ networkIntegration: NetworkIntegrationProtocol, didUpdateLoadingProgress progress: CGFloat, for photo: PhotoProtocol) {
        photo.ax_progress = progress
        DispatchQueue.main.async { [weak self] in
            self?.notificationCenter.post(name: .photoLoadingProgressUpdate,
                                          object: photo,
                                          userInfo: [PhotosViewControllerNotification.ProgressKey: progress])
        }
    }

}


// MARK: - PhotosViewControllerDelegate
@objc(AXPhotosViewControllerDelegate) public protocol PhotosViewControllerDelegate: AnyObject, NSObjectProtocol {
    
    /// Called when the `PhotosViewController` navigates to a new photo. This is defined as when the swipe percent between pages
    /// is greater than the threshold (>0.5).
    ///
    /// - Parameters:
    ///   - photosViewController: The `PhotosViewController` that is navigating.
    ///   - photo: The `Photo` that was navigated to.
    ///   - index: The `index` in the dataSource of the `Photo` being transitioned to.
    @objc(photosViewController:didNavigateToPhoto:atIndex:)
    optional func photosViewController(_ photosViewController: PhotosViewController,
                                       didNavigateTo photo: PhotoProtocol,
                                       at index: Int)
    
    /// Called when the `PhotosViewController` is configuring its `OverlayView` for a new photo. This should be used to update the
    /// the overlay's title or any other overlay-specific properties.
    ///
    /// - Parameters:
    ///   - photosViewController: The `PhotosViewController` that is updating the overlay.
    ///   - overlayView: The `OverlayView` that is being updated.
    ///   - photo: The `Photo` the overlay is being configured for.
    ///   - index: The index of the `Photo` that the overlay is being configured for.
    ///   - totalNumberOfPhotos: The total number of photos in the current `dataSource`.
    @objc(photosViewController:willUpdateOverlayView:forPhoto:atIndex:totalNumberOfPhotos:)
    optional func photosViewController(_ photosViewController: PhotosViewController,
                                       willUpdate overlayView: OverlayView,
                                       for photo: PhotoProtocol,
                                       at index: Int,
                                       totalNumberOfPhotos: Int)
    
    /// If implemented and returns a valid zoom scale for the photo (valid meaning >= the photo's minimum zoom scale), the underlying
    /// zooming image view will adopt the returned `maximumZoomScale` instead of the default calculated by the library. A good implementation
    /// of this method will use a combination of the provided `minimumZoomScale` and `imageSize` to extrapolate a `maximumZoomScale` to return.
    /// If the `minimumZoomScale` is returned (ie. `minimumZoomScale` == `maximumZoomScale`), zooming will be disabled for this image.
    ///
    /// - Parameters:
    ///   - photosViewController: The `PhotosViewController` that is updating the photo's zoom scale.
    ///   - photo: The `Photo` that the zoom scale will affect.
    ///   - minimumZoomScale: The minimum zoom scale that is calculated by the library. This value cannot be changed.
    ///   - imageSize: The size of the image that belongs to the `Photo`.
    /// - Returns: A "maximum" zoom scale that >= `minimumZoomScale`.
    @objc(photosViewController:maximumZoomScaleForPhoto:minimumZoomScale:imageSize:)
    optional func photosViewController(_ photosViewController: PhotosViewController,
                                       maximumZoomScaleFor photo: PhotoProtocol,
                                       minimumZoomScale: CGFloat,
                                       imageSize: CGSize) -> CGFloat
    
    /// Called when the action button is tapped for a photo. If no implementation is provided, will fall back to default action.
    ///
    /// - Parameters:
    ///   - photosViewController: The `PhotosViewController` handling the action.
    ///   - photo: The related `Photo`.
    @objc(photosViewController:handleActionButtonTappedForPhoto:)
    optional func photosViewController(_ photosViewController: PhotosViewController, 
                                       handleActionButtonTappedFor photo: PhotoProtocol)
    
    /// Called when an action button action is completed.
    ///
    /// - Parameters:
    ///   - photosViewController: The `PhotosViewController` that handled the action.
    ///   - photo: The related `Photo`.
    /// - Note: This is only called for the default action.
    @objc(photosViewController:actionCompletedWithActivityType:forPhoto:)
    optional func photosViewController(_ photosViewController: PhotosViewController, 
                                       actionCompletedWith activityType: UIActivityType,
                                       for photo: PhotoProtocol)
    
}

// MARK: - Notification definitions
// Keep Obj-C land happy
@objc(AXPhotosViewControllerNotification) open class PhotosViewControllerNotification: NSObject {
    static let ProgressUpdate = Notification.Name.photoLoadingProgressUpdate.rawValue
    static let ImageUpdate = Notification.Name.photoImageUpdate.rawValue
    static let ImageKey = "AXPhotosViewControllerImage"
    static let ImageDataKey = "AXPhotosViewControllerImageData"
    static let ReferenceViewKey = "AXPhotosViewControllerReferenceView"
    static let LoadingStateKey = "AXPhotosViewControllerLoadingState"
    static let ProgressKey = "AXPhotosViewControllerProgress"
    static let ErrorKey = "AXPhotosViewControllerError"
}

public extension Notification.Name {
    static let photoLoadingProgressUpdate = Notification.Name("AXPhotoLoadingProgressUpdateNotification")
    static let photoImageUpdate = Notification.Name("AXPhotoImageUpdateNotification")
}
