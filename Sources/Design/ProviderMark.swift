import UIKit

/// Small vector marks for each model provider, drawn in code so the app needs
/// no bundled third-party logo files.
enum ProviderMark {
    static func color(for provider: ModelProvider) -> UIColor {
        switch provider {
        case .anthropic: return UIColor(hex: 0xD97757)
        case .openai: return UIColor(hex: 0xE8E6DF)
        case .google: return UIColor(hex: 0x6C93F5)
        case .xai: return UIColor(hex: 0xE8E6DF)
        case .moonshot: return UIColor(hex: 0x8E7BF0)
        case .auto: return UIColor(hex: 0xD97757)
        }
    }

    static func image(for provider: ModelProvider, size: CGFloat = 18) -> UIImage {
        let bounds = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: bounds)
        return renderer.image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: bounds)
            let tint = color(for: provider)
            tint.setFill()
            tint.setStroke()

            switch provider {
            case .anthropic, .auto:
                drawStarburst(in: rect, ctx: ctx, rays: provider == .auto ? 4 : 11)
            case .openai:
                drawKnot(in: rect, ctx: ctx)
            case .google:
                drawSpark(in: rect, ctx: ctx)
            case .xai:
                drawX(in: rect, ctx: ctx)
            case .moonshot:
                drawMoon(in: rect, ctx: ctx)
            }
        }
    }

    private static func drawStarburst(in rect: CGRect, ctx: CGContext, rays: Int) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width * 0.46
        let innerWidth = rect.width * 0.085
        let path = UIBezierPath()

        for index in 0..<rays {
            let angle = (CGFloat(index) / CGFloat(rays)) * .pi * 2 - .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
            let left = CGPoint(
                x: center.x + cos(angle - .pi / 2) * innerWidth,
                y: center.y + sin(angle - .pi / 2) * innerWidth
            )
            let right = CGPoint(
                x: center.x + cos(angle + .pi / 2) * innerWidth,
                y: center.y + sin(angle + .pi / 2) * innerWidth
            )
            path.move(to: left)
            path.addLine(to: tip)
            path.addLine(to: right)
            path.close()
        }
        path.fill()
    }

    private static func drawKnot(in rect: CGRect, ctx: CGContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.3
        let petal = rect.width * 0.2
        ctx.setLineWidth(max(1, rect.width * 0.09))
        ctx.setLineCap(.round)

        for index in 0..<6 {
            let angle = (CGFloat(index) / 6) * .pi * 2 - .pi / 2
            let origin = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let circle = UIBezierPath(
                arcCenter: origin,
                radius: petal,
                startAngle: angle - 1.25,
                endAngle: angle + 1.25,
                clockwise: true
            )
            circle.lineWidth = max(1, rect.width * 0.09)
            circle.lineCapStyle = .round
            circle.stroke()
        }
    }

    private static func drawSpark(in rect: CGRect, ctx: CGContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let long = rect.width * 0.48
        let short = rect.width * 0.15
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - long))
        path.addQuadCurve(
            to: CGPoint(x: center.x + long, y: center.y),
            controlPoint: CGPoint(x: center.x + short, y: center.y - short)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + long),
            controlPoint: CGPoint(x: center.x + short, y: center.y + short)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x - long, y: center.y),
            controlPoint: CGPoint(x: center.x - short, y: center.y + short)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - long),
            controlPoint: CGPoint(x: center.x - short, y: center.y - short)
        )
        path.close()
        path.fill()
    }

    private static func drawX(in rect: CGRect, ctx: CGContext) {
        let inset = rect.insetBy(dx: rect.width * 0.2, dy: rect.width * 0.2)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: inset.minX, y: inset.minY))
        path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        path.move(to: CGPoint(x: inset.maxX, y: inset.minY))
        path.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
        path.lineWidth = max(1.2, rect.width * 0.12)
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func drawMoon(in rect: CGRect, ctx: CGContext) {
        let full = UIBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.12, dy: rect.width * 0.12))
        let bite = UIBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.12, dy: rect.width * 0.12)
            .offsetBy(dx: rect.width * 0.24, dy: -rect.width * 0.06))
        ctx.saveGState()
        full.append(bite.reversing())
        full.fill()
        ctx.restoreGState()
    }
}

/// The large app mark shown above the greeting on the empty chat screen.
final class BrandMarkView: UIView {
    private let rays: Int

    init(rays: Int = 11) {
        self.rays = rays
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.5
        let innerWidth = outer * 0.19
        let path = UIBezierPath()

        for index in 0..<rays {
            let angle = (CGFloat(index) / CGFloat(rays)) * .pi * 2 - .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer)
            let left = CGPoint(
                x: center.x + cos(angle - .pi / 2) * innerWidth,
                y: center.y + sin(angle - .pi / 2) * innerWidth
            )
            let right = CGPoint(
                x: center.x + cos(angle + .pi / 2) * innerWidth,
                y: center.y + sin(angle + .pi / 2) * innerWidth
            )
            path.move(to: left)
            path.addQuadCurve(to: tip, controlPoint: CGPoint(
                x: (left.x + tip.x) / 2 + cos(angle - .pi / 2) * innerWidth * 0.35,
                y: (left.y + tip.y) / 2 + sin(angle - .pi / 2) * innerWidth * 0.35
            ))
            path.addQuadCurve(to: right, controlPoint: CGPoint(
                x: (right.x + tip.x) / 2 + cos(angle + .pi / 2) * innerWidth * 0.35,
                y: (right.y + tip.y) / 2 + sin(angle + .pi / 2) * innerWidth * 0.35
            ))
            path.close()
        }

        Theme.accent.setFill()
        path.fill()
    }

    func pulse() {
        guard !AppSettings.shared.motionReduced else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.86
        animation.toValue = 1.0
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "pulse")
    }
}
