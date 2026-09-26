import Photos
import SwiftUI

/// Full-screen Tinder-style deck: swipe right to add to Wallpapers, left to skip.
struct SwipeDeckView: View {
    @EnvironmentObject private var deck: DeckModel
    @Environment(\.displayScale) private var displayScale

    @State private var drag: CGSize = .zero
    @State private var isAnimating = false
    @State private var showChrome = true
    @State private var showGrid = false
    @State private var showSettings = false
    @State private var screenWidth: CGFloat = 400

    var body: some View {
        ZStack {
            GeometryReader { geo in
                cardStack(size: geo.size)
                    .onAppear { updateSize(geo.size) }
                    .onChange(of: geo.size) { _, newSize in updateSize(newSize) }
            }
            .ignoresSafeArea()

            if showChrome {
                chrome.transition(.opacity)
            }
        }
        .background(Color.black)
        .statusBarHidden(!showChrome)
        .task {
            if !deck.hasStarted { deck.start() }
        }
        .sheet(isPresented: $showGrid) {
            AcceptedGridView().environmentObject(deck)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(deck)
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deck.errorMessage ?? "")
        }
    }

    // MARK: Cards

    private func cardStack(size: CGSize) -> some View {
        ZStack {
            Color.black
            if deck.cards.isEmpty {
                emptyState
            } else {
                // Top two cards, bottom one first. Identity follows the card, so the next card
                // keeps its loaded image when it becomes the top one.
                let visible = Array(deck.cards.prefix(2).enumerated().reversed())
                ForEach(visible, id: \.element.id) { index, card in
                    cardView(card, isTop: index == 0, size: size)
                }
            }
        }
    }

    private func cardView(_ card: Candidate, isTop: Bool, size: CGSize) -> some View {
        PhotoCardView(asset: card.asset, size: size)
            .overlay {
                if isTop { decisionOverlay(width: size.width) }
            }
            .offset(isTop ? CGSize(width: drag.width, height: drag.height * 0.4) : .zero)
            .rotationEffect(.degrees(isTop ? Double(drag.width / max(size.width, 1)) * 10 : 0), anchor: .bottom)
            .allowsHitTesting(isTop)
            .accessibilityIdentifier(isTop ? "photoCard" : "nextPhotoCard")
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
            }
            .gesture(dragGesture(for: card, width: size.width))
    }

    @ViewBuilder
    private func decisionOverlay(width: CGFloat) -> some View {
        if drag.width != 0 {
            let progress = min(abs(drag.width) / (width * 0.3), 1)
            let accepting = drag.width > 0
            let tint: Color = accepting ? .green : .red
            ZStack(alignment: accepting ? .topLeading : .topTrailing) {
                tint.opacity(0.25 * progress)
                Text(accepting ? "WALLPAPER" : "SKIP")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint, lineWidth: 4))
                    .rotationEffect(.degrees(accepting ? -15 : 15))
                    .padding(.top, 140)
                    .padding(.horizontal, 36)
                    .opacity(progress)
            }
            .allowsHitTesting(false)
        }
    }

    private func dragGesture(for card: Candidate, width: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimating else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isAnimating else { return }
                let threshold = width * 0.3
                let predicted = value.predictedEndTranslation.width
                if value.translation.width > threshold || predicted > width * 0.8 {
                    swipe(card, accept: true)
                } else if value.translation.width < -threshold || predicted < -width * 0.8 {
                    swipe(card, accept: false)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = .zero }
                }
            }
    }

    private func swipe(_ card: Candidate, accept: Bool) {
        guard !isAnimating else { return }
        isAnimating = true
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: (accept ? 1 : -1) * screenWidth * 1.5, height: drag.height)
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if accept { deck.accept(card) } else { deck.reject(card) }
                drag = .zero
            }
            isAnimating = false
        }
    }

    private func undo() {
        guard !isAnimating else { return }
        var undone: DeckModel.Decision?
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            undone = deck.undo()
            if let undone {
                // Place the card off-screen on the side it left from, then slide it back in.
                drag = CGSize(width: (undone.isAccept ? 1 : -1) * screenWidth * 1.5, height: 0)
            }
        }
        guard undone != nil else { return }
        isAnimating = true
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                drag = .zero
            } completion: {
                isAnimating = false
            }
        }
    }

    private func updateSize(_ size: CGSize) {
        screenWidth = size.width
        deck.setCardPixelSize(CGSize(width: size.width * displayScale, height: size.height * displayScale))
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            HStack(spacing: 10) {
                statsChip
                Spacer()
                chromeButton("arrow.uturn.backward", label: "Undo", id: "undoButton", disabled: !deck.canUndo || isAnimating) { undo() }
                chromeButton("square.grid.2x2", label: "Wallpapers album", id: "gridButton") { showGrid = true }
                chromeButton("gearshape", label: "Settings", id: "settingsButton") { showSettings = true }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Spacer()

            if let top = deck.cards.first {
                HStack(spacing: 56) {
                    decisionButton("xmark", label: "Skip", id: "rejectButton", tint: .red) { swipe(top, accept: false) }
                    decisionButton("heart.fill", label: "Add to Wallpapers", id: "acceptButton", tint: .green) { swipe(top, accept: true) }
                }
                .padding(.bottom, 24)
                .disabled(isAnimating)
            }
        }
    }

    private var statsChip: some View {
        HStack(spacing: 12) {
            stat("heart.fill", "\(deck.acceptedCount)", .green)
            stat("xmark", "\(deck.rejectedCount)", .red)
            stat("magnifyingglass", "\(deck.scannedCount)/\(deck.totalCount)", .white.opacity(0.8))
        }
        .font(.footnote.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("stats")
        .accessibilityLabel("\(deck.acceptedCount) added, \(deck.rejectedCount) skipped, \(deck.scannedCount) of \(deck.totalCount) checked")
    }

    private func stat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).foregroundStyle(.white)
        }
    }

    private func chromeButton(_ icon: String, label: String, id: String, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func decisionButton(_ icon: String, label: String, id: String, tint: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if deck.isExhausted {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 52))
                Text("You've seen them all")
                    .font(.title3.bold())
                Text(deck.isLimitedToDates
                     ? "There are no more wallpaper candidates in this date range."
                     : "There are no more wallpaper candidates in your library.")
                    .foregroundStyle(.secondary)
                Button("Scan again") { deck.start() }
                    .buttonStyle(.bordered)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Looking for wallpaper-worthy photos…")
                Text("Checked \(deck.scannedCount) of \(deck.totalCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { deck.errorMessage != nil },
            set: { if !$0 { deck.errorMessage = nil } }
        )
    }
}
