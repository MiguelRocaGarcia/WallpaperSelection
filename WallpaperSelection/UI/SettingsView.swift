import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var deck: DeckModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(FilterSettings.Key.maxPersonArea) private var maxPersonArea = FilterSettings.defaults.maxPersonArea
    @AppStorage(FilterSettings.Key.maxPersonHeight) private var maxPersonHeight = FilterSettings.defaults.maxPersonHeight
    @AppStorage(FilterSettings.Key.minShortSide) private var minShortSide = FilterSettings.defaults.minShortSide
    @AppStorage(FilterSettings.Key.order) private var order = FilterSettings.defaults.order
    @AppStorage(FilterSettings.Key.limitDates) private var limitDates = false
    @AppStorage(FilterSettings.Key.startDate) private var startDateValue = FilterSettings.defaultStartDate.timeIntervalSince1970
    @AppStorage(FilterSettings.Key.endDate) private var endDateValue = FilterSettings.defaultEndDate.timeIntervalSince1970

    @State private var confirmResetRejections = false
    @State private var confirmClearCache = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Order", selection: $order) {
                        Text("Random").tag(PhotoOrder.random)
                        Text("Newest first").tag(PhotoOrder.newestFirst)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("orderPicker")

                    Toggle("Only photos between", isOn: $limitDates)
                        .accessibilityIdentifier("limitDatesToggle")
                    if limitDates {
                        DatePicker("From", selection: dateBinding($startDateValue),
                                   in: ...dateBinding($endDateValue).wrappedValue, displayedComponents: .date)
                        DatePicker("To", selection: dateBinding($endDateValue),
                                   in: min(dateBinding($startDateValue).wrappedValue, Date())...Date(),
                                   displayedComponents: .date)
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Photos you've already swiped won't appear again, whatever the order.")
                }

                Section {
                    sliderRow("Max person size (area)", value: $maxPersonArea, range: 0.005...0.10, step: 0.005)
                    sliderRow("Max person height", value: $maxPersonHeight, range: 0.05...0.60, step: 0.01)
                    Button("Restore defaults") {
                        maxPersonArea = FilterSettings.defaults.maxPersonArea
                        maxPersonHeight = FilterSettings.defaults.maxPersonHeight
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("Photos are skipped when a person takes up more than this share of the image. Raise these to allow closer people, lower them to be stricter.")
                }

                Section {
                    Picker("Minimum width", selection: $minShortSide) {
                        Text("720 px").tag(720)
                        Text("1080 px").tag(1080)
                        Text("1179 px (iPhone 16)").tag(1179)
                        Text("1440 px").tag(1440)
                    }
                } header: {
                    Text("Quality")
                } footer: {
                    Text("Photos narrower than this look soft as a full-screen wallpaper.")
                }

                Section("Progress") {
                    LabeledContent("In \(PhotoLibraryService.albumTitle) album", value: "\(deck.acceptedCount)")
                    LabeledContent("Skipped", value: "\(deck.rejectedCount)")
                    LabeledContent("Photos checked", value: "\(deck.scannedCount) of \(deck.totalCount)")
                }

                Section {
                    Button("Rescan library") {
                        deck.start()
                        dismiss()
                    }
                    Button("Reset skipped photos", role: .destructive) { confirmResetRejections = true }
                    Button("Clear analysis cache", role: .destructive) { confirmClearCache = true }
                } footer: {
                    Text("Rescan picks up new photos. Clearing the cache re-analyzes every photo, which takes a while.")
                }

                Section("Use as wallpaper") {
                    Text("On your Lock Screen, touch and hold ▸ tap + ▸ Photo Shuffle ▸ choose the \(PhotoLibraryService.albumTitle) album, then pick how often it changes.")
                        .font(.callout)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Show all skipped photos again?", isPresented: $confirmResetRejections,
                                titleVisibility: .visible) {
                Button("Reset \(deck.rejectedCount) skipped photos", role: .destructive) {
                    deck.resetRejections()
                }
            }
            .confirmationDialog("Re-analyze every photo?", isPresented: $confirmClearCache,
                                titleVisibility: .visible) {
                Button("Clear cache", role: .destructive) {
                    deck.clearAnalysisCache()
                }
            }
        }
        .onDisappear {
            deck.restartIfSettingsChanged()
        }
    }

    /// Dates are stored as seconds since 1970 so they fit in @AppStorage.
    private func dateBinding(_ value: Binding<Double>) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: value.wrappedValue) },
            set: { value.wrappedValue = $0.timeIntervalSince1970 }
        )
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
