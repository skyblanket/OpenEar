import SwiftUI
import AppKit

// MARK: - Notch Specifications

enum NotchSpecs {
    // Compact (behind notch)
    static let compactWidth: CGFloat = 150
    static let compactHeight: CGFloat = 28

    // Expanded - fits content snugly
    static let expandedWidth: CGFloat = 210
    static let expandedHeight: CGFloat = 68

    static let cornerRadius: CGFloat = 16
}

/// Observable state for the Dynamic Island
class DynamicIslandState: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var isExpanded: Bool = false
}

/// Dynamic Island that grows down from the MacBook notch
@MainActor
class RecordingOverlayController {
    static let shared = RecordingOverlayController()

    private var overlayWindow: NSWindow?
    private weak var appState: AppState?
    private let islandState = DynamicIslandState()
    private var hideWorkItem: DispatchWorkItem?

    func setup(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard let appState = appState else {
            print("OpenEar: show() - no appState")
            return
        }

        print("OpenEar: show() called")

        // Cancel any pending hide immediately
        hideWorkItem?.cancel()
        hideWorkItem = nil

        // If window exists and is on screen, just ensure it's expanded
        if let window = overlayWindow, window.isVisible {
            window.alphaValue = 1
            islandState.isExpanded = true
            print("OpenEar: show() - reusing window")
            return
        }

        // Clean up any stale window
        overlayWindow?.orderOut(nil)
        overlayWindow = nil

        print("OpenEar: show() - creating window")

        // Fresh state
        islandState.isVisible = true
        islandState.isExpanded = false

        let islandView = NotchDynamicIsland()
            .environmentObject(appState)
            .environmentObject(islandState)

        let hosting = NSHostingView(rootView: AnyView(islandView))
        hosting.wantsLayer = true

        let windowWidth: CGFloat = 260
        let windowHeight: CGFloat = 85

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.hasShadow = false
        window.contentView = hosting
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.alphaValue = 1

        if let screen = NSScreen.main {
            let x = screen.frame.midX - (windowWidth / 2)
            let y = screen.frame.maxY - windowHeight
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFrontRegardless()
        self.overlayWindow = window

        // Small delay to let view render, then animate expand
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.islandState.isExpanded = true
            print("OpenEar: show() - expanded")
        }
    }

    func hide() {
        print("OpenEar: hide() called")
        guard let window = overlayWindow else {
            print("OpenEar: hide() - no window")
            return
        }

        // Cancel any previous hide
        hideWorkItem?.cancel()

        // Collapse content
        islandState.isExpanded = false

        // Fade out window after collapse
        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor [weak self] in
                    self?.islandState.isVisible = false
                    self?.overlayWindow?.orderOut(nil)
                    self?.overlayWindow?.alphaValue = 1
                    self?.overlayWindow = nil
                    print("OpenEar: hide() - window removed")
                }
            }
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}

// MARK: - Custom Shape: MacBook Notch Style (With Shoulder Curves)

struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cr = min(cornerRadius, rect.height / 2, rect.width / 2)

        // Shoulder curve radius (the "ears" that blend into top edge)
        let shoulderR: CGFloat = 8

        // Start at far left of top edge (outside main rect for shoulder)
        path.move(to: CGPoint(x: rect.minX - shoulderR, y: rect.minY))

        // Left shoulder curve (curves down and inward)
        path.addArc(
            center: CGPoint(x: rect.minX - shoulderR, y: rect.minY + shoulderR),
            radius: shoulderR,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Left side down to bottom corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cr))

        // Bottom-left rounded corner
        path.addArc(
            center: CGPoint(x: rect.minX + cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - cr, y: rect.maxY))

        // Bottom-right rounded corner
        path.addArc(
            center: CGPoint(x: rect.maxX - cr, y: rect.maxY - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )

        // Right side up
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + shoulderR))

        // Right shoulder curve (curves up and outward)
        path.addArc(
            center: CGPoint(x: rect.maxX + shoulderR, y: rect.minY + shoulderR),
            radius: shoulderR,
            startAngle: .degrees(180),
            endAngle: .degrees(-90),
            clockwise: false
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX - shoulderR, y: rect.minY))

        path.closeSubpath()

        return path
    }
}

// MARK: - Notch Dynamic Island View

struct NotchDynamicIsland: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var islandState: DynamicIslandState

    @State private var width: CGFloat = NotchSpecs.compactWidth
    @State private var height: CGFloat = NotchSpecs.compactHeight
    @State private var contentOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Black island container - content is INSIDE the shape
            NotchShape(cornerRadius: NotchSpecs.cornerRadius)
                .fill(Color.black)
                .frame(width: width, height: height)
                .overlay(alignment: .bottom) {
                    // Content pinned to bottom, inside the black shape
                    contentView
                        .opacity(contentOpacity)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                .clipShape(NotchShape(cornerRadius: NotchSpecs.cornerRadius))
                .frame(width: 260, height: 85, alignment: .top)

            Spacer(minLength: 0)
        }
        .onChange(of: islandState.isExpanded) { _, expanded in
            if expanded {
                // Smooth expand
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    width = NotchSpecs.expandedWidth
                    height = NotchSpecs.expandedHeight
                }
                withAnimation(.easeOut(duration: 0.2).delay(0.15)) {
                    contentOpacity = 1
                }
            } else {
                // Graceful collapse - content fades, then shape shrinks
                withAnimation(.easeOut(duration: 0.15)) {
                    contentOpacity = 0
                }
                withAnimation(.easeInOut(duration: 0.25).delay(0.1)) {
                    width = NotchSpecs.compactWidth
                    height = NotchSpecs.compactHeight
                }
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        HStack(spacing: 8) {
            // Glowing breathing dot
            NotchWaveform(level: appState.audioLevel)
                .frame(width: 22, height: 22)

            // 3D wheel scrolling text
            ScrollingTranscriptionText(
                text: appState.partialTranscription,
                placeholder: "Listening..."
            )
        }
        .frame(height: 24)
    }
}

// MARK: - 3D Wheel Scrolling Text (French Design)

struct ScrollingTranscriptionText: View {
    let text: String
    let placeholder: String

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var showText: Bool = false
    @State private var rotationAngle: Double = 0
    @State private var yOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Shimmer placeholder
                if text.isEmpty {
                    ShimmerText(text: placeholder)
                }

                // 3D wheel scrolling text
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize()
                        .background(
                            GeometryReader { textGeo in
                                Color.clear
                                    .onAppear { textWidth = textGeo.size.width }
                                    .onChange(of: text) { _, _ in
                                        DispatchQueue.main.async {
                                            textWidth = textGeo.size.width
                                        }
                                    }
                            }
                        )
                        .offset(x: scrollOffset, y: yOffset)
                        // 3D wheel rotation - like a slot machine / lyrics wheel
                        .rotation3DEffect(
                            .degrees(rotationAngle),
                            axis: (x: 1, y: 0, z: 0),
                            anchor: .center,
                            perspective: 0.8
                        )
                        .opacity(showText ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, new in containerWidth = new }
            .onChange(of: text) { old, new in
                if old.isEmpty && !new.isEmpty {
                    // First text - gentle wheel in
                    showText = true
                    scrollOffset = 0
                    rotationAngle = -25
                    yOffset = 5
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        rotationAngle = 0
                        yOffset = 0
                    }
                } else if !new.isEmpty {
                    // Text updating - subtle wheel tick
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        rotationAngle = -8
                        yOffset = 2
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            rotationAngle = 0
                            yOffset = 0
                        }
                    }

                    // Smooth scroll to latest - slower
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let overflow = textWidth - containerWidth
                        if overflow > 0 {
                            withAnimation(.easeInOut(duration: 2.8)) {
                                scrollOffset = -overflow - 4
                            }
                        }
                    }
                } else {
                    // Text cleared - gentle wheel out
                    withAnimation(.easeOut(duration: 0.3)) {
                        rotationAngle = 18
                        yOffset = -4
                        showText = false
                        scrollOffset = 0
                    }
                }
            }
        }
        // Dynamic mask - left fade only appears when scrolling
        .mask(
            HStack(spacing: 0) {
                // Left fade - only when text has scrolled
                if scrollOffset < -10 {
                    LinearGradient(
                        colors: [.clear, .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 10)
                }

                // Main visible area
                Rectangle().fill(.white)

                // Right fade
                LinearGradient(
                    colors: [.white, .white.opacity(0.3), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
            }
            .animation(.easeInOut(duration: 0.25), value: scrollOffset < -10)
        )
    }
}

// MARK: - Shimmer Text (Thinking Effect)

struct ShimmerText: View {
    let text: String
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.35))
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.4),
                            .white.opacity(0.6),
                            .white.opacity(0.4),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: shimmerOffset * geo.size.width * 1.5)
                    .mask(
                        Text(text)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                    )
                }
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.8)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 1
                }
            }
    }
}

// MARK: - Glowing Breathing Dot (Recording Indicator)

struct NotchWaveform: View {
    let level: Float

    @State private var displayLevel: Float = 0
    @State private var breathe: CGFloat = 0
    private let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Outer glow - more visible
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .red.opacity(0.8 * Double(displayLevel + 0.4)),
                            .red.opacity(0.4 * Double(displayLevel + 0.2)),
                            .red.opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 10 + CGFloat(displayLevel) * 6
                    )
                )
                .frame(width: 20, height: 20)
                .scaleEffect(1 + breathe * 0.15 + CGFloat(displayLevel) * 0.3)

            // Inner bright glow
            Circle()
                .fill(.red.opacity(0.5 + Double(displayLevel) * 0.3))
                .frame(width: 8, height: 8)
                .blur(radius: 2)

            // Core dot - bright
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.3), .red, .red],
                        center: .center,
                        startRadius: 0,
                        endRadius: 3
                    )
                )
                .frame(width: 5, height: 5)
                .shadow(color: .red.opacity(0.8), radius: 3)
        }
        .onReceive(timer) { _ in
            let target = level
            if target > displayLevel {
                displayLevel = displayLevel + (target - displayLevel) * 0.7
            } else {
                displayLevel = displayLevel + (target - displayLevel) * 0.15
            }
            breathe = CGFloat(sin(Date().timeIntervalSinceReferenceDate * 2.5) * 0.5 + 0.5)
        }
        .animation(.easeOut(duration: 0.08), value: displayLevel)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.4)

        VStack(spacing: 0) {
            Rectangle().fill(Color.black).frame(height: 38)
            Spacer()
        }

        VStack(spacing: 0) {
            NotchDynamicIsland()
                .environmentObject({
                    let s = AppState()
                    s.partialTranscription = "Hello world"
                    return s
                }())
                .environmentObject({
                    let s = DynamicIslandState()
                    s.isVisible = true
                    s.isExpanded = true
                    return s
                }())
            Spacer()
        }
    }
    .frame(width: 400, height: 300)
}
