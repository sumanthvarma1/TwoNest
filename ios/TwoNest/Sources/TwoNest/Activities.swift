import SwiftUI
import MapKit

struct ActivityCategory: Identifiable {
    let id: String; let title: String; let icon: String
    static let all: [Self] = [
        .init(id: "shopping", title: "Shopping", icon: "bag"), .init(id: "hangout", title: "Hang out", icon: "person.2"),
        .init(id: "drinks", title: "A beer / drinks", icon: "mug"), .init(id: "gaming", title: "Gaming", icon: "gamecontroller"),
        .init(id: "coffee", title: "Coffee", icon: "cup.and.saucer"), .init(id: "food", title: "Food", icon: "fork.knife"),
        .init(id: "fitness", title: "Fitness", icon: "figure.run"), .init(id: "culture", title: "Culture", icon: "building.columns"),
        .init(id: "outdoors", title: "Outdoors", icon: "leaf"), .init(id: "other", title: "Anything else", icon: "sparkles")]
    static func find(_ id: String) -> Self { all.first { $0.id == id } ?? all.last! }
}

enum ActivityDates {
    static func parse(_ raw: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; if let value = f.date(from: raw) { return value }; f.formatOptions = [.withInternetDateTime]; return f.date(from: raw) }
    static func display(_ raw: String) -> String { guard let date = parse(raw) else { return raw }; if Calendar.current.isDateInToday(date) { return "Today · " + date.formatted(date: .omitted, time: .shortened) }; return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) }
}

struct ActivityHubView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [String] = []
    @State private var plans: [ActivityPlan] = []
    @State private var mine: [ActivityPlan] = []
    @State private var availability: ActivityAvailabilityState?
    @State private var category = ""
    @State private var mode = "both"
    @State private var area = ""
    @State private var visible = false
    @State private var loading = true
    @State private var error: String?
    @State private var creating = false
    @State private var settingAvailability = false
    @State private var section = "map"
    @State private var inviting: ActivityMapMember?
    @State private var live = ActivityLiveConnection()
    @State private var mapRefresh = 0
    private var showMine: Bool { section != "map" }
    @State private var initialized = false
    private var refreshID: String { "\(scenePhase)-\(visible)-\(category)-\(mode)-\(area)" }
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            Text("Go do something. Together.").font(.system(size: 23, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Label(live.connected ? "Live" : "Connecting", systemImage: live.connected ? "dot.radiowaves.left.and.right" : "arrow.trianglehead.2.clockwise.rotate.90").font(.caption).foregroundStyle(Theme.forest)
                        }
                        if section != "plans", let invitation = mine.first(where: { $0.my_join_status == "invited" && $0.status == "open" }) {
                            Button { path.append(invitation.id) } label: { Label("\(invitation.host.first_name) invited you · \(invitation.title)", systemImage: "envelope.badge").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(OutlineButton())
                        }
                        Picker("Rally", selection: $section) { Text("Map").tag("map"); Text("My plans (\(mine.count))").tag("plans"); Text("Chats").tag("chats") }.pickerStyle(.segmented)
                        if !showMine {
                            filters
                            ActivityMapDiscovery(category: category, mode: mode, refresh: mapRefresh, ownPlans: mine.filter { $0.is_host }, onOpen: { path.append($0) }, onInvite: { inviting = $0 }, onPlans: { plans = $0; loading = false })
                        }
                        Button { creating = true } label: { HStack { Image(systemName: "plus"); Text("Make a Rally plan"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(ForestButton())
                        availabilityCard
                        if loading && plans.isEmpty && mine.isEmpty { ProgressView("Finding plans…").frame(maxWidth: .infinity).padding(25) }
                        else {
                            let displayed = section == "chats" ? mine.filter { $0.chat_open } : showMine ? mine : plans
                            if displayed.isEmpty { emptyState }
                            LazyVStack(spacing: 14) { ForEach(displayed) { plan in NavigationLink(value: plan.id) { ActivityPlanCard(plan: plan) }.buttonStyle(.plain) } }
                        }
                        if let error { Text(error).font(.subheadline).foregroundStyle(Theme.berry); Button("Try again") { Task { await load() } }.buttonStyle(OutlineButton()) }
                        Text("Rally has its own plans and chats. Live updates run while the app is open; background notifications aren’t connected yet.").font(.footnote).foregroundStyle(Theme.muted)
                    }.padding(24)
                }.refreshable { await load() }
            }.navigationTitle("Rally").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { creating = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel("Create activity request") } }
                .navigationDestination(for: String.self) { ActivityDetailView(requestID: $0) }
                .sheet(isPresented: $creating) { CreateActivityView(initialCategory: category) { plan in creating = false; path.append(plan.id); Task { await load() } } }
                .sheet(item: $inviting) { person in ActivityInviteSheet(person: person) { creating = true } }
                .sheet(isPresented: $settingAvailability) { ActivityAvailabilityView(current: availability, defaultArea: area) { value in availability = value; settingAvailability = false } }
                .onAppear { if !initialized { area = "New York"; initialized = true }; visible = true }.onDisappear { visible = false }
                .task(id: refreshID) {
                    guard visible && scenePhase == .active else { return }
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    await load()
                }
                .task(id: "live-\(scenePhase)-\(visible)") {
                    guard visible && scenePhase == .active, let token = session.token else { return }
                    await live.run(api: session.api, token: token) { mapRefresh += 1; await load() }
                }
        }
    }
    private var availabilityCard: some View {
        Button { settingAvailability = true } label: {
            HStack(spacing: 14) {
                Image(systemName: availability?.enabled == true ? "dot.radiowaves.left.and.right" : "clock").font(.title2).foregroundStyle(Theme.forest).frame(width: 42)
                VStack(alignment: .leading, spacing: 5) { Text(availability?.enabled == true ? "You’re up for something" : "Have a little time to spare?").font(.headline).foregroundStyle(Theme.ink); Text(availability?.enabled == true ? "Available until " + (ActivityDates.parse(availability?.expires_at ?? "")?.formatted(date: .omitted, time: .shortened) ?? "soon") : "Choose what you’re open to for the next hour.").font(.footnote).foregroundStyle(Theme.muted) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }.padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 21))
        }.buttonStyle(.plain)
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { categoryButton("", "Anything", "sparkles"); ForEach(ActivityCategory.all) { item in categoryButton(item.id, item.title, item.icon) } } }.contentMargins(.vertical, 2)
            Picker("Meeting mode", selection: $mode) { Text("All plans").tag("both"); Text("In person").tag("in_person"); Text("Online").tag("online") }.pickerStyle(.segmented)

        }
    }
    private func categoryButton(_ id: String, _ title: String, _ icon: String) -> some View {
        Button { category = id } label: { Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 12).foregroundStyle(category == id ? .white : Theme.forest).background(category == id ? Theme.forest : Theme.paper, in: Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(category == id ? [.isSelected] : [])
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: showMine ? "calendar.badge.plus" : "sparkles").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.berry)
            Text(section == "chats" ? "Your Rally chats start with a plan." : showMine ? "Your next plan starts here." : "Be the first to put\na plan out there.").font(.system(size: 26, weight: .medium, design: .serif))
            Text(section == "chats" ? "Accept an invitation or connect through a plan. Its private chat will appear here, separate from dating Messages." : showMine ? "Requests, invitations and plans you host appear here. Once accepted, coordinate in the plan’s private chat." : "No open request fits these filters yet. Try another area or activity, or invite someone into an idea of your own.").font(.subheadline).foregroundStyle(Theme.muted)
            Button("Create a request") { creating = true }.buttonStyle(OutlineButton())
        }.padding(23).frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 25))
    }
    private func load() async {
        guard let token = session.token else { return }
        defer { loading = false }
        do {
            let nextMine: [ActivityPlan] = try await session.api.get("/activities/mine", token: token)
            let nextAvailability: ActivityAvailabilityState = try await session.api.get("/activities/availability", token: token)
            guard !Task.isCancelled else { return }; mine = nextMine; availability = nextAvailability; if !nextAvailability.area.isEmpty { area = nextAvailability.area }; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ActivityPlanCard: View {
    let plan: ActivityPlan
    var body: some View {
        let category = ActivityCategory.find(plan.category)
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label(category.title, systemImage: category.icon).font(.caption.weight(.semibold)).foregroundStyle(Theme.berry); Spacer(); Text(plan.is_host ? "YOUR REQUEST" : plan.my_join_status == "accepted" ? "YOU’RE IN" : plan.my_join_status == "invited" ? "INVITED" : plan.my_join_status == "pending" ? "REQUESTED" : plan.mode == "online" ? "ONLINE" : "IN PERSON").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Theme.forest) }
            Text(plan.title).font(.system(size: 25, weight: .medium, design: .serif)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if !plan.description.isEmpty { Text(plan.description).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2) }
            HStack { Label(plan.mode == "online" ? "Online" : plan.area, systemImage: plan.mode == "online" ? "globe" : "mappin.and.ellipse"); Spacer(); Text(ActivityDates.display(plan.starts_at)) }.font(.caption).foregroundStyle(Theme.muted)
            Divider().overlay(Theme.line)
            HStack { Text(String(plan.host.first_name.prefix(1))).font(.system(size: 16, weight: .medium, design: .serif)).foregroundStyle(Theme.forest).frame(width: 32, height: 32).background(Theme.sage.opacity(0.35), in: Circle()); Text(plan.is_host ? "Hosted by you" : "With \(plan.host.first_name)").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink); Spacer(); Text("\(plan.accepted_count)/\(plan.companion_limit) companions").font(.caption).foregroundStyle(Theme.muted) }
            HStack { Text(plan.statusLabel).font(.caption.weight(.semibold)).foregroundStyle(plan.isEnded ? Theme.muted : Theme.forest); if plan.pending_count > 0 { Text("· \(plan.pending_count) to review").font(.caption).foregroundStyle(Theme.berry) }; Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.forest) }
        }.padding(21).background(Theme.paper, in: RoundedRectangle(cornerRadius: 25)).overlay(RoundedRectangle(cornerRadius: 25).stroke(Theme.line)).nestScrollMotion()
    }
}

struct CreateActivityView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let initialCategory: String
    let onCreated: (ActivityPlan) -> Void
    @State private var category = "hangout"
    @State private var title = ""
    @State private var description = ""
    @State private var mode = "in_person"
    @State private var area = ""
    @State private var meetingDetails = ""
    @State private var meetingPlace: ActivityPlaceChoice?
    @State private var choosingPlace = false
    @State private var startsAt = Date.now.addingTimeInterval(1800)
    @State private var discoveryMinutes = 60
    @State private var companionLimit = 1
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Put your plan out there.").font(.system(size: 27, weight: .medium, design: .serif)); Text("People ask to join. You choose who comes, and accepted members get a private plan chat.").font(.subheadline).foregroundStyle(Theme.muted) }
                Section("What are you up for?") {
                    Picker("Activity", selection: $category) { ForEach(ActivityCategory.all) { Label($0.title, systemImage: $0.icon).tag($0.id) } }
                    TextField("A short title for your plan", text: $title)
                    TextField("Tell people a little more (optional)", text: $description, axis: .vertical).lineLimit(2...5)
                }
                Section("How and when") {
                    Picker("Meet", selection: $mode) { Text("In person").tag("in_person"); Text("Online").tag("online") }.pickerStyle(.segmented)
                    if mode == "in_person" {
                        TextField("Broad neighbourhood, e.g. Brooklyn", text: $area)
                        Button { choosingPlace = true } label: { Label(meetingPlace?.name ?? "Choose a public meetup place on the map", systemImage: "mappin.and.ellipse") }
                        if let place = meetingPlace { Text(place.address).font(.caption).foregroundStyle(Theme.muted) }
                        Text("The map shows the approximate area. The exact meeting point is shared with accepted members.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    DatePicker("Starts", selection: $startsAt, in: Date.now...Date.now.addingTimeInterval(7 * 86400))
                    Button("Make it soon · in 10 minutes") { startsAt = Date.now.addingTimeInterval(600) }
                    Stepper(companionLimit == 1 ? "One companion" : "\(companionLimit) companions · \(companionLimit + 1) people total", value: $companionLimit, in: 1...5)
                    Picker("Look for company for", selection: $discoveryMinutes) { Text("15 minutes").tag(15); Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("4 hours").tag(240); Text("24 hours").tag(1440) }
                    Text("Requests close at the end of this window or one hour after the plan starts, whichever comes first.").font(.footnote).foregroundStyle(Theme.muted)
                }
                Section("Only after you accept someone") {
                    TextField(mode == "online" ? "Game, lobby or meeting details (optional)" : "Public meeting point (optional)", text: $meetingDetails, axis: .vertical).lineLimit(2...4)
                    Text("These details are hidden from the public request. Accepted members can see the meeting details and group chat. Choose a public place for a first in-person meetup.").font(.footnote).foregroundStyle(Theme.muted)
                }
                if let error { Section { Text(error).foregroundStyle(Theme.berry) } }
                Section { Button { Task { await publish() } } label: { HStack { if busy { ProgressView() }; Text(busy ? "Sending request…" : "Send request"); Spacer(); Image(systemName: "arrow.right") } }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || (mode == "in_person" && (meetingPlace == nil || area.trimmingCharacters(in: .whitespacesAndNewlines).count < 2))) }
            }.scrollContentBackground(.hidden).background(Theme.cream).navigationTitle("Make a plan").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }.onAppear { if !initialCategory.isEmpty { category = initialCategory }; area = "New York" }
        }.sheet(isPresented: $choosingPlace) { ActivityPlaceSearch(title: "Choose a meetup place") { place in meetingPlace = place; if !place.city.isEmpty { area = place.city } } }.interactiveDismissDisabled(busy)
    }
    private func publish() async {
        guard !busy, let token = session.token else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let plan: ActivityPlan = try await session.api.send("/activities", method: "POST", body: ["category": category, "title": title, "description": description, "mode": mode, "area": area, "meeting_details": meetingDetails, "starts_at": ISO8601DateFormatter().string(from: startsAt), "discovery_minutes": discoveryMinutes, "companion_limit": companionLimit, "latitude": mode == "in_person" ? (meetingPlace.map { $0.coordinate.latitude as Any } ?? NSNull()) : NSNull(), "longitude": mode == "in_person" ? (meetingPlace.map { $0.coordinate.longitude as Any } ?? NSNull()) : NSNull(), "meeting_name": meetingPlace?.name ?? ""], token: token)
            onCreated(plan); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ActivityAvailabilityView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let current: ActivityAvailabilityState?
    let defaultArea: String
    let onSaved: (ActivityAvailabilityState) -> Void
    @State private var enabled = true
    @State private var area = ""
    @State private var categories: Set<String> = []
    @State private var mode = "both"
    @State private var duration = 60
    @State private var showOnMap = false
    @State private var mapPlace: ActivityPlaceChoice?
    @State private var choosingArea = false
    @State private var location = ActivityLocation()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Leave room for a plan.").font(.system(size: 26, weight: .medium, design: .serif)); Text("Availability expires automatically. It helps hosts see whether people are open to their activity; you still decide which requests to join.").font(.subheadline).foregroundStyle(Theme.muted); Toggle("I’m available", isOn: $enabled) }
                if enabled {
                    Section("Where and how") { Picker("Meet", selection: $mode) { Text("Online or in person").tag("both"); Text("In person").tag("in_person"); Text("Online").tag("online") }; if mode != "online" { TextField("Broad neighbourhood", text: $area) }; Picker("Available for", selection: $duration) { Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120); Text("4 hours").tag(240) } }
                    if mode != "online" {
                        Section("People can find me on Rally") {
                            Toggle("Show my approximate area on the map", isOn: $showOnMap)
                            if showOnMap {
                                Button { choosingArea = true } label: { Label(mapPlace?.name ?? "Choose an area", systemImage: "map") }
                                Button(location.locating ? "Locating…" : "Use my location") { location.request() }.disabled(location.locating)
                                Text("Only a rounded area is saved, roughly a few city blocks. Visibility ends with your availability. Switch this off to disappear from the people map.").font(.footnote).foregroundStyle(Theme.muted)
                                if let message = location.message { Text(message).font(.caption).foregroundStyle(Theme.berry) }
                            }
                        }
                    }
                    Section("I’m up for…") { ForEach(ActivityCategory.all) { item in Toggle(item.title, isOn: Binding(get: { categories.contains(item.id) }, set: { value in if value { categories.insert(item.id) } else { categories.remove(item.id) } })) }; Text("Leave all unselected if you’re open to anything.").font(.footnote).foregroundStyle(Theme.muted) }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.berry) } }
            }.scrollContentBackground(.hidden).background(Theme.cream).navigationTitle("Rally availability").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }; ToolbarItem(placement: .confirmationAction) { Button(busy ? "Saving…" : "Save") { Task { await save() } }.disabled(busy || (enabled && mode != "online" && area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) } }.onAppear { area = current?.area.isEmpty == false ? current!.area : defaultArea; mode = current?.mode ?? "both"; categories = Set(current?.categories ?? []); showOnMap = current?.show_on_map == true; if let lat = current?.latitude, let lon = current?.longitude { mapPlace = .init(name: "Your saved area", address: area, coordinate: .init(latitude: lat, longitude: lon), city: area) } }
        }.sheet(isPresented: $choosingArea) { ActivityPlaceSearch(title: "Your approximate area") { place in mapPlace = place; area = place.city.isEmpty ? place.name : place.city } }
            .onChange(of: location.coordinate?.latitude) { _, _ in if let coordinate = location.coordinate { mapPlace = .init(name: "Around my location", address: area, coordinate: coordinate, city: area) } }
            .interactiveDismissDisabled(busy)
    }
    private func save() async {
        if enabled && showOnMap && mode != "online" && mapPlace == nil { error = "Choose an area before appearing on the map."; return }
        busy = true; error = nil; defer { busy = false }
        do { let result: ActivityAvailabilityState = try await session.api.send("/activities/availability", method: "PUT", body: ["enabled": enabled, "area": area, "categories": categories.sorted(), "mode": mode, "duration_minutes": duration, "show_on_map": showOnMap && mode != "online", "latitude": mapPlace.map { $0.coordinate.latitude as Any } ?? NSNull(), "longitude": mapPlace.map { $0.coordinate.longitude as Any } ?? NSNull()], token: session.token); onSaved(result); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct ActivityDetailView: View {
    let requestID: String
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plan: ActivityPlan?
    @State private var live = ActivityLiveConnection()
    @State private var travelling = false
    @State private var error: String?
    @State private var busy = false
    @State private var joinNote = ""
    @State private var draft = ""
    @State private var confirming: String?
    @State private var reporting: ActivityMember?
    @State private var blocking: ActivityMember?
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        if let plan {
                            ActivityPlanCard(plan: plan)
                            if plan.is_host && plan.status == "open" {
                                Card { VStack(alignment: .leading, spacing: 11) { Label("Your request is live", systemImage: "dot.radiowaves.left.and.right").font(.headline).foregroundStyle(Theme.forest); Text(plan.available_members > 0 ? "\(plan.available_members) member\(plan.available_members == 1 ? " is" : "s are") currently available for this activity and broad area." : "No member is marked available for this activity here right now. Your request is still open for people to find and join.").font(.subheadline).foregroundStyle(Theme.muted); Text("Join requests close " + ActivityDates.display(plan.expires_at)).font(.caption).foregroundStyle(Theme.muted) } }
                            }
                            if plan.mode == "in_person" && plan.latitude != nil {
                                Button { travelling = true } label: { HStack { Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath"); VStack(alignment: .leading, spacing: 4) { Text("How to get there").font(.headline); Text("Walk · bus & train · drive · cab / Uber").font(.caption) }; Spacer(); Image(systemName: "arrow.up.right") } }.buttonStyle(OutlineButton())
                            }
                            actionArea(plan)
                            if plan.is_host && !(plan.applicants ?? []).isEmpty { Text("Who’s up for it").font(.system(size: 25, weight: .medium, design: .serif)); ForEach(plan.applicants ?? []) { applicant in applicantCard(applicant, plan: plan) } }
                            if plan.is_host || plan.my_join_status == "accepted" {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Your people").font(.system(size: 25, weight: .medium, design: .serif))
                                    ForEach(plan.participants ?? []) { member in memberRow(member) }
                                }
                                if let details = plan.meeting_details, !details.isEmpty { Card { VStack(alignment: .leading, spacing: 10) { Label("Your private plan", systemImage: "lock").font(.headline).foregroundStyle(Theme.forest); Text(details).font(.subheadline).textSelection(.enabled); Text("Shared with accepted members only.").font(.caption).foregroundStyle(Theme.muted) } } }
                            }
                            if plan.chat_open {
                                Text("Plan chat").font(.system(size: 25, weight: .medium, design: .serif)).id("chat")
                                Text("Only the host and accepted members can read and send messages here.").font(.footnote).foregroundStyle(Theme.muted)
                                if (plan.messages ?? []).isEmpty { Text("You’re connected. Say hello and work out the details together.").font(.subheadline).foregroundStyle(Theme.muted).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20)) }
                                ForEach(plan.messages ?? []) { message in messageBubble(message) }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                        } else if error == nil { ProgressView("Opening your plan…").frame(maxWidth: .infinity).padding(60) }
                        if let error { Text(error).font(.subheadline).foregroundStyle(Theme.berry); Button("Refresh plan") { Task { await load() } }.buttonStyle(OutlineButton()) }
                    }.padding(24)
                }.scrollDismissesKeyboard(.interactively).refreshable { await load() }.onChange(of: plan?.messages?.last?.id) { old, new in if old != nil && new != nil && focused { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } } }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) { if plan?.chat_open == true { composer } }
            .navigationTitle("Your plan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { if let plan { Menu { if plan.is_host && !plan.isEnded { Button("Cancel plan", role: .destructive) { confirming = "cancel" }; if (ActivityDates.parse(plan.starts_at) ?? .distantFuture) <= .now { Button("Mark completed") { confirming = "complete" } } }; if !plan.is_host && ["pending", "accepted", "invited"].contains(plan.my_join_status ?? "") { Button("Leave plan", role: .destructive) { confirming = "leave" } }; if !plan.is_host { Button("Report host") { reporting = plan.host }; Button("Block host", role: .destructive) { blocking = plan.host } } } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Plan options") } } } }
            .confirmationDialog(confirming == "cancel" ? "Cancel this plan for everyone?" : confirming == "complete" ? "Mark this plan completed?" : "Leave this plan?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) { Button(confirming == "complete" ? "Mark completed" : confirming == "cancel" ? "Cancel plan" : "Leave plan", role: confirming == "complete" ? nil : .destructive) { let action = confirming ?? "leave"; confirming = nil; Task { await mutate(action == "leave" ? "/leave" : "/state", body: action == "leave" ? nil : ["action": action]) } }; Button("Keep plan", role: .cancel) { confirming = nil } }
            .sheet(isPresented: $travelling) { if let plan { ActivityTravelView(plan: plan) } }
            .sheet(item: $reporting) { member in SafetyReportSheet(memberID: member.id, firstName: member.first_name) { message in error = message } }
            .confirmationDialog("Block this member?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) { Button("Block", role: .destructive) { if let member = blocking { Task { await block(member) } }; blocking = nil }; Button("Cancel", role: .cancel) { blocking = nil } } message: { Text("You won’t connect through new requests. A shared plan membership ends between you.") }
            .task(id: scenePhase) { guard scenePhase == .active, let token = session.token else { return }; await load(); await live.run(api: session.api, token: token) { await load() } }
    }
    @ViewBuilder private func actionArea(_ plan: ActivityPlan) -> some View {
        if plan.isEnded { Label(plan.statusLabel + " · chat is closed", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Theme.muted) }
        else if !plan.is_host && plan.my_join_status == "accepted" { Label("You’re in. Work out the details together below.", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.forest) }
        else if !plan.is_host && plan.my_join_status == "invited" {
            Card { VStack(alignment: .leading, spacing: 12) { Text("\(plan.host.first_name) invited you").font(.headline); Text("Accept to take a place in this plan and open its private chat.").font(.subheadline).foregroundStyle(Theme.muted); Button("Accept invitation") { Task { await mutate("/join", body: ["note": ""]) } }.buttonStyle(ForestButton()).disabled(busy || plan.status != "open"); Button("Decline invitation") { confirming = "leave" }.buttonStyle(OutlineButton()).disabled(busy) } }
        }
        else if !plan.is_host && plan.my_join_status == "pending" { Card { VStack(alignment: .leading, spacing: 12) { Text("Your join request is sent").font(.headline); Text("\(plan.host.first_name) will review it. The private plan and chat open after acceptance.").font(.subheadline).foregroundStyle(Theme.muted); Button("Withdraw request") { confirming = "leave" }.buttonStyle(OutlineButton()).disabled(busy) } } }
        else if !plan.is_host && ["declined", "removed"].contains(plan.my_join_status ?? "") { Text("This join request has ended. Explore another plan that feels right.").font(.subheadline).foregroundStyle(Theme.muted) }
        else if !plan.is_host && plan.status == "open" {
            Card { VStack(alignment: .leading, spacing: 14) { Text("Up for this?").font(.system(size: 25, weight: .medium, design: .serif)); TextField("A little hello to the host (optional)", text: $joinNote, axis: .vertical).lineLimit(2...4).padding(14).background(Theme.cream, in: RoundedRectangle(cornerRadius: 15)); Text("\(joinNote.count)/300").font(.caption).foregroundStyle(Theme.muted); Button { Task { await mutate("/join", body: ["note": joinNote]) } } label: { HStack { if busy { ProgressView().tint(.white) }; Text("Ask to join"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(ForestButton()).disabled(busy || joinNote.count > 300); Text("Your first name and this note are shared with the host. You choose whether to join; they choose whom to accept.").font(.footnote).foregroundStyle(Theme.muted) } }
        } else if !plan.is_host { Text("This request is no longer looking for company.").font(.subheadline).foregroundStyle(Theme.muted) }
    }
    private func applicantCard(_ applicant: ActivityApplicant, plan: ActivityPlan) -> some View {
        Card { VStack(alignment: .leading, spacing: 14) { memberRow(applicant.member); if !applicant.member.bio.isEmpty { Text(applicant.member.bio).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(3) }; if !applicant.note.isEmpty { Text("“\(applicant.note)”").font(.subheadline).foregroundStyle(Theme.ink) }; HStack { Button("Accept") { Task { await mutate("/joins/\(applicant.id)/decision", body: ["accepted": true]) } }.buttonStyle(ForestButton()); Button("Pass") { Task { await mutate("/joins/\(applicant.id)/decision", body: ["accepted": false]) } }.buttonStyle(OutlineButton()) }.disabled(busy || plan.status != "open") } }
    }
    private func memberRow(_ member: ActivityMember) -> some View {
        HStack(spacing: 12) { Text(String(member.first_name.prefix(1))).font(.system(size: 20, weight: .medium, design: .serif)).foregroundStyle(Theme.forest).frame(width: 43, height: 43).background(Theme.sage.opacity(0.3), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(member.id == session.user?.id ? "You" : member.first_name).font(.headline); if !member.area.isEmpty { Text(member.area).font(.caption).foregroundStyle(Theme.muted) } }; Spacer(); if member.id != session.user?.id { Menu { Button("Report a concern") { reporting = member }; Button("Block member", role: .destructive) { blocking = member } } label: { Image(systemName: "ellipsis").padding(10).accessibilityLabel("Options for \(member.first_name)") } } }
    }
    private func messageBubble(_ message: ActivityMessage) -> some View {
        let mine = message.sender_id == session.user?.id
        return HStack { if mine { Spacer(minLength: 35) }; VStack(alignment: .leading, spacing: 6) { Text(mine ? "You" : message.first_name).font(.caption.weight(.semibold)).foregroundStyle(mine ? Theme.sage : Theme.berry); Text(message.body).font(.system(size: 16)).foregroundStyle(mine ? .white : Theme.ink); Text(ActivityDates.parse(message.created_at)?.formatted(date: .omitted, time: .shortened) ?? "").font(.system(size: 10)).foregroundStyle(mine ? .white.opacity(0.65) : Theme.muted) }.padding(15).background(mine ? Theme.forest : Theme.paper, in: RoundedRectangle(cornerRadius: 20)); if !mine { Spacer(minLength: 35) } }.accessibilityElement(children: .combine)
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) { TextField("Message your people…", text: $draft, axis: .vertical).lineLimit(1...4).focused($focused).padding(14).background(Theme.cream, in: RoundedRectangle(cornerRadius: 20)); Button { Task { await send() } } label: { Image(systemName: busy ? "ellipsis" : "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 48, height: 48).background(Theme.forest, in: Circle()) }.disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000).accessibilityLabel("Send to plan chat") }.padding(16).background(Theme.paper)
    }
    private func load() async {
        guard !busy, let token = session.token else { return }
        do { let result: ActivityPlan = try await session.api.get("/activities/\(requestID)", token: token); if result.revision >= (plan?.revision ?? -1) { plan = result } }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; if (error as? APIError)?.statusCode == 404 { plan = nil } } }
    }
    private func mutate(_ path: String, body: [String: Any]? = nil) async {
        guard !busy, let token = session.token else { return }; busy = true; error = nil; defer { busy = false }
        do { plan = try await session.api.send("/activities/\(requestID)" + path, method: "POST", body: body, token: token) }
        catch { self.error = error.localizedDescription }
    }
    private func send() async {
        guard !busy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.count <= 2000 else { return }
        busy = true; error = nil
        do { let _: ActivityMessage = try await session.api.send("/activities/\(requestID)/messages", method: "POST", body: ["body": draft], token: session.token); draft = "" }
        catch { self.error = error.localizedDescription }; busy = false; await load()
    }
    private func block(_ member: ActivityMember) async {
        busy = true
        do { let _: MemberBlockResponse = try await session.api.send("/members/\(member.id)/block", method: "POST", token: session.token); error = "Member blocked. Your shared plan membership has ended." }
        catch { self.error = error.localizedDescription }; busy = false; await load()
    }
}
