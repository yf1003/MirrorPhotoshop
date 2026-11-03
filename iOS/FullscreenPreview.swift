import SwiftUI
import UIKit

struct FullscreenPreview: UIViewControllerRepresentable {
    var image: UIImage?
    var frame: MirrorFrame?
    var status: String
    var onClose: () -> Void
    var onLibrary: () -> Void
    func makeUIViewController(context: Context) -> PreviewController {
        let controller = PreviewController()
        controller.onClose = onClose; controller.onLibrary = onLibrary
        return controller
    }
    func updateUIViewController(_ controller: PreviewController, context: Context) {
        controller.update(image: image, frame: frame, status: status)
    }
}

final class PreviewController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onClose: (() -> Void)?
    var onLibrary: (() -> Void)?
    private let scroll = UIScrollView()
    private let imageView = UIImageView()
    private let toolbar = UIStackView()
    private let titleLabel = UILabel()
    private let hint = UILabel()
    private var frame: MirrorFrame?
    private var version: String?
    private var fitMode = 0
    private var lastSize = CGSize.zero
    private var hideWork: DispatchWorkItem?
    private var controlsHidden = false

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { controlsHidden }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scroll.delegate = self; scroll.backgroundColor = .clear
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true; scroll.maximumZoomScale = 12
        scroll.addSubview(imageView); view.addSubview(scroll)
        imageView.contentMode = .scaleToFill
        let single = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        double.numberOfTapsRequired = 2; single.require(toFail: double)
        single.delegate = self; double.delegate = self
        view.addGestureRecognizer(single); view.addGestureRecognizer(double)
        toolbar.axis = .horizontal; toolbar.spacing = 12; toolbar.alignment = .center
        toolbar.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        toolbar.layer.cornerRadius = 22; toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        toolbar.addArrangedSubview(button("xmark", action: #selector(close)))
        toolbar.addArrangedSubview(button("square.stack", action: #selector(library)))
        toolbar.addArrangedSubview(button("arrow.down.right.and.arrow.up.left", action: #selector(fit)))
        toolbar.addArrangedSubview(button("arrow.up.left.and.arrow.down.right", action: #selector(fill)))
        let actual = UIButton(type: .system)
        actual.setTitle("1:1", for: .normal); actual.tintColor = .white
        actual.titleLabel?.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        actual.addTarget(self, action: #selector(actualSize), for: .touchUpInside)
        toolbar.addArrangedSubview(actual)
        toolbar.addArrangedSubview(button("circle.lefthalf.filled", action: #selector(background)))
        toolbar.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(toolbar)
        titleLabel.textColor = .white; titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.numberOfLines = 2; titleLabel.textAlignment = .center
        titleLabel.backgroundColor = UIColor(white: 0, alpha: 0.6)
        titleLabel.layer.cornerRadius = 8; titleLabel.clipsToBounds = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(titleLabel)
        hint.text = "轻点隐藏工具栏 · 双击缩放 · 双指自由缩放"
        hint.textColor = .lightGray; hint.font = .systemFont(ofSize: 11); hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(hint)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            toolbar.heightAnchor.constraint(equalToConstant: 48),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            hint.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -10),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        UIApplication.shared.isIdleTimerDisabled = true
        scheduleHide()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        if lastSize != view.bounds.size {
            lastSize = view.bounds.size
            applyMode()
        }
        centerImage()
    }
    func update(image: UIImage?, frame: MirrorFrame?, status: String) {
        loadViewIfNeeded()
        let sameID = self.frame?.id == frame?.id
        self.frame = frame
        titleLabel.text = "  \(frame?.title ?? "等待画面")  \n  \(status)  "
        let newVersion = frame.map { $0.id + $0.version }
        guard newVersion != version, let image else { return }
        let sameDocument = sameID && version != nil && imageView.image?.size == image.size
        let oldScale = scroll.zoomScale
        let oldOffset = scroll.contentOffset
        version = newVersion
        scroll.setZoomScale(1, animated: false)
        imageView.image = image; imageView.frame = CGRect(origin: .zero, size: image.size)
        scroll.contentSize = image.size
        updateLimits()
        if sameDocument {
            scroll.setZoomScale(min(scroll.maximumZoomScale, max(scroll.minimumZoomScale, oldScale)), animated: false)
            scroll.contentOffset = oldOffset
        } else { applyMode() }
        centerImage()
    }
    private func updateLimits() {
        guard let image = imageView.image else { return }
        let scale = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
        scroll.minimumZoomScale = max(0.001, scale)
        scroll.maximumZoomScale = max(12, scale * 8)
    }
    private func applyMode() {
        guard let image = imageView.image, scroll.bounds.width > 0 else { return }
        updateLimits()
        let fit = min(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
        let fill = max(scroll.bounds.width / image.size.width, scroll.bounds.height / image.size.height)
        // 1 source PSD pixel per physical screen pixel, even when transport is downsampled.
        let actual = CGFloat(frame?.width ?? Int(image.size.width)) / image.size.width / (view.window?.screen.scale ?? 3)
        let scale = fitMode == 0 ? fit : (fitMode == 1 ? fill : actual)
        scroll.setZoomScale(max(scroll.minimumZoomScale, min(scroll.maximumZoomScale, scale)), animated: false)
        centerImage()
        scroll.contentOffset = CGPoint(x: max(0, (scroll.contentSize.width - scroll.bounds.width) / 2),
                                       y: max(0, (scroll.contentSize.height - scroll.bounds.height) / 2))
    }
    private func centerImage() {
        var rect = imageView.frame
        rect.origin = CGPoint(x: max(0, (scroll.bounds.width - rect.width) / 2), y: max(0, (scroll.bounds.height - rect.height) / 2))
        imageView.frame = rect
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view?.isDescendant(of: toolbar) ?? false)
    }
    private func button(_ icon: String, action: Selector) -> UIButton {
        let result = UIButton(type: .system)
        result.setImage(UIImage(systemName: icon), for: .normal); result.tintColor = .white
        result.addTarget(self, action: action, for: .touchUpInside)
        result.widthAnchor.constraint(equalToConstant: 30).isActive = true
        result.accessibilityLabel = ["xmark": "返回", "square.stack": "PSD 列表", "arrow.down.right.and.arrow.up.left": "适应屏幕", "arrow.up.left.and.arrow.down.right": "铺满屏幕", "circle.lefthalf.filled": "切换背景"][icon]
        return result
    }
    @objc private func close() { hideWork?.cancel(); onClose?() }
    @objc private func library() { showControls(); onLibrary?() }
    @objc private func fit() { fitMode = 0; applyMode(); scheduleHide() }
    @objc private func fill() { fitMode = 1; applyMode(); scheduleHide() }
    @objc private func actualSize() { fitMode = 2; applyMode(); scheduleHide() }
    @objc private func background() { view.backgroundColor = view.backgroundColor == .black ? .white : .black; scheduleHide() }
    @objc private func toggleControls() { controlsHidden ? showControls() : hideControls() }
    @objc private func doubleTap(_ sender: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }
        if scroll.zoomScale > scroll.minimumZoomScale * 1.05 { fitMode = 0; applyMode() }
        else {
            let point = sender.location(in: imageView)
            let scale = min(scroll.maximumZoomScale, max(scroll.minimumZoomScale * 2.5, 1))
            let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
            scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
    private func showControls() {
        controlsHidden = false; toolbar.alpha = 1; titleLabel.alpha = 1; hint.alpha = 1
        setNeedsUpdateOfHomeIndicatorAutoHidden(); scheduleHide()
    }
    private func hideControls() {
        controlsHidden = true
        UIView.animate(withDuration: 0.2) { self.toolbar.alpha = 0; self.titleLabel.alpha = 0; self.hint.alpha = 0 }
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideControls() }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
