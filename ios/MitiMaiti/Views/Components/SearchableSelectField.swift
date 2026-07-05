import SwiftUI

/// A tappable field that opens a searchable directory sheet: a search bar plus
/// a scrollable list of `options`. Always allows a custom value via
/// "Use \"<query>\"", so an incomplete directory never blocks a real entry.
/// Visual style mirrors AppTextField.
struct SearchableSelectField: View {
    @Binding var value: String
    let options: [String]
    var placeholder: String = "Tap to choose"
    var searchHint: String = "Search…"
    var title: String = "Select"

    @Environment(\.adaptiveColors) private var colors
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 12) {
                Text(value.isEmpty ? placeholder : value)
                    .foregroundColor(value.isEmpty ? colors.textMuted : colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.textMuted)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                    .fill(colors.cardDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                            .stroke(colors.border, lineWidth: 1)
                    )
                    .shadow(color: colors.cardShadowColor, radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            SearchableSelectSheet(
                value: $value,
                options: options,
                searchHint: searchHint,
                title: title,
                isPresented: $showSheet
            )
        }
    }
}

private struct SearchableSelectSheet: View {
    @Binding var value: String
    let options: [String]
    let searchHint: String
    let title: String
    @Binding var isPresented: Bool

    @Environment(\.adaptiveColors) private var colors
    @State private var query: String = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? options : options.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    private var exactMatch: Bool {
        options.contains { $0.caseInsensitiveCompare(query.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                AppTextField(placeholder: searchHint, text: $query, icon: "magnifyingglass")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                List {
                    let trimmed = query.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !exactMatch {
                        Button {
                            value = trimmed; isPresented = false
                        } label: {
                            Text("Use \"\(trimmed)\"")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.rose)
                        }
                    }
                    ForEach(filtered, id: \.self) { opt in
                        Button {
                            value = opt; isPresented = false
                        } label: {
                            HStack {
                                Text(opt).foregroundColor(colors.textPrimary)
                                Spacer()
                                if opt.caseInsensitiveCompare(value) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(AppTheme.rose)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .background(colors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
