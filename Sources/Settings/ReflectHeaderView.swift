import UIKit

/// Reflect: the stats card from the desktop client, computed from local
/// history so nothing extra is sent to a server.
final class ReflectHeaderView: UIView {
    private let rangeButton = UIButton(type: .system)
    private let summaryLabel = UILabel()
    private let statsRow = UIStackView()
    private let sectionLabel = UILabel()
    private let segmented = UISegmentedControl(items: ["Conversations", "Time spent"])
    private let chart = LineChartView()
    private let rangeLabel = UILabel()

    private var days = 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        backgroundColor = Theme.background

        rangeButton.setTitle("Past month  \u{25BE}", for: .normal)
        rangeButton.setTitleColor(Theme.textSecondary, for: .normal)
        rangeButton.titleLabel?.font = AppSettings.shared.chatFont.font(size: 13)
        rangeButton.backgroundColor = Theme.surfaceRaised
        rangeButton.layer.cornerRadius = 14
        rangeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        rangeButton.translatesAutoresizingMaskIntoConstraints = false
        rangeButton.addTarget(self, action: #selector(cycleRange), for: .touchUpInside)
        addSubview(rangeButton)

        summaryLabel.numberOfLines = 0
        summaryLabel.textColor = Theme.textPrimary
        summaryLabel.font = AppSettings.shared.chatFont.font(size: 15)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(summaryLabel)

        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = 10
        statsRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statsRow)

        sectionLabel.text = "YOUR TIME WITH NOTION AI"
        sectionLabel.textColor = Theme.textTertiary
        sectionLabel.font = AppSettings.shared.chatFont.font(size: 11, weight: .semibold)
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionLabel)

        segmented.selectedSegmentIndex = 0
        segmented.tintColor = Theme.accent
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.addTarget(self, action: #selector(reload), for: .valueChanged)
        addSubview(segmented)

        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        rangeLabel.textColor = Theme.textTertiary
        rangeLabel.font = AppSettings.shared.chatFont.font(size: 11)
        rangeLabel.textAlignment = .center
        rangeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rangeLabel)

        NSLayoutConstraint.activate([
            rangeButton.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            rangeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),

            summaryLabel.topAnchor.constraint(equalTo: rangeButton.bottomAnchor, constant: 12),
            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            statsRow.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 14),
            statsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            statsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            statsRow.heightAnchor.constraint(equalToConstant: 58),

            sectionLabel.topAnchor.constraint(equalTo: statsRow.bottomAnchor, constant: 18),
            sectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),

            segmented.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 8),
            segmented.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            segmented.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            chart.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            chart.heightAnchor.constraint(equalToConstant: 96),

            rangeLabel.topAnchor.constraint(equalTo: chart.bottomAnchor, constant: 6),
            rangeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            rangeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
        ])
    }

    @objc private func cycleRange() {
        switch days {
        case 7: days = 30
        case 30: days = 90
        default: days = 7
        }

        let title: String
        switch days {
        case 7: title = "Past week"
        case 30: title = "Past month"
        default: title = "Past quarter"
        }
        rangeButton.setTitle(title + "  \u{25BE}", for: .normal)
        reload()
    }

    @objc func reload() {
        let series = ConversationStore.shared.dailyCounts(days: days)
        let conversations = ConversationStore.shared.conversations
        let calendar = Calendar.current

        let showTime = segmented.selectedSegmentIndex == 1
        let values: [CGFloat] = series.map { entry in
            guard showTime else { return CGFloat(entry.count) }

            // Rough estimate: half a minute of attention per message.
            let minutes = conversations
                .filter { calendar.isDate($0.createdAt, inSameDayAs: entry.date) }
                .reduce(0) { $0 + $1.messages.count }
            return CGFloat(minutes) * 0.5
        }
        chart.values = values

        let total = conversations.count
        let weekdayCounts = Dictionary(grouping: conversations) { conversation in
            calendar.component(.weekday, from: conversation.createdAt)
        }.mapValues { $0.count }
        let hourCounts = Dictionary(grouping: conversations) { conversation in
            calendar.component(.hour, from: conversation.createdAt)
        }.mapValues { $0.count }

        let busiestWeekday = weekdayCounts.max { $0.value < $1.value }?.key
        let busiestHour = hourCounts.max { $0.value < $1.value }?.key

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let weekdayName = busiestWeekday.map { index -> String in
            let symbols = formatter.weekdaySymbols ?? []
            return index - 1 < symbols.count ? symbols[index - 1] : "--"
        } ?? "--"

        let hourName = busiestHour.map { hour -> String in
            let suffix = hour < 12 ? "AM" : "PM"
            let display = hour % 12 == 0 ? 12 : hour % 12
            return String(display) + " " + suffix
        } ?? "--"

        statsRow.arrangedSubviews.forEach { view in
            statsRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        statsRow.addArrangedSubview(ReflectHeaderView.statCard(value: weekdayName, caption: "MOST ACTIVE DAY"))
        statsRow.addArrangedSubview(ReflectHeaderView.statCard(value: hourName, caption: "PEAK HOUR"))
        statsRow.addArrangedSubview(ReflectHeaderView.statCard(value: String(total), caption: "TOTAL CONVERSATIONS"))

        let messageCount = conversations.reduce(0) { $0 + $1.messages.count }
        summaryLabel.text = total == 0
            ? "No chats yet. Once you start talking to Notion AI, your rhythm shows up here."
            : "You had " + String(total) + " conversations and exchanged " + String(messageCount)
                + " messages. Your rhythm peaks around " + hourName + " on " + weekdayName + "."

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d yyyy"
        if let first = series.first?.date, let last = series.last?.date {
            rangeLabel.text = dateFormatter.string(from: first) + "  \u{2013}  " + dateFormatter.string(from: last)
        }
    }

    private static func statCard(value: String, caption: String) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 12

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.textColor = Theme.textPrimary
        valueLabel.font = AppSettings.shared.chatFont.font(size: 16, weight: .semibold)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(valueLabel)

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.textColor = Theme.textTertiary
        captionLabel.font = AppSettings.shared.chatFont.font(size: 9, weight: .semibold)
        captionLabel.numberOfLines = 2
        captionLabel.textAlignment = .center
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(captionLabel)

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),

            captionLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            captionLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            captionLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6)
        ])

        return card
    }
}

/// Minimal line chart so the app needs no charting dependency on iOS 14.
final class LineChartView: UIView {
    var values: [CGFloat] = [] { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.surface
        layer.cornerRadius = 12
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = Theme.surface
        layer.cornerRadius = 12
    }

    override func draw(_ rect: CGRect) {
        guard values.count > 1 else { return }

        let inset: CGFloat = 12
        let plot = rect.insetBy(dx: inset, dy: inset)
        let maximum = max(values.max() ?? 1, 1)

        Theme.border.withAlphaComponent(0.6).setStroke()
        let baseline = UIBezierPath()
        baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        baseline.lineWidth = 1
        baseline.stroke()

        let step = plot.width / CGFloat(values.count - 1)
        let line = UIBezierPath()

        for (index, value) in values.enumerated() {
            let x = plot.minX + CGFloat(index) * step
            let y = plot.maxY - (value / maximum) * plot.height
            let point = CGPoint(x: x, y: y)
            index == 0 ? line.move(to: point) : line.addLine(to: point)
        }

        let fill = line.copy() as! UIBezierPath
        fill.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        fill.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
        fill.close()
        Theme.accentMuted.setFill()
        fill.fill()

        Theme.accent.setStroke()
        line.lineWidth = 2
        line.lineJoinStyle = .round
        line.stroke()
    }
}
