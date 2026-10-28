import SwiftUI
import UIKit
import WidgetKit

private enum WidgetPalette {
    static let blue = Color(red: 0.08, green: 0.30, blue: 0.51)
    static let card = Color(red: 0.96, green: 0.79, blue: 0.88)
}

private enum WidgetTextWeight {
    case light, medium, bold

    var swiftUI: Font.Weight {
        switch self {
        case .light: .light
        case .medium: .medium
        case .bold: .bold
        }
    }

    var uiKit: UIFont.Weight {
        switch self {
        case .light: .light
        case .medium: .medium
        case .bold: .bold
        }
    }
}

// In Tinted mode iOS recolors SwiftUI Text white. A full-color image of the
// short label preserves black ink on the widget's light-gray controls.
@available(iOS 17.0, *)
private struct WidgetInk: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let text: String
    let size: CGFloat
    let weight: WidgetTextWeight
    var tracking: CGFloat = 0
    var opacity: Double = 1

    var body: some View {
        if renderingMode == .accented {
            if #available(iOS 18.0, *) {
                Image(uiImage: blackTextImage)
                    .widgetAccentedRenderingMode(.fullColor)
                    .accessibilityLabel(text)
            } else {
                normalText
            }
        } else {
            normalText
        }
    }

    private var normalText: some View {
        Text(text)
            .font(.system(size: size, weight: weight.swiftUI, design: .rounded))
            .tracking(tracking)
            .foregroundStyle(WidgetPalette.blue.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var blackTextImage: UIImage {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight.uiKit)
        let font = systemFont.fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: size) } ?? systemFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black.withAlphaComponent(opacity),
            .kern: tracking
        ]
        let label = text as NSString
        let measured = label.size(withAttributes: attributes)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 3
        return UIGraphicsImageRenderer(
            size: CGSize(width: ceil(measured.width) + 2, height: ceil(measured.height) + 2),
            format: format
        ).image { _ in
            label.draw(at: CGPoint(x: 1, y: 1), withAttributes: attributes)
        }
    }
}

@available(iOS 17.0, *)
struct MoodiEntry: TimelineEntry {
    let date: Date
    let start: Int
    let stop: Int
    let pending: Bool
    let state: String
    let message: String

    init(date: Date = .now) {
        self.date = date
        start = SharedSettings.start
        stop = SharedSettings.stop
        pending = SharedSettings.defaults.bool(forKey: SharedSettings.pendingKey)
        state = SharedSettings.defaults.string(forKey: SharedSettings.widgetStateKey) ?? "idle"
        message = SharedSettings.defaults.string(forKey: SharedSettings.widgetMessageKey) ?? ""
    }
}

@available(iOS 17.0, *)
struct MoodiProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodiEntry { MoodiEntry() }
    func getSnapshot(in context: Context, completion: @escaping (MoodiEntry) -> Void) {
        completion(MoodiEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodiEntry>) -> Void) {
        completion(Timeline(entries: [MoodiEntry()], policy: .never))
    }
}

@available(iOS 17.0, *)
private struct ThresholdTile: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let title: String
    let value: Int
    let field: String
    let canDecrease: Bool
    let canIncrease: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetInk(text: title.uppercased(), size: 8, weight: .bold,
                      tracking: 0.6, opacity: 0.75)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                WidgetInk(text: "\(value)", size: 21, weight: .light)
                WidgetInk(text: "BPM", size: 7, weight: .bold)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Button(intent: AdjustThresholdIntent(field: field, delta: -1)) {
                    WidgetInk(text: "−", size: 19, weight: .medium)
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .disabled(!canDecrease)
                .accessibilityLabel("Decrease \(title) threshold")
                Button(intent: AdjustThresholdIntent(field: field, delta: 1)) {
                    WidgetInk(text: "+", size: 19, weight: .medium)
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .disabled(!canIncrease)
                .accessibilityLabel("Increase \(title) threshold")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .leading)
        .background(renderingMode == .accented ? Color.white.opacity(0.83) : WidgetPalette.card,
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

@available(iOS 17.0, *)
private struct MoodiWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: MoodiEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ThresholdTile(title: "Start", value: entry.start, field: "start",
                              canDecrease: entry.start > max(41, entry.stop + 1), canIncrease: entry.start < 220)
                ThresholdTile(title: "Reset", value: entry.stop, field: "stop",
                              canDecrease: entry.stop > 40, canIncrease: entry.stop + 1 < entry.start)
            }
            Button(intent: ConnectMoodiIntent()) {
                HStack(spacing: 6) {
                    if renderingMode == .accented {
                        WidgetInk(text: "●", size: 8, weight: .bold)
                    } else {
                        Circle().fill(entry.pending ? .orange : (entry.state == "ready" ? .green : WidgetPalette.blue.opacity(0.55)))
                            .frame(width: 6, height: 6)
                    }
                    WidgetInk(text: "CONNECT", size: 10, weight: .bold, tracking: 0.7)
                    Spacer(minLength: 0)
                    WidgetInk(text: entry.pending ? "PENDING" : (entry.state == "ready" ? "SYNCED" : ""),
                              size: 7, weight: .bold, opacity: 0.7)
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(renderingMode == .accented ? Color.white.opacity(0.83) : WidgetPalette.card,
                            in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect to CalmPulse. \(entry.message.isEmpty ? (entry.pending ? "Changes pending" : entry.state) : entry.message)")
        }
        .padding(12)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.91, green: 0.67, blue: 0.81),
                                    Color(red: 0.84, green: 0.53, blue: 0.72)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

@available(iOS 17.0, *)
struct MoodiControlsWidget: Widget {
    let kind = "MoodiControlsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodiProvider()) { entry in
            MoodiWidgetView(entry: entry)
        }
        .configurationDisplayName("moodi controls")
        .description("Adjust pulse thresholds and check CalmPulse from your Home Screen.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

@main
@available(iOS 17.0, *)
struct MoodiWidgetBundle: WidgetBundle {
    var body: some Widget { MoodiControlsWidget() }
}
