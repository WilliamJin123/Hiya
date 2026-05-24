import SwiftUI

struct HistoryView: View {
    let repo: HiyaRepository
    @State private var vm: HistoryViewModel
    @State private var editing: LoggedConversation?
    @State private var viewMode: ViewMode = .list
    @State private var displayedMonth: Date = .now
    @State private var scrollTarget: Date?

    init(repo: HiyaRepository) {
        self.repo = repo
        _vm = State(initialValue: HistoryViewModel(repo: repo))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                viewModePicker
                if viewMode == .list {
                    listContent
                } else {
                    calendarContent
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(item: $editing, onDismiss: { Task { await vm.load() } }) { entry in
            LogSheetView(repo: repo, editing: entry)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            Text("List").tag(ViewMode.list)
            Text("Calendar").tag(ViewMode.calendar)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var listContent: some View {
        if vm.sections.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(vm.sections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                Button {
                                    editing = entry
                                } label: {
                                    EntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(rowBackground(for: entry))
                                .listRowSeparatorTint(Theme.divider)
                            }
                        } header: {
                            DayHeader(section: section)
                        }
                        .id(section.date)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: scrollTarget) { _, target in
                    if let target {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        VStack(spacing: Theme.Spacing.md) {
            monthHeader
            CalendarMonthGrid(
                month: displayedMonth,
                sections: vm.sections,
                onDayTap: { date in
                    // Switch to list view + scroll to that day's section.
                    viewMode = .list
                    scrollTarget = Calendar.current.startOfDay(for: date)
                }
            )
            .padding(.horizontal, Theme.Spacing.md)
            legend
            Spacer()
        }
    }

    private var monthHeader: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(Theme.accentLavender)
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(monthLabel(displayedMonth))
                .font(Theme.FontScale.body())
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(canShiftForward ? Theme.accentLavender : Theme.textSecondary.opacity(0.4))
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!canShiftForward)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: 6) {
                Circle().fill(Theme.accentAmber).frame(width: 6, height: 6)
                Text("approaches")
                    .font(Theme.FontScale.micro())
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.accentLavender).frame(width: 6, height: 6)
                Text("catch-ups")
                    .font(Theme.FontScale.micro())
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Spacer()
            Text("Nothing here yet.\nLog a conversation and it'll show up here.")
                .multilineTextAlignment(.center)
                .font(Theme.FontScale.secondary())
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var canShiftForward: Bool {
        let cal = Calendar.current
        let displayed = cal.dateComponents([.year, .month], from: displayedMonth)
        let now = cal.dateComponents([.year, .month], from: .now)
        return (displayed.year ?? 0) < (now.year ?? 0)
            || ((displayed.year == now.year) && (displayed.month ?? 0) < (now.month ?? 0))
    }

    private func shiftMonth(by delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }

    private func monthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    /// Surface plus a faint valence wash, so a day's rows read warm/rough at a
    /// glance without reintroducing a hard color stripe. Nil valence stays plain.
    private func rowBackground(for entry: LoggedConversation) -> some View {
        let tint: Color = switch entry.valence {
            case .positive: Theme.valencePositive
            case .neutral:  Theme.valenceNeutral
            case .negative: Theme.valenceNegative
            case .none:     .clear
        }
        return ZStack {
            Theme.surface
            tint.opacity(0.10)
        }
    }
}

enum ViewMode: Hashable { case list, calendar }

private struct CalendarMonthGrid: View {
    let month: Date
    let sections: [DaySection]
    let onDayTap: (Date) -> Void

    private var sectionByDay: [Date: DaySection] {
        Dictionary(uniqueKeysWithValues: sections.map { ($0.date, $0) })
    }

    private var cells: [Date?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = interval.start
        let firstWeekday = cal.component(.weekday, from: firstDay)  // 1 = Sunday
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 0

        var out: [Date?] = []
        for _ in 1..<firstWeekday { out.append(nil) }
        for d in 0..<daysInMonth {
            out.append(cal.date(byAdding: .day, value: d, to: firstDay))
        }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    var body: some View {
        VStack(spacing: 6) {
            weekdayHeader
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let section = sectionByDay[Calendar.current.startOfDay(for: date)]
                        Button {
                            if section != nil { onDayTap(date) }
                        } label: {
                            DayCell(date: date, section: section)
                        }
                        .buttonStyle(.plain)
                        .disabled(section == nil)
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let labels = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(Theme.FontScale.micro())
                    .tracking(1.0)
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DayCell: View {
    let date: Date
    let section: DaySection?
    @State private var pulse = false

    private var isToday: Bool {
        Calendar.current.isDate(date, inSameDayAs: .now)
    }

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var hasWarm: Bool {
        guard let s = section else { return false }
        return (s.totalCount - s.coldCount) > 0
    }

    private var heatTint: Color {
        guard let s = section else { return .clear }
        let intensity = min(0.45, 0.18 + Double(s.totalCount - 1) * 0.06)
        if s.hadCold { return Theme.accentAmber.opacity(intensity) }
        return Theme.accentLavender.opacity(intensity)
    }

    private var borderColor: Color {
        guard let s = section else { return .clear }
        if isToday { return Theme.textPrimary.opacity(0.6) }
        if s.hadCold && hasWarm { return Theme.accentLavender.opacity(0.65) }
        return .clear
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(dayNumber)
                .font(Theme.FontScale.body())
                .foregroundColor(section != nil ? Theme.textPrimary : Theme.textSecondary.opacity(0.5))
            if let s = section, s.totalCount > 1 {
                Text("\(s.totalCount)")
                    .font(Theme.FontScale.micro())
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(heatTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .shadow(
            color: isToday ? Theme.accentLavender.opacity(pulse ? 0.55 : 0.0) : .clear,
            radius: pulse ? 9 : 3
        )
        .onAppear {
            guard isToday else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct DayHeader: View {
    let section: DaySection

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(Self.dateFormatter.string(from: section.date).uppercased())
                .font(Theme.FontScale.bodyHeading())
                .tracking(1.2)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            if section.coldCount > 0 {
                Text("\(section.coldCount) \(section.coldCount == 1 ? "approach" : "approaches")")
                    .font(Theme.FontScale.micro())
                    .tracking(0.8)
                    .foregroundColor(Theme.accentAmber)
            }
            Text("\(section.uniquePeopleCount) · \(section.totalCount) log\(section.totalCount == 1 ? "" : "s")")
                .font(Theme.FontScale.micro())
                .tracking(0.8)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct EntryRow: View {
    let entry: LoggedConversation

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(valenceColor)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.personName)
                    .font(Theme.FontScale.body())
                    .foregroundColor(Theme.textPrimary)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(Theme.FontScale.secondary())
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(entry.occurredAt, style: .time)
                .font(Theme.FontScale.micro())
                .tracking(0.8)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var valenceColor: Color {
        switch entry.valence {
        case .positive: Theme.valencePositive
        case .neutral:  Theme.valenceNeutral
        case .negative: Theme.valenceNegative
        case .none:     Theme.valenceNone
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView(repo: MockHiyaRepository())
    }
    .preferredColorScheme(.dark)
}
