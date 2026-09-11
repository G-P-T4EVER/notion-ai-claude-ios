import UIKit

/// The Claude starburst, drawn with Core Graphics so the app ships no bitmaps.
final class StarburstView: UIView {
    var rayCount: Int = 11 { didSet { setNeedsDisplay() } }
    var color: UIColor = Theme.accent { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.14
        let spread = (CGFloat.pi / CGFloat(max(rayCount, 1))) * 0.40

        color.setFill()

        for index in 0..<max(rayCount, 1) {
            let angle = (CGFloat(index) / CGFloat(rayCount)) * 2 * CGFloat.pi - CGFloat.pi / 2

            let tip = CGPoint(
                x: center.x + cos(angle) * outer,
                y: center.y + sin(angle) * outer
            )
            let left = CGPoint(
                x: center.x + cos(angle - spread) * inner,
                y: center.y + sin(angle - spread) * inner
            )
            let right = CGPoint(
                x: center.x + cos(angle + spread) * inner,
                y: center.y + sin(angle + spread) * inner
            )

            let path = UIBezierPath()
            path.move(to: tip)
            path.addQuadCurve(to: left, controlPoint: center)
            path.addLine(to: right)
            path.addQuadCurve(to: tip, controlPoint: center)
            path.close()
            path.fill()
        }
    }

    func startSpinning() {
        guard !AppSettings.shared.motionReduced else { return }
        guard layer.animation(forKey: "spin") == nil else { return }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = 3.2
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        layer.add(spin, forKey: "spin")
    }

    func stopSpinning() {
        layer.removeAnimation(forKey: "spin")
    }
}
