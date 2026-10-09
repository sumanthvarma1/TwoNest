import SwiftUI
import Observation
import AVFoundation

@main struct TwoNestApp: App {
    @State private var session = SessionStore()
    var body: some Scene { WindowGroup { RootView().environment(session).tint(Theme.forest) } }
}

@Observable @MainActor final class SessionStore {
    var user: Member?; var token: String? { didSet { if let token { Keychain.save(token) } } }; var error: String?
    var restoring = false
    var preferredTab = 0
    let api = APIClient()
    init() { token = Keychain.read(); if let token { restoring = true; Task { await loadMe(token); restoring = false } } }
    func signIn(_ email: String) async { do { let result: LoginResponse = try await api.send("/auth/dev-login", method: "POST", body: ["email": email]); token = result.access_token; user = result.user; error = nil } catch { self.error = error.localizedDescription } }
    func signUp(_ email: String) async { do { let result: LoginResponse = try await api.send("/auth/dev-signup", method: "POST", body: ["email": email]); token = result.access_token; user = result.user; error = nil } catch { self.error = error.localizedDescription } }
    func loadMe(_ token: String) async { do { user = try await api.get("/me", token: token) } catch { self.error = error.localizedDescription; if let status = (error as? APIError)?.statusCode, [401,404].contains(status) { Keychain.clear(); self.token = nil } } }
    func signOut() { Keychain.clear(); token = nil; user = nil }
}
struct RootView: View {
    @Environment(SessionStore.self) private var session
    var body: some View {
        Group {
            if session.restoring { ProgressView("Opening your space…").frame(maxWidth:.infinity,maxHeight:.infinity).background(Theme.cream) }
            else if session.user == nil { WelcomeView() }
            else if session.user?.profile.complete != true || session.user?.profile.onboarding_completed != true { GuidedOnboardingView() }
            else { MainTabs() }
        }.preferredColorScheme(.light)
    }
}
struct MainTabs: View {
    @Environment(SessionStore.self) private var session
    @State private var selection = 0
    var body: some View {
        Group {
            switch selection {
            case 1: ConnectView()
            case 2: ExperiencesView()
            case 3: MessagesView(selection: $selection)
            case 4: NestView(selection: $selection)
            case 5: ActivityHubView()
            default: HomeView(selection: $selection)
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                mainOption(0, "Home", "house")
                mainOption(1, "Connect", "heart")
                mainOption(5, "Rally", "map")
                mainOption(2, "Experiences", "wineglass")
                mainOption(3, "Messages", "bubble.left.and.bubble.right")
                mainOption(4, "Nest", "house.and.flag")
            }.padding(.top, 10).padding(.bottom, 4).background(Theme.paper).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }.onAppear { selection = session.preferredTab; session.preferredTab = 0 }
    }
    private func mainOption(_ id: Int, _ title: String, _ icon: String) -> some View {
        Button { selection = id } label: {
            VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 20, weight: selection == id ? .semibold : .regular)); Text(title).font(.system(size: 9, weight: selection == id ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.75) }.foregroundStyle(selection == id ? Theme.forest : Theme.muted).frame(maxWidth: .infinity).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityAddTraits(selection == id ? [.isSelected] : []).accessibilityLabel(title)

    }
}
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showProfile = false
    @Binding var selection: Int
    @State private var introductions: [Introduction] = []
    @State private var experiences: [Experience] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(Theme.forest)
                                Text("Good to have you, \(session.user?.first_name ?? "there").").font(.system(size: 29, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                            }
                            Spacer()
                            Button { showProfile = true } label: { Image(systemName: "person.crop.circle").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.forest).padding(8) }.accessibilityLabel("Edit your profile")
                        }


                        Button { selection = 1 } label: {
                            ZStack(alignment: .bottomLeading) {
                                Image("DateNightHero").resizable().scaledToFill().frame(height: 255).clipped()
                                LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(introductions.isEmpty ? "START WITH WHAT MATTERS" : "A THOUGHTFUL INTRODUCTION").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.white.opacity(0.88))
                                    Text(introductions.isEmpty ? "Meet beyond the\nfirst impression." : "Your introduction\nis waiting.").font(.system(size: 27, weight: .medium, design: .serif)).lineSpacing(-2).foregroundStyle(.white)
                                    Text(introductions.isEmpty ? "Set the intentions that shape who you meet." : "See what you have in common.").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                                }.padding(20)
                                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 34, height: 34).background(.white.opacity(0.2), in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(16)
                            }.frame(height: 255).clipShape(RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(.plain)

                        HStack(alignment: .firstTextBaseline) {
                            Text("A good first step").font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("MADE FOR REAL LIFE").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 12) {
                            HomeActionCard(icon: "heart.text.square", title: "Know what fits", detail: "Values-led introductions", tint: Theme.blush) { selection = 1 }
                            HomeActionCard(icon: "wineglass", title: "Meet in person", detail: "Hosted dates & circles", tint: Theme.sage) { selection = 2 }
                        }

                        if let experience = experiences.first {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("COMING UP").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(Theme.forest); Spacer(); Text(displayDate(experience.starts_at)).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted) }
                                Text(experience.title).font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                                Label("\(experience.area) · \(experience.spaces_remaining) places left", systemImage: "mappin.and.ellipse").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                                Button { selection = 2 } label: { HStack { Text("Explore experiences"); Spacer(); Image(systemName: "arrow.right") }.font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.forest) }.buttonStyle(.plain).padding(.top, 2)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
                        }

                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: "house.and.flag").font(.system(size: 18, weight: .regular)).foregroundStyle(Theme.forest).frame(width: 42, height: 42).background(Theme.lilac, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text("And if it grows…").font(.system(size: 16, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                                Text("TwoNest gives couples a private space to talk through a shared future, including what living together could look like.").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted).lineSpacing(3)
                            }
                        }.padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
                        if let loadError { Text(loadError).font(.footnote).foregroundStyle(.red) }
                    }.padding(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadHome() }
            .sheet(isPresented: $showProfile) { ProfileEditorView() }
        }
    }

    private func loadHome() async {
        guard let token = session.token else { return }
        do { introductions = try await session.api.get("/introductions", token: token) } catch { loadError = error.localizedDescription }
        do { experiences = try await session.api.get("/experiences", token: token) } catch { loadError = error.localizedDescription }
    }
}
struct ProfileEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let required: Bool
    @State private var firstName = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    @State private var birthdayProvided = false
    @State private var pronouns = ""
    @State private var genderIdentity = ""
    @State private var orientation = ""
    @State private var partnerPreferences: Set<String> = []
    @State private var preferredAgeMin = 18
    @State private var preferredAgeMax = 80
    @State private var intention = "serious_dating"
    @State private var friendshipIntention = ""
    @State private var area = "East London"
    @State private var radius = 40
    @State private var bio = ""
    @State private var interests = ""
    @State private var languages = "English"
    @State private var availability = "Weekends"
    @State private var dietary = ""
    @State private var accessibility = ""
    @State private var budgetMin = 0
    @State private var budgetMax = 100
    @State private var visibility = "matches"
    @State private var discoveryPaused = false
    @State private var travelModeEnabled = false
    @State private var travelArea = ""
    @State private var travelUntil = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    init(required: Bool = false) { self.required = required }

    private var adultCutoff: Date { Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now }

    var body: some View {
        NavigationStack {
            Form {
                Section("The basics") {
                    TextField("First name", text: $firstName).textContentType(.givenName)
                    if birthdayProvided {
                        DatePicker("Date of birth · 18+", selection: $birthDate, in: ...adultCutoff, displayedComponents: .date)
                    } else {
                        Button("Add date of birth") { birthdayProvided = true }
                        Text("Your birthday is used only to confirm you’re an adult.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    TextField("Pronouns (optional)", text: $pronouns)
                    TextField("Gender (optional)", text: $genderIdentity)
                    TextField("Sexual orientation (optional)", text: $orientation)
                }
                Section("What brings you here?") {
                    Picker("Primary intention", selection: $intention) {
                        Text("Serious dating").tag("serious_dating")
                        Text("Dating and seeing what grows").tag("dating")
                        Text("Life partner").tag("life_partner")
                        Text("Friendship").tag("friendship")
                        Text("Local activities").tag("local_activities")
                        Text("Professional community").tag("professional_community")
                        Text("Preparing to live together").tag("home_together")
                    }
                    TextField("Friendship intention (optional)", text: $friendshipIntention)
                    TextField("Neighbourhood or area", text: $area)
                    Stepper("Discovery radius · \(radius) km", value: $radius, in: 5...250, step: 5)
                }
                Section("Who you’d like to meet") {
                    ForEach(["woman", "man", "non binary", "any"], id: \.self) { preference in
                        Toggle(preference == "any" ? "All genders" : preference.capitalized, isOn: Binding(get: { partnerPreferences.contains(preference) }, set: { selected in
                            if selected { if preference == "any" { partnerPreferences = ["any"] } else { partnerPreferences.remove("any"); partnerPreferences.insert(preference) } }
                            else { partnerPreferences.remove(preference) }
                        }))
                    }
                    Stepper("Minimum age · \(preferredAgeMin)", value: $preferredAgeMin, in: 18...preferredAgeMax)
                    Stepper("Maximum age · \(preferredAgeMax)", value: $preferredAgeMax, in: preferredAgeMin...120)
                }
                Section("A little more about you") {
                    TextField("A few words about yourself", text: $bio, axis: .vertical).lineLimit(3...6)
                    TextField("Interests · comma separated", text: $interests)
                    TextField("Languages · comma separated", text: $languages)
                    TextField("When you’re usually free", text: $availability)
                }
                Section("Experiences that work for you") {
                    TextField("Dietary requirements", text: $dietary)
                    TextField("Accessibility needs", text: $accessibility)
                    Stepper("Event budget · £\(budgetMin)–£\(budgetMax)", value: $budgetMax, in: budgetMin...500, step: 10)
                    Stepper("Minimum budget · £\(budgetMin)", value: $budgetMin, in: 0...budgetMax, step: 10)
                }
                Section("Privacy") {
                    Picker("Profile visibility", selection: $visibility) {
                        Text("Introductions only").tag("matches")
                        Text("Hidden from discovery").tag("private")
                    }
                    Text("Sensitive details stay private and are only used to support your preferences.").font(.footnote).foregroundStyle(Theme.muted)
                }
                if !required {
                    Section("Account") {
                        Button("Sign out", role: .destructive) { session.signOut(); dismiss() }
                    }
                }
                Section("Discovery") {
                    Toggle("Pause new introductions", isOn: $discoveryPaused)
                    Text("You can still use TwoNest and respond to introductions already in your inbox.").font(.footnote).foregroundStyle(Theme.muted)
                    Toggle("I’m travelling", isOn: $travelModeEnabled)
                    if travelModeEnabled {
                        TextField("Area you’ll be in", text: $travelArea)
                        DatePicker("Travel until", selection: $travelUntil, in: Date.now..., displayedComponents: .date)
                        Text("We use the area you enter for approximate matching. Your home area stays saved privately.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.cream)
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !required { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving || loading || firstName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let token = session.token else { loading = false; return }
        defer { loading = false }
        do {
            let value: OnboardingProfile = try await session.api.get("/onboarding", token: token)
            firstName = value.first_name
            if let raw = value.date_of_birth, let parsed = Self.dateFormatter.date(from: raw) { birthDate = parsed; birthdayProvided = true }
            pronouns = value.pronouns; genderIdentity = value.gender_identity; orientation = value.sexual_orientation
            intention = value.intention; friendshipIntention = value.friendship_intention; area = value.area
            partnerPreferences = Set(value.dating_preferences); preferredAgeMin = value.preferred_age_min ?? 18; preferredAgeMax = value.preferred_age_max ?? 80
            radius = value.search_radius_km; bio = value.bio; interests = value.interests.joined(separator: ", ")
            languages = value.languages.joined(separator: ", "); availability = value.availability.joined(separator: ", ")
            dietary = value.dietary_requirements.joined(separator: ", "); accessibility = value.accessibility_needs.joined(separator: ", ")
            budgetMin = value.event_budget_min; budgetMax = max(value.event_budget_max, value.event_budget_min); visibility = value.visibility
            discoveryPaused = value.discovery_paused
            travelArea = value.travel_mode_area
            if let raw = value.travel_mode_until, let parsed = Self.dateFormatter.date(from: raw), parsed >= Calendar.current.startOfDay(for: .now) {
                travelModeEnabled = true
                travelUntil = parsed
            }
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let token = session.token else { return }
        guard !partnerPreferences.isEmpty else { error = "Choose who you’d like to meet."; return }
        guard birthdayProvided else { error = "Add your date of birth to confirm you’re at least 18."; return }
        saving = true; error = nil
        defer { saving = false }
        let payload: [String: Any] = [
            "first_name": firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            "date_of_birth": Self.dateFormatter.string(from: birthDate),
            "pronouns": pronouns, "gender_identity": genderIdentity,
            "sexual_orientation": orientation, "intention": intention,
            "dating_preferences": partnerPreferences.sorted(), "preferred_age_min": preferredAgeMin, "preferred_age_max": preferredAgeMax,
            "friendship_intention": friendshipIntention, "area": area,
            "search_radius_km": radius, "bio": bio,
            "interests": Self.csv(interests), "languages": Self.csv(languages),
            "availability": Self.csv(availability), "dietary_requirements": Self.csv(dietary),
            "accessibility_needs": Self.csv(accessibility),
            "event_budget_min": budgetMin, "event_budget_max": budgetMax,
            "visibility": visibility,
            "discovery_paused": discoveryPaused,
            "travel_mode_area": travelModeEnabled ? travelArea.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            "travel_mode_until": travelModeEnabled ? Self.dateFormatter.string(from: travelUntil) : "",
        ]
        if travelModeEnabled && travelArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Add the area you’ll be visiting to turn on travel mode."
            saving = false
            return
        }
        do {
            let _: OnboardingProfile = try await session.api.send("/onboarding", method: "PATCH", body: payload, token: token)
            session.user = try await session.api.get("/me", token: token)
            if !required { dismiss() }
        } catch { self.error = error.localizedDescription }
    }

    private static func csv(_ value: String) -> [String] { value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private static var dateFormatter: DateFormatter { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0); return formatter }
}
struct ConnectView: View {
    @Environment(SessionStore.self) private var session
    @State private var introductions: [Introduction] = []
    @State private var answeredPreferences = 0
    @State private var loading = true
    @State private var message: String?
    @State private var showingQuestionnaire = false
    @State private var showingDiscovery = false
    @State private var refreshing = false
    @State private var selectedSafetyTarget: Introduction?
    @State private var reportingTarget: Member?
    @State private var showingCircles = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("YOUR NEXT GOOD THING").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.5).foregroundStyle(Theme.berry)
                        HStack(alignment:.firstTextBaseline) { Text("A little chemistry.").font(.system(size:30,weight:.medium,design:.serif)).foregroundStyle(Theme.ink); Spacer(); Text("\(introductions.count) NEW").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(Theme.plum).padding(.horizontal,10).padding(.vertical,7).background(Theme.lilac.opacity(0.55),in:Capsule()) }
                        Text("Thoughtful introductions, chosen around what matters to you.").font(.system(size:14,design:.rounded)).foregroundStyle(Theme.muted)
                        Text("Thoughtful introductions").font(.system(size: 23, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                        HStack(spacing:10) {
                            Button { showingQuestionnaire = true } label: { Label("Compatibility",systemImage:"slider.horizontal.3").font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(Theme.plum).padding(.horizontal,13).padding(.vertical,10).background(.white,in:Capsule()) }.buttonStyle(.plain)
                            Button { if answeredPreferences < 3 { showingQuestionnaire = true } else { Task { await refresh() } } } label: { Label(refreshing ? "Finding…" : (answeredPreferences < 3 ? "Answer 3 questions" : "Find introductions"),systemImage:answeredPreferences < 3 ? "list.bullet.rectangle" : "sparkles").font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(.white).padding(.horizontal,13).padding(.vertical,10).background(Theme.forest,in:Capsule()) }.buttonStyle(.plain).disabled(refreshing)
                        }
                        HStack { Button { showingDiscovery = true } label: { Label("Who you meet", systemImage: "slider.horizontal.3").font(.system(size: 12, weight: .semibold)).padding(12).background(Theme.paper, in: Capsule()) }; Spacer() }
                        Button { showingCircles = true } label: { Label("Find your Circle",systemImage:"person.3.fill").font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(Theme.forest).padding(.horizontal,13).padding(.vertical,10).background(Theme.sage.opacity(0.7),in:Capsule()) }.buttonStyle(.plain)
                        ForEach(introductions) { intro in
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    ZStack(alignment:.topLeading) {
                                        RoundedRectangle(cornerRadius:22).fill(LinearGradient(colors:[Theme.lilac,Theme.blush,Theme.gold.opacity(0.75)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(height:174)
                                        Circle().stroke(.white.opacity(0.55),lineWidth:20).frame(width:170).offset(x:190,y:-35)
                                        Circle().fill(Theme.coral.opacity(0.17)).frame(width:100).offset(x:235,y:92)
                                        VStack(alignment:.leading,spacing:0) {
                                            HStack { Label("INTRODUCED WITH CONTEXT",systemImage:"quote.bubble.fill").font(.system(size:9,weight:.bold,design:.rounded)).tracking(0.5).foregroundStyle(Theme.plum).padding(.horizontal,10).padding(.vertical,8).background(.white.opacity(0.82),in:Capsule()); Spacer() }
                                            Spacer()
                                            HStack(alignment:.bottom) { ZStack { Circle().fill(LinearGradient(colors:[Theme.coral,Theme.berry],startPoint:.topLeading,endPoint:.bottomTrailing)); Text(String(intro.candidate.first_name.prefix(1))).font(.system(size:31,weight:.medium,design:.serif)).foregroundStyle(.white) }.frame(width:65,height:65).overlay(Circle().stroke(.white,lineWidth:3)); Spacer(); Image(systemName:"heart.fill").font(.system(size:20)).foregroundStyle(.white.opacity(0.85)).padding(12).background(.white.opacity(0.24),in:Circle()) }
                                        }.padding(15)
                                    }.clipShape(RoundedRectangle(cornerRadius:22))
                                    VStack(alignment:.leading,spacing:5) { HStack(alignment:.firstTextBaseline,spacing:8) { Text(intro.candidate.first_name).font(.system(size:26,weight:.medium,design:.serif)).foregroundStyle(Theme.ink); Spacer(); Menu { Button("Report member",systemImage:"exclamationmark.bubble") { reportingTarget = intro.candidate }; Button("Block member",systemImage:"hand.raised.fill",role:.destructive) { selectedSafetyTarget = intro } } label: { Image(systemName:"ellipsis").font(.system(size:17,weight:.bold)).foregroundStyle(Theme.muted).padding(8).contentShape(Rectangle()) }.accessibilityLabel("Safety options for \(intro.candidate.first_name)") }; Label(intro.candidate.profile.area,systemImage:"mappin.and.ellipse").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Theme.muted) }
                                    Text(intro.candidate.profile.bio).font(.system(size:14,design:.rounded)).foregroundStyle(Theme.ink).lineSpacing(3)
                                    Text(intro.candidate.profile.interests.prefix(3).joined(separator:"  ·  ")).font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(Theme.plum).padding(.horizontal,12).padding(.vertical,9).background(Theme.lilac.opacity(0.42),in:Capsule())
                                    VStack(alignment:.leading,spacing:6) { Text("WHY THIS INTRODUCTION").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1.1).foregroundStyle(Theme.plum); Text(intro.reasons).font(.system(size:13,design:.rounded)).foregroundStyle(Theme.ink).lineSpacing(3) }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(Theme.cream,in:RoundedRectangle(cornerRadius:16))
                                    HStack {
                                        Button { Task { await decide(intro, "passed") } } label: { Image(systemName:"xmark").font(.system(size:15,weight:.bold)).foregroundStyle(Theme.muted).frame(width:50,height:50).background(Theme.cream,in:Circle()) }.accessibilityLabel("Pass")
                                        Spacer()
                                        Button { Task { await decide(intro, "interested") } } label: { Label("I’d love to meet",systemImage:"heart.fill").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(.white).padding(.horizontal,18).frame(height:50).background(LinearGradient(colors:[Theme.berry,Theme.coral],startPoint:.leading,endPoint:.trailing),in:Capsule()) }.buttonStyle(.plain)
                                    }.padding(.top,3)
                                }
                            }
                        }
                        if let message { Text(message).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(Theme.plum).padding(13).background(Theme.lilac.opacity(0.45),in:RoundedRectangle(cornerRadius:14)).accessibilityLabel(message) }
                        if introductions.isEmpty && !loading { Card { VStack(alignment:.leading,spacing:11) { Text("A better introduction starts with you.").font(.system(size:20,weight:.medium,design:.serif)).foregroundStyle(Theme.ink); Text(answeredPreferences < 3 ? "Share a few things that matter to you. After three answers, we can start making introductions and show you why they might fit." : "There are no introductions waiting right now. Your preferences are saved, so check back after the next matching round.").font(.system(size:13,design:.rounded)).foregroundStyle(Theme.muted).lineSpacing(3); if answeredPreferences < 3 { Button { showingQuestionnaire = true } label: { Label("Set your preferences",systemImage:"arrow.right").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(Theme.forest) }.buttonStyle(.plain).padding(.top,3) } } } }
                    }.padding(20)
                }
                if loading { ProgressView().tint(Theme.forest) }
            }
            .toolbar(.hidden,for:.navigationBar)
            .task { await load() }
            .sheet(isPresented:$showingDiscovery) { ProfileEditorView() }
            .sheet(isPresented:$showingQuestionnaire) { QuestionnaireView { Task { await preferencesSaved() } } }
            .sheet(isPresented:$showingCircles) { CircleHubView() }
            .sheet(item:$reportingTarget) { member in SafetyReportSheet(member:member) { message = $0 } }
            .confirmationDialog("Block \(selectedSafetyTarget?.candidate.first_name ?? "this member")?",isPresented:Binding(get:{selectedSafetyTarget != nil},set:{if !$0{selectedSafetyTarget=nil}}),titleVisibility:.visible) {
                Button("Block member",role:.destructive) { if let intro=selectedSafetyTarget { Task { await block(intro) } }; selectedSafetyTarget=nil }
                Button("Cancel",role:.cancel) { selectedSafetyTarget=nil }
            } message: { Text("They won’t appear in your recommendations or conversations. They won’t be notified.") }
        }
    }

    func load() async {
        guard let token = session.token else { loading = false; return }
        defer { loading = false }
        do { introductions = try await session.api.get("/introductions", token: token) }
        catch { message = error.localizedDescription }
        do { let form: QuestionnaireForm = try await session.api.get("/questionnaire", token: token); answeredPreferences = form.answers.filter { !$0.is_private }.count }
        catch { message = error.localizedDescription }
    }

    func preferencesSaved() async {
        guard let token = session.token else { return }
        do {
            let form: QuestionnaireForm = try await session.api.get("/questionnaire", token: token)
            answeredPreferences = form.answers.filter { !$0.is_private }.count
            if answeredPreferences >= 3 { await refresh() }
            else { message = "Saved. Add \(3 - answeredPreferences) more answer\(answeredPreferences == 2 ? "" : "s") to start receiving introductions." }
        } catch { message = error.localizedDescription }
    }

    func refresh() async {
        guard let token = session.token else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let result: IntroductionRefreshResponse = try await session.api.send("/introductions/refresh", method:"POST", token:token)
            message = result.created_count > 0 ? "\(result.created_count) thoughtful introductions are ready." : "You’re all caught up for this week. Update your preferences to shape what comes next."
            await load()
        } catch { message = error.localizedDescription }
    }

    func decide(_ intro: Introduction, _ value: String) async {
        guard let token = session.token else { return }
        do {
            let result: DecisionResponse = try await session.api.send("/introductions/\(intro.id)/decision", method: "POST", body: ["decision": value], token: token)
            message = result.mutual ? "It’s mutual. Your conversation is open." : "Your choice has been saved privately."
            if value == "passed" { introductions.removeAll { $0.id == intro.id } }
        } catch { message = error.localizedDescription }
    }

    func block(_ intro: Introduction) async {
        guard let token=session.token else{return}
        do { let _:MemberBlockResponse=try await session.api.send("/members/\(intro.candidate.id)/block",method:"POST",token:token); introductions.removeAll{$0.candidate.id==intro.candidate.id}; message="\(intro.candidate.first_name) has been blocked." }
        catch { message=error.localizedDescription }
    }
}

struct SafetyReportSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let memberID: String
    let firstName: String
    let onSent: (String) -> Void
    init(member: Member, onSent: @escaping (String) -> Void) { self.memberID = member.id; self.firstName = member.first_name; self.onSent = onSent }
    init(memberID: String, firstName: String, onSent: @escaping (String) -> Void) { self.memberID = memberID; self.firstName = firstName; self.onSent = onSent }
    @State private var category = "Harassment"
    @State private var details = ""
    @State private var error: String?
    @State private var sending = false
    private let categories = ["Harassment", "Inappropriate content", "Impersonation", "Scam or spam", "Safety concern", "Other"]
    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    Picker("Reason",selection:$category) { ForEach(categories,id:\.self){Text($0)} }
                    TextEditor(text:$details).frame(minHeight:140).accessibilityLabel("Report details")
                    Text("Share at least 10 characters. Your report is private.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Report \(firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button(sending ? "Sending…":"Send"){Task{await submit()}}.disabled(sending || details.trimmingCharacters(in:.whitespacesAndNewlines).count<10)}
            }
        }
    }
    private func submit() async {
        guard let token=session.token else{return};sending=true;defer{sending=false}
        do { let _:SafetyReportResponse=try await session.api.send("/safety/reports",method:"POST",body:["subject_id":memberID,"category":category,"details":details],token:token);onSent("Your private report was submitted for review.");dismiss() }
        catch { self.error=error.localizedDescription }
    }
}
struct CircleHubView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var circles:[CircleCard]=[]
    @State private var error:String?
    @State private var loading=true
    var body:some View {
        NavigationStack { ZStack { Theme.cream.ignoresSafeArea(); ScrollView { VStack(alignment:.leading,spacing:18) {
            Text("GOOD COMPANY, GROWN TOGETHER").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.4).foregroundStyle(Theme.berry)
            Text("Find your people.").font(.system(size:32,weight:.medium,design:.serif)).foregroundStyle(Theme.ink)
            Text("Small, guided groups make it easier to turn shared interests into real friendships.").font(.system(size:14,design:.rounded)).foregroundStyle(Theme.muted).lineSpacing(3)
            ForEach(circles) { circle in Card { VStack(alignment:.leading,spacing:12) {
                HStack { Label(circle.theme.replacingOccurrences(of:"_",with:" ").uppercased(),systemImage:"person.3.fill").font(.system(size:9,weight:.bold,design:.rounded)).tracking(0.8).foregroundStyle(Theme.forest).padding(.horizontal,10).padding(.vertical,8).background(Theme.sage.opacity(0.55),in:Capsule());Spacer();Text("WEEK \(circle.week) OF 4").font(.system(size:9,weight:.bold,design:.rounded)).foregroundStyle(Theme.plum) }
                Text(circle.title).font(.system(size:23,weight:.medium,design:.serif)).foregroundStyle(Theme.ink)
                Label("\(circle.area) · \(circle.member_count) of \(circle.max_members) members",systemImage:"mappin.and.ellipse").font(.system(size:12,design:.rounded)).foregroundStyle(Theme.muted)
                HStack(spacing:7){ForEach(1...4,id:\.self){week in Capsule().fill(week<=circle.week ? Theme.berry:Theme.line).frame(height:4)}}
                if circle.joined { NavigationLink { CircleDetailView(circle:circle) } label:{Label("Open your Circle",systemImage:"arrow.right").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(.white).frame(maxWidth:.infinity,minHeight:46).background(Theme.plum,in:Capsule())}.buttonStyle(.plain) }
                else { Button{Task{await join(circle)}}label:{Label("Join this Circle",systemImage:"person.badge.plus").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(.white).frame(maxWidth:.infinity,minHeight:46).background(Theme.plum,in:Capsule())}.buttonStyle(.plain).disabled(circle.member_count>=circle.max_members) }
            } } }
            if circles.isEmpty && !loading { Card { Text("New groups are forming soon. Check back for a Circle that feels like you.").font(.system(size:14,design:.rounded)).foregroundStyle(Theme.muted) } }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }.padding(20) };if loading{ProgressView().tint(Theme.forest)} }.navigationTitle("Circles").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}}}.task{await load()} }
    }
    private func load() async { defer{loading=false};do{circles=try await session.api.get("/circles",token:session.token ?? "")}catch{self.error=error.localizedDescription} }
    private func join(_ circle:CircleCard) async { do{let value:CircleCard=try await session.api.send("/circles/\(circle.id)/join",method:"POST",token:session.token ?? "");if let i=circles.firstIndex(where:{$0.id==circle.id}){circles[i]=value}}catch{self.error=error.localizedDescription} }
}

struct CircleDetailView:View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let circle:CircleCard
    @State private var detail:CircleDetail?
    @State private var answer=""
    @State private var selectedOptions:Set<String>=[]
    @State private var voiceFile:URL?
    @State private var draft=""
    @State private var error:String?
    @State private var saving=false
    @State private var planSheet=false
    @State private var leaveConfirm=false
    var body:some View {
        ZStack { Theme.cream.ignoresSafeArea();if let detail { ScrollView { VStack(alignment:.leading,spacing:17) {
            VStack(alignment:.leading,spacing:10){Label("\(detail.area.uppercased()) · WEEK \(detail.week) OF 4",systemImage:"person.3.fill").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(.white.opacity(0.82));Text(detail.title).font(.system(size:29,weight:.medium,design:.serif)).foregroundStyle(.white);Text("A thoughtful little group, at a human pace.").font(.system(size:13,design:.rounded)).foregroundStyle(.white.opacity(0.86));HStack(spacing:5){ForEach(1...4,id:\.self){w in Capsule().fill(w<=detail.week ? Theme.gold:.white.opacity(0.3)).frame(height:4)}}}.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(LinearGradient(colors:[Theme.forest,Theme.plum],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:24))
            if let prompt=detail.current_prompt { Card { VStack(alignment:.leading,spacing:11) {
                Text("THIS WEEK’S PROMPT").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(Theme.berry);Text(prompt.title).font(.system(size:22,weight:.medium,design:.serif)).foregroundStyle(Theme.ink);Text(prompt.body).font(.system(size:14,design:.rounded)).foregroundStyle(Theme.muted).lineSpacing(3)
                if prompt.prompt_type=="voice"{VStack(alignment:.leading,spacing:9){Label("Voice prompt · speak for up to 45 seconds",systemImage:"waveform").font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(Theme.plum);CircleVoiceRecorder(fileURL:$voiceFile);if let key=detail.my_response?.voice_asset_key{CircleVoicePlayback(circleID:circle.id,assetKey:key)}}}
                if prompt.prompt_type == "poll" {
                    VStack(spacing:8) {
                        ForEach(prompt.options ?? [],id:\.self) { option in
                            Button {
                                if selectedOptions.contains(option) { selectedOptions.remove(option) }
                                else if selectedOptions.count < 2 { selectedOptions.insert(option) }
                            } label: {
                                HStack {
                                    Text(option).font(.system(size:13,weight:.semibold,design:.rounded))
                                    Spacer()
                                    Text("\(prompt.poll_counts?[option] ?? 0)").font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(Theme.muted)
                                    Image(systemName:selectedOptions.contains(option) ? "checkmark.circle.fill":"circle").foregroundStyle(selectedOptions.contains(option) ? Theme.berry:Theme.muted)
                                }
                                .foregroundStyle(Theme.ink).padding(12)
                                .background(selectedOptions.contains(option) ? Theme.blush:Theme.cream,in:RoundedRectangle(cornerRadius:13))
                            }.buttonStyle(.plain)
                        }
                        Text("Choose up to two · votes are visible to your Circle").font(.system(size:10,design:.rounded)).foregroundStyle(Theme.muted)
                    }
                } else {
                    TextEditor(text:$answer).frame(minHeight:86).scrollContentBackground(.hidden).padding(9).background(Theme.cream,in:RoundedRectangle(cornerRadius:14)).accessibilityLabel("Your Circle prompt response")
                }
                Button{Task{await submitResponse(prompt)}}label:{Label(saving ? "Saving…":"Share with your Circle",systemImage:"paperplane.fill").font(.system(size:12,weight:.bold,design:.rounded)).foregroundStyle(.white).frame(maxWidth:.infinity,minHeight:44).background(Theme.berry,in:Capsule())}.buttonStyle(.plain).disabled(saving || (answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && voiceFile == nil && selectedOptions.isEmpty))
            } } }
            if !detail.group_responses.isEmpty { Card { VStack(alignment:.leading,spacing:11){Text("A FEW SHARED THOUGHTS").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(Theme.plum);ForEach(detail.group_responses){item in VStack(alignment:.leading,spacing:4){Text(item.first_name).font(.system(size:12,weight:.bold,design:.rounded)).foregroundStyle(Theme.ink);if !item.response_text.isEmpty{Text(item.response_text).font(.system(size:13,design:.rounded)).foregroundStyle(Theme.muted)};if !item.selected_options.isEmpty{Text(item.selected_options.joined(separator:" · ")).font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(Theme.berry)};if let key=item.voice_asset_key{CircleVoicePlayback(circleID:circle.id,assetKey:key)}}}}} }
            Card { VStack(alignment:.leading,spacing:11){HStack{Text("Your Circle chat").font(.system(size:20,weight:.medium,design:.serif)).foregroundStyle(Theme.ink);Spacer();Text("\(detail.members.count) MEMBERS").font(.system(size:9,weight:.bold,design:.rounded)).foregroundStyle(Theme.muted)};ForEach(detail.messages.suffix(30)){m in HStack(alignment:.top,spacing:8){Text(m.first_name).font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(Theme.berry).frame(width:52,alignment:.leading);Text(m.body).font(.system(size:13,design:.rounded)).foregroundStyle(Theme.ink)}.padding(.vertical,3)};HStack(spacing:8){TextField("Share something with the group",text:$draft,axis:.vertical).lineLimit(1...3).font(.system(size:13,design:.rounded)).padding(10).background(Theme.cream,in:RoundedRectangle(cornerRadius:14));Button{Task{await sendMessage()}}label:{Image(systemName:"arrow.up").font(.system(size:14,weight:.bold)).foregroundStyle(.white).frame(width:40,height:40).background(Theme.plum,in:Circle())}.disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityLabel("Send Circle message")}} }
            if detail.week>=3 { VStack(alignment:.leading,spacing:12){HStack{Text("Plan a meet-up").font(.system(size:21,weight:.medium,design:.serif)).foregroundStyle(Theme.ink);Spacer();Button{planSheet=true}label:{Image(systemName:"plus").foregroundStyle(Theme.berry).padding(10).background(Theme.blush,in:Circle())}.accessibilityLabel("Suggest a Circle meet-up")};ForEach(detail.meeting_plans){p in Card{VStack(alignment:.leading,spacing:8){Text(p.title).font(.system(size:17,weight:.medium,design:.serif)).foregroundStyle(Theme.ink);Label("\(p.venue) · \(p.area)",systemImage:"mappin.and.ellipse").font(.system(size:12,design:.rounded)).foregroundStyle(Theme.muted);Text(Self.date(p.starts_at)).font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(Theme.plum);HStack{Label("\(p.yes_count) going",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(Theme.forest);Spacer();Button(p.my_vote == true ? "You’re in":"I’m in"){Task{await vote(p,true)}}.buttonStyle(OutlineButton());Button("Can’t"){Task{await vote(p,false)}}.font(.caption).foregroundStyle(Theme.muted)}}}};if detail.meeting_plans.isEmpty{Text("Suggest a relaxed local plan when an idea comes to you.").font(.system(size:13,design:.rounded)).foregroundStyle(Theme.muted)}} }
            if let error{Text(error).font(.footnote).foregroundStyle(.red)}
            Button("Leave this Circle",systemImage:"rectangle.portrait.and.arrow.right",role:.destructive){leaveConfirm=true}.font(.system(size:12,weight:.semibold,design:.rounded)).frame(maxWidth:.infinity).padding(.top,4)
        }.padding(18).padding(.bottom,18)} }else{ProgressView().tint(Theme.forest)} }
        .navigationTitle("Circle").navigationBarTitleDisplayMode(.inline).task{await load()}
        .sheet(isPresented:$planSheet){CircleMeetingPlanSheet(area:circle.area){values in Task{await createPlan(values)}}}
        .confirmationDialog("Leave \(circle.title)?",isPresented:$leaveConfirm,titleVisibility:.visible){Button("Leave Circle",role:.destructive){Task{await leave()}};Button("Stay",role:.cancel){}}
    }
    private func load() async {do{detail=try await session.api.get("/circles/\(circle.id)",token:session.token ?? "");answer=detail?.my_response?.response_text ?? "";selectedOptions=Set(detail?.my_response?.selected_options ?? [])}catch{self.error=error.localizedDescription}}
    private func submitResponse(_ prompt:CirclePrompt) async {saving=true;defer{saving=false};do{if let voiceFile{let data=try Data(contentsOf:voiceFile);let _:CircleResponseResult=try await session.api.sendAudio("/circles/\(circle.id)/prompts/\(prompt.id)/voice-note",data:data,token:session.token ?? "");try? FileManager.default.removeItem(at:voiceFile)};if !answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !selectedOptions.isEmpty{let _:CircleResponseResult=try await session.api.send("/circles/\(circle.id)/responses",method:"POST",body:["response_text":answer,"selected_options":Array(selectedOptions)],token:session.token ?? "")};voiceFile=nil;await load()}catch{self.error=error.localizedDescription}}
    private func sendMessage() async {let body=draft.trimmingCharacters(in:.whitespacesAndNewlines);guard !body.isEmpty else{return};do{let _:CircleChatMessage=try await session.api.send("/circles/\(circle.id)/messages",method:"POST",body:["body":body],token:session.token ?? "");draft="";await load()}catch{self.error=error.localizedDescription}}
    private func createPlan(_ values:CircleMeetingPlanDraft) async {do{let _:CircleMeetingPlan=try await session.api.send("/circles/\(circle.id)/meeting-plans",method:"POST",body:["title":values.title,"venue":values.venue,"area":values.area,"starts_at":ISO8601DateFormatter().string(from:values.startsAt)],token:session.token ?? "");await load()}catch{self.error=error.localizedDescription}}
    private func vote(_ plan:CircleMeetingPlan,_ attending:Bool) async {do{let _:CircleMeetingVoteResult=try await session.api.send("/circles/\(circle.id)/meeting-plans/\(plan.id)/vote",method:"POST",body:["attending":attending],token:session.token ?? "");await load()}catch{self.error=error.localizedDescription}}
    private func leave() async {do{let _:CircleLeftResponse=try await session.api.send("/circles/\(circle.id)/leave",method:"POST",token:session.token ?? "");dismiss()}catch{self.error=error.localizedDescription}}
    private static func date(_ value:String)->String{let f=ISO8601DateFormatter();guard let d=f.date(from:value)else{return value};return d.formatted(date:.abbreviated,time:.shortened)}
}

struct CircleVoiceRecorder:View {
    @Binding var fileURL:URL?
    @State private var recorder:AVAudioRecorder?
    @State private var recording=false
    @State private var error:String?
    var body:some View{VStack(alignment:.leading,spacing:6){HStack(spacing:10){Button{if recording{stop()}else{Task{await start()}}}label:{Label(recording ? "Stop recording":"Record voice note",systemImage:recording ? "stop.fill":"mic.fill").font(.system(size:12,weight:.bold,design:.rounded)).foregroundStyle(recording ? Theme.berry:Theme.plum).padding(.horizontal,13).padding(.vertical,10).background(Theme.lilac.opacity(0.42),in:Capsule())}.buttonStyle(.plain);if fileURL != nil{Button("Discard",systemImage:"trash"){if let fileURL{try? FileManager.default.removeItem(at:fileURL)};self.fileURL=nil}.font(.caption).foregroundStyle(Theme.muted)}};if recording{Text("Recording · max 45 seconds").font(.caption).foregroundStyle(Theme.berry)};if let error{Text(error).font(.caption).foregroundStyle(.red)}}}
    private func start() async {
        let allowed=await withCheckedContinuation{continuation in AVAudioApplication.requestRecordPermission{continuation.resume(returning:$0)}}
        guard allowed else{error="Microphone access is needed to record a voice note.";return}
        do{let session=AVAudioSession.sharedInstance();try session.setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker]);try session.setActive(true);let url=FileManager.default.temporaryDirectory.appendingPathComponent("circle-\(UUID().uuidString).m4a");let settings:[String:Any]=[AVFormatIDKey:Int(kAudioFormatMPEG4AAC),AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:64000];let audio=try AVAudioRecorder(url:url,settings:settings);audio.prepareToRecord();audio.record(forDuration:45);recorder=audio;fileURL=url;recording=true;error=nil;Task{try? await Task.sleep(for:.seconds(45));if recording{stop()}}}catch{self.error=error.localizedDescription}
    }
    private func stop(){recorder?.stop();recording=false;try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
}

struct CircleVoicePlayback:View {
    @Environment(SessionStore.self) private var session
    let circleID:String
    let assetKey:String
    @State private var player:AVAudioPlayer?
    @State private var loading=false
    @State private var error:String?
    var body:some View{VStack(alignment:.leading,spacing:3){Button{Task{await play()}}label:{Label(loading ? "Loading…":"Play voice note",systemImage:loading ? "hourglass":"play.circle.fill").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(Theme.plum)}.disabled(loading);if let error{Text(error).font(.caption).foregroundStyle(.red)}}}
    private func play() async {loading=true;defer{loading=false};do{let data=try await session.api.getAudio("/circles/\(circleID)/voice-notes/\(assetKey)",token:session.token ?? "");let audio=try AVAudioPlayer(data:data);player=audio;audio.play()}catch{self.error=error.localizedDescription}}
}

struct CircleMeetingPlanDraft{let title:String;let venue:String;let area:String;let startsAt:Date}
struct CircleMeetingPlanSheet:View {
    @Environment(\.dismiss) private var dismiss
    let area:String
    let onCreate:(CircleMeetingPlanDraft)->Void
    @State private var title="Coffee and a walk"
    @State private var venue=""
    @State private var neighbourhood=""
    @State private var startsAt=Calendar.current.date(byAdding:.day,value:4,to:.now) ?? .now
    var body:some View{NavigationStack{Form{Section("A relaxed group plan"){TextField("Plan name",text:$title);TextField("Venue",text:$venue);TextField("Neighbourhood",text:$neighbourhood);DatePicker("Date and time",selection:$startsAt,in:Date.now...)};Section{Text("Keep the first meet-up public and easy to reach. Share contact details only if you choose.").font(.footnote).foregroundStyle(Theme.muted)}}.navigationTitle("Suggest a meet-up").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Suggest"){onCreate(CircleMeetingPlanDraft(title:title,venue:venue,area:neighbourhood,startsAt:startsAt));dismiss()}.disabled(title.count<3 || venue.count<2 || neighbourhood.count<2)}}.onAppear{neighbourhood=area}}}
}

struct CircleLeftResponse:Codable{let left:Bool}

struct QuestionnaireDraft {
    var value: APIJSONValue?
    var importance = 1
    var dealBreaker = false
    var isPrivate = false

    var isAnswered: Bool {
        guard let value else { return false }
        switch value {
        case .null: return false
        case .string(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let items): return !items.isEmpty
        default: return true
        }
    }
}

struct QuestionnaireAnswerRow: View {
    let question: QuestionnaireQuestion
    @Binding var draft: QuestionnaireDraft
    private var options: [String] { question.options ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.prompt).font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Theme.ink).fixedSize(horizontal:false,vertical:true)
            answerControl
            Picker("How much does this matter?", selection: $draft.importance) {
                Text("A little").tag(1); Text("Some").tag(2); Text("A lot").tag(3)
            }.font(.system(size:12,design:.rounded))
            Toggle("Keep my answer private", isOn: $draft.isPrivate).font(.system(size:12,design:.rounded))
            Toggle("This is important for compatibility", isOn: $draft.dealBreaker).font(.system(size:12,design:.rounded))
        }.padding(.vertical,7).tint(Theme.plum)
    }

    @ViewBuilder private var answerControl: some View {
        switch question.response_type {
        case "single_select":
            Picker("Choose an answer", selection: Binding<String>(get: { draft.value?.stringValue ?? "" }, set: { draft.value = $0.isEmpty ? nil : .string($0) })) {
                Text("Choose an answer").tag("")
                ForEach(options,id:\.self) { Text($0).tag($0) }
            }.font(.system(size:13,design:.rounded))
        case "multiple_select":
            VStack(alignment:.leading,spacing:7) {
                ForEach(options,id:\.self) { option in
                    Toggle(option,isOn:Binding(get:{draft.value?.arrayValue?.contains(option) ?? false},set:{isOn in
                        var selected=draft.value?.arrayValue ?? []
                        if isOn && !selected.contains(option){selected.append(option)}
                        if !isOn{selected.removeAll{$0==option}}
                        draft.value=selected.isEmpty ? nil : .array(selected.map(APIJSONValue.string))
                    })).font(.system(size:12,design:.rounded))
                }
            }
        case "scale":
            Picker("Your answer",selection:Binding<Int>(get:{draft.value?.integerValue ?? ((question.minimum ?? 1)+(question.maximum ?? 5))/2},set:{draft.value = .integer($0)})) {
                ForEach((question.minimum ?? 1)...(question.maximum ?? 5),id:\.self){Text("\($0)").tag($0)}
            }.pickerStyle(.segmented).accessibilityLabel(question.prompt)
        case "free_text":
            TextField("Your answer",text:Binding<String>(get:{draft.value?.stringValue ?? ""},set:{draft.value = $0.isEmpty ? nil : .string($0)}),axis:.vertical).lineLimit(2...5).textInputAutocapitalization(.sentences).font(.system(size:13,design:.rounded))
        case "ranking":
            VStack(alignment:.leading,spacing:7) {
                Text("Tap choices in the order you prefer.").font(.system(size:11,design:.rounded)).foregroundStyle(Theme.muted)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:7){
                    ForEach(options,id:\.self){option in
                        let selected=draft.value?.arrayValue ?? []
                        let rank=selected.firstIndex(of:option).map{$0+1}
                        Button {
                            var next=selected
                            if let index=next.firstIndex(of:option){next.remove(at:index)}else{next.append(option)}
                            draft.value=next.isEmpty ? nil : .array(next.map(APIJSONValue.string))
                        } label: {
                            HStack(spacing:6){if let rank{Text("\(rank)").fontWeight(.bold)};Text(option).lineLimit(1).minimumScaleFactor(0.8);Spacer(minLength:0)}.font(.system(size:11,design:.rounded)).foregroundStyle(rank == nil ? Theme.ink : .white).padding(.horizontal,10).frame(minHeight:37).background(rank == nil ? Theme.cream : Theme.plum,in:RoundedRectangle(cornerRadius:12))
                        }.buttonStyle(.plain)
                    }
                }
            }
        default:
            Text("This question type is not available yet.").font(.footnote).foregroundStyle(Theme.muted)
        }
    }
}

struct QuestionnaireView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var groups: [QuestionnaireGroup] = []
    @State private var drafts: [String: QuestionnaireDraft] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if loading { ProgressView("Loading your questions…").frame(maxWidth:.infinity,alignment:.center) }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.questions) { question in
                            QuestionnaireAnswerRow(question:question,draft:draftBinding(question.id))
                        }
                    }
                }
                Section {
                    Text("Your answers shape thoughtful introductions. Private answers never appear on your profile. You can skip anything and change your answers any time.").font(.system(size:12,design:.rounded)).foregroundStyle(Theme.muted)
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.cream).tint(Theme.plum)
            .navigationTitle("Compatibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Close"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button(saving ? "Saving…":"Save"){Task{await save()}}.disabled(saving || loading)}
            }
            .task { await load() }
        }
    }

    private func draftBinding(_ questionID:String)->Binding<QuestionnaireDraft>{
        Binding(get:{drafts[questionID] ?? QuestionnaireDraft(value:nil)},set:{drafts[questionID]=$0})
    }

    private func load() async {
        guard let token=session.token else{loading=false;return}
        defer{loading=false}
        do {
            let form:QuestionnaireForm=try await session.api.get("/questionnaire",token:token)
            groups=form.groups
            for answer in form.answers{drafts[answer.question_id]=QuestionnaireDraft(value:answer.value,importance:answer.importance,dealBreaker:answer.deal_breaker,isPrivate:answer.is_private)}
        } catch { self.error=error.localizedDescription }
    }

    private func save() async {
        guard let token=session.token else{return}
        let answers:[[String:Any]]=drafts.compactMap{questionID,draft in
            guard draft.isAnswered,let value=draft.value else{return nil}
            return ["question_id":questionID,"value":value.foundationValue,"importance":draft.importance,"deal_breaker":draft.dealBreaker,"is_private":draft.isPrivate]
        }
        guard !answers.isEmpty else{error="Answer a few questions before saving.";return}
        saving=true;error=nil;defer{saving=false}
        do {
            let _:QuestionnaireSavedResponse=try await session.api.send("/questionnaire/answers",method:"PUT",body:["answers":answers],token:token)
            dismiss();onSaved()
        } catch { self.error=error.localizedDescription }
    }
}
struct ExperiencesView: View {
    @Environment(SessionStore.self) private var session
    @State private var items: [Experience] = []
    @State private var booking: BookingResponse?
    @State private var checkedIn = false
    @State private var checkedOut = false
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators:false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("GOOD DATES, BEAUTIFULLY PLANNED").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.35).foregroundStyle(Theme.berry)
                        Text("Make a night\nof it.").font(.system(size:34,weight:.medium,design:.serif)).foregroundStyle(Theme.ink).lineSpacing(-2)
                        Text("Thoughtful experiences, made for meeting in real life.").font(.system(size:14,design:.rounded)).foregroundStyle(Theme.muted)
                        ForEach(items) { item in
                            Card {
                                VStack(alignment: .leading, spacing: 13) {
                                    ZStack(alignment:.topLeading) {
                                        Image(item.format == "curated_date" ? "DateNightHero" : "CircleDinner").resizable().scaledToFill().frame(height:175,alignment:.top).clipped()
                                        LinearGradient(colors:[.black.opacity(0.08),.clear,.black.opacity(0.63)],startPoint:.top,endPoint:.bottom)
                                        VStack(alignment:.leading) { Text(item.format == "curated_date" ? "A TABLE FOR TWO" : "COME AS YOU ARE").font(.system(size:9,weight:.bold,design:.rounded)).tracking(1.25).foregroundStyle(.white.opacity(0.92)); Spacer(); Label(item.area.uppercased(),systemImage:"mappin.and.ellipse").font(.system(size:10,weight:.bold,design:.rounded)).tracking(0.8).foregroundStyle(.white) }.padding(16)
                                    }.clipShape(RoundedRectangle(cornerRadius:21))
                                    Text(item.title).font(.system(size:21,weight:.medium,design:.serif)).foregroundStyle(Theme.ink)
                                    HStack(spacing:8) { Label(displayDate(item.starts_at),systemImage:"calendar"); Text("·"); Text(item.format == "curated_date" ? "A table for two":"A shared table") }.font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(Theme.muted)
                                    Label(item.spaces_remaining > 0 ? "\(item.spaces_remaining) places remaining" : "At capacity · \(item.waitlist_count) waiting", systemImage: item.spaces_remaining > 0 ? "person.2" : "person.2.wave.2").font(.caption.weight(.medium)).foregroundStyle(item.spaces_remaining > 0 ? Theme.forest : Theme.berry)
                                    if item.spaces_remaining > 0 {
                                        Button { Task { await book(item) } } label: { HStack { Text("Reserve your place"); Spacer(); Image(systemName:"arrow.up.right") }.font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(.white).padding(.horizontal,16).frame(height:48).background(Theme.plum,in:Capsule()) }.buttonStyle(.plain)
                                    } else if item.on_waitlist {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Button("Refresh reservation status") { Task { await refreshExperiences() } }.buttonStyle(OutlineButton())
                                            Button("Leave the waitlist", role: .destructive) { Task { await setWaitlist(item, waiting: false) } }.font(.subheadline)
                                        }
                                    } else {
                                        Button { Task { await setWaitlist(item, waiting: true) } } label: { HStack { Text("Join the waitlist"); Spacer(); Image(systemName:"arrow.right") }.font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(.white).padding(.horizontal,16).frame(height:48).background(Theme.plum,in:Capsule()) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if let booking {
                            Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Your reservation").font(.headline)
                                    Text("Check-in code: \(booking.check_code)").font(.subheadline)
                                    if !checkedIn {
                                        Button("Check in safely") { Task { await checkIn() } }.buttonStyle(ForestButton())
                                    } else if !checkedOut {
                                        Button("I’m safe · check out") { Task { await checkOut() } }.buttonStyle(ForestButton())
                                    } else {
                                        Button("Send private feedback") { Task { await sendFeedback() } }.buttonStyle(ForestButton())
                                    }
                                    if booking.status == "confirmed" && !checkedIn { Button("Cancel reservation", role: .destructive) { Task { await cancelBooking() } }.font(.subheadline) }
                                }
                            }
                        }
                        if let notice { Text(notice).foregroundStyle(Theme.forest).accessibilityLabel(notice) }
                    }.padding(20)
                }
            }
            .toolbar(.hidden,for:.navigationBar)
            .task { await refreshExperiences() }
        }
    }
    func refreshExperiences() async {
        do {
            let token = session.token ?? ""
            items = try await session.api.get("/experiences", token: token)
            let bookings: [BookingResponse] = try await session.api.get("/me/bookings", token: token)
            if let current = bookings.first(where: { ["confirmed", "checked_in", "checked_out"].contains($0.status) }) {
                booking = current; checkedIn = current.status == "checked_in"; checkedOut = current.status == "checked_out"
            }
        } catch { notice = error.localizedDescription }
    }
    func setWaitlist(_ item: Experience, waiting: Bool) async {
        do {
            let _: WaitlistResponse = try await session.api.send("/experiences/\(item.id)/waitlist", method: waiting ? "POST" : "DELETE", token: session.token ?? "")
            notice = waiting ? "You’re on the waitlist. We’ll show your place here when it changes." : "You’ve left the waitlist."
            await refreshExperiences()
        } catch { notice = error.localizedDescription }
    }
    func cancelBooking() async {
        guard let booking else { return }
        do {
            let result: BookingCancellationResponse = try await session.api.send("/bookings/\(booking.booking_id)", method: "DELETE", token: session.token ?? "")
            self.booking = nil; checkedIn = false; checkedOut = false
            notice = result.waitlist_member_promoted ? "Reservation cancelled. The next guest on the waitlist has been offered the place." : "Reservation cancelled."
            await refreshExperiences()
        } catch { notice = error.localizedDescription }
    }
    func book(_ item: Experience) async {
        do { booking = try await session.api.send("/experiences/\(item.id)/book", method: "POST", token: session.token ?? ""); notice = "Reserved. Your check-in code is \(booking?.check_code ?? "ready")." }
        catch { notice = error.localizedDescription }
    }
    func checkIn() async {
        guard let booking else { return }
        do { let result: CheckResponse = try await session.api.send("/bookings/\(booking.booking_id)/check-in", method: "POST", token: session.token ?? ""); checkedIn = result.checked_in ?? false; notice = "Check-in saved. Have a lovely evening." }
        catch { notice = error.localizedDescription }
    }
    func checkOut() async {
        guard let booking else { return }
        do { let result: CheckResponse = try await session.api.send("/bookings/\(booking.booking_id)/check-out", method: "POST", token: session.token ?? ""); checkedOut = result.safety_check_complete ?? false; notice = "Thanks for checking in. You can leave private feedback." }
        catch { notice = error.localizedDescription }
    }
    func sendFeedback() async {
        guard let booking else { return }
        do { let _: FeedbackResponse = try await session.api.send("/bookings/\(booking.booking_id)/feedback", method: "POST", body: ["rating": "5", "note": "A lovely evening"], token: session.token ?? ""); notice = "Your feedback was sent privately." }
        catch { notice = error.localizedDescription }
    }
}
struct NestView: View {
    @Binding var selection: Int
    @State private var showInvite = false
    @Environment(SessionStore.self) private var session
    @State private var couples: [CoupleSummary] = []
    @State private var email = ""
    @State private var candidates: [Nest4Candidate] = []
    @State private var matches: [Nest4Match] = []
    @State private var properties: [PropertyItem] = []
    @State private var report: LivingReport?
    @State private var editingHomeCouple: CoupleSummary?
    @State private var editingMovingCouple: CoupleSummary?
    @State private var openingTogetherCouple: CoupleSummary?
    @State private var reportingNest4Concern: Nest4Match?
    @State private var openingNest4Chat: Nest4Match?
    @State private var meetupTitle = "Dinner for four"
    @State private var meetupVenue = "A relaxed local restaurant"
    @State private var meetupArea = "East London"
    @State private var meetupDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var notice: String?
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators:false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("LIFE, BUILT TOGETHER").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.35).foregroundStyle(Theme.berry)
                        Text("Your Nest.").font(.system(size:34,weight:.medium,design:.serif)).foregroundStyle(Theme.ink).lineSpacing(-2)
                        if couples.isEmpty {
                            NestStartingView(onConnect: { selection = 1 }, onExperiences: { selection = 2 })
                            Button { withAnimation(.spring(response: 0.4)) { showInvite.toggle() } } label: {
                                HStack { Text("Already found your person?"); Spacer(); Image(systemName: showInvite ? "chevron.up" : "plus") }
                            }.buttonStyle(OutlineButton())
                            if showInvite {
                                Card {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Start a private space together").font(.headline)
                                        Text("Invite their existing TwoNest account. Your space opens after they accept.").font(.subheadline).foregroundStyle(Theme.muted)
                                        TextField("Partner’s account email", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                                        Button("Send invitation") { Task { await invite() } }.buttonStyle(ForestButton()).disabled(!email.contains("@"))
                                    }
                                }
                            }
                        }
                        ForEach(couples) { couple in coupleCard(couple) }
                        if !candidates.isEmpty {
                            Text("Meet another couple").font(.title3.weight(.semibold))
                            ForEach(candidates) { candidate in
                                Card {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(candidate.first_names.joined(separator: " & ")).font(.headline)
                                        Text("A Nest4 introduction needs four individual approvals.").font(.caption).foregroundStyle(Theme.muted)
                                        Button("Propose a Nest4 introduction") { Task { await propose(candidate) } }.buttonStyle(OutlineButton())
                                    }
                                }
                            }
                        }
                        ForEach(matches) { match in
                            Card {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Nest4 · \(match.other_first_names.joined(separator: " & "))").font(.headline)
                                    Text(nest4StatusDescription(match.status)).font(.subheadline).foregroundStyle(Theme.muted)
                                    if match.status == "pending" {
                                        Text("\(match.approval_count)/4 people have approved.").font(.caption.weight(.semibold)).foregroundStyle(Theme.forest)
                                        HStack {
                                            Button("I’m interested") { Task { await decide(match, approved: true) } }.buttonStyle(ForestButton())
                                            Button("Pass") { Task { await decide(match, approved: false) } }.buttonStyle(OutlineButton())
                                        }
                                    } else if match.status == "matched" {
                                        if let plan = match.meeting_plan, plan.status != "declined" {
                                            Text("\(plan.title) · \(plan.venue), \(plan.area)").font(.subheadline.weight(.semibold))
                                            Text("\(displayDate(plan.starts_at)) · \(plan.attending_count)/4 attending · \(plan.status.capitalized)").font(.caption).foregroundStyle(Theme.muted)
                                            if plan.status == "proposed" && plan.my_vote == nil {
                                                HStack {
                                                    Button("I can make it") { Task { await voteMeeting(match, plan, attending: true) } }.buttonStyle(ForestButton())
                                                    Button("Can’t attend") { Task { await voteMeeting(match, plan, attending: false) } }.buttonStyle(OutlineButton())
                                                }
                                            } else if plan.status == "scheduled" && isNest4MeetingPast(plan.starts_at) {
                                                Button("We’ve met") { Task { await completeMeeting(match, plan) } }.buttonStyle(ForestButton())
                                            } else if plan.status == "scheduled" {
                                                Label("Your meetup is confirmed", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.forest)
                                            }
                                        } else {
                                            TextField("Meetup idea", text: $meetupTitle).textFieldStyle(.roundedBorder)
                                            TextField("Venue", text: $meetupVenue).textFieldStyle(.roundedBorder)
                                            TextField("Neighbourhood", text: $meetupArea).textFieldStyle(.roundedBorder)
                                            DatePicker("A time that works", selection: $meetupDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                                            Button("Suggest a meetup") { Task { await proposeMeeting(match) } }.buttonStyle(ForestButton())
                                        }
                                    } else if match.status == "meeting_complete" {
                                        Text("\(match.followup_count)/4 people have made a private choice.").font(.caption.weight(.semibold)).foregroundStyle(Theme.forest)
                                        Text(match.your_followup.map { "Your choice: \($0.replacingOccurrences(of: "_", with: " ").capitalized)" } ?? "Choose privately whether you’d like to stay connected.").font(.subheadline).foregroundStyle(Theme.muted)
                                        Button("Meet again") { Task { await followup(match, decision: "meet_again") } }.buttonStyle(ForestButton())
                                        Button("Invite them to an activity") { Task { await followup(match, decision: "invite_activity") } }.buttonStyle(OutlineButton())
                                        Button("Add to Couple Circle") { Task { await followup(match, decision: "couple_circle") } }.buttonStyle(OutlineButton())
                                        Button("No further connection", role: .destructive) { Task { await followup(match, decision: "no_connection") } }
                                        Button("Report a concern", role: .destructive) { reportingNest4Concern = match }
                                    } else if match.status == "connected" {
                                        Text("All four chose to continue after meeting.").font(.subheadline).foregroundStyle(Theme.muted)
                                        Button("Open your group chat") { openingNest4Chat = match }.buttonStyle(ForestButton())
                                    } else if match.status == "closed" {
                                        Text("This Nest4 introduction has ended.").font(.subheadline).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                        if let report { reportCard(report) }
                        if couples.contains(where: { $0.status == "active" && $0.your_home_consent && $0.partner_home_consent }) && !properties.isEmpty {
                            Text("Verified homes to explore").font(.title3.weight(.semibold))
                            ForEach(properties) { property in
                                Card {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(property.title).font(.headline)
                                        Text("\(property.area) · £\(property.rent_pcm) pcm · \(property.bedrooms) bedrooms").font(.subheadline).foregroundStyle(Theme.muted)
                                        Button("Add to shared shortlist") { Task { await shortlist(property) } }.buttonStyle(OutlineButton())
                                    }
                                }
                            }
                        }
                        if let notice { Text(notice).font(.subheadline).foregroundStyle(Theme.forest).accessibilityLabel(notice) }
                    }.padding(20)
                }
            }
            .toolbar(.hidden,for:.navigationBar)
            .task { await load() }
            .sheet(item: $editingHomeCouple) { couple in HomeQuestionnaireView(couple: couple) { Task { await load() } } }
            .sheet(item: $editingMovingCouple) { couple in MovingWorkspaceView(couple: couple) }
            .sheet(item: $openingTogetherCouple) { couple in TogetherView(couple: couple) }
            .sheet(item: $reportingNest4Concern) { match in Nest4ConcernView(match: match) { Task { await load() } } }
            .sheet(item: $openingNest4Chat) { match in Nest4GroupChatView(match: match) }
        }
    }
    @ViewBuilder func coupleCard(_ couple: CoupleSummary) -> some View {
        if couple.status == "active" {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("YOUR PRIVATE SPACE").font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(Theme.berry)
                            Text("\(session.user?.first_name ?? "You") &\n\(couple.partner_first_name)").font(.system(size: 30, weight: .medium, design: .serif)).foregroundStyle(Theme.forest).fixedSize(horizontal: false, vertical: true)
                            Text("Make plans. Save moments. Build your next chapter.").font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        NestSculpture().frame(width: 130, height: 150).accessibilityHidden(true)
                    }
                    Button { openingTogetherCouple = couple } label: { HStack { Text("Open Together"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(ForestButton())
                }.padding(22).background(Theme.paper, in: RoundedRectangle(cornerRadius: 27)).nestScrollMotion()
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("A home that fits you both", systemImage: "house").font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(Theme.forest)
                        Text("Explore your routines, priorities and shared hopes before planning a move.").font(.subheadline).foregroundStyle(Theme.muted)
                        HStack { Text("Your answers"); Spacer(); Text("\(couple.your_home_answer_count)/10").foregroundStyle(Theme.forest) }.font(.caption.weight(.semibold))
                        ProgressView(value: Double(couple.your_home_answer_count), total: 10).tint(Theme.forest)
                        Text("Your partner · \(couple.partner_home_answer_count)/10 answers").font(.caption).foregroundStyle(Theme.muted)
                        Button("Set your home preferences") { editingHomeCouple = couple }.buttonStyle(OutlineButton())
                        if !couple.your_home_consent {
                            Text("Home Mode opens after you both opt in. Your individual answers stay private.").font(.footnote).foregroundStyle(Theme.muted)
                            Button("I’m ready for Home Mode") { Task { await activateHome(couple) } }.buttonStyle(ForestButton())
                        } else if couple.partner_home_consent {
                            Button("Explore your shared report") { Task { await loadReport(couple) } }.buttonStyle(OutlineButton())
                            Button("Open your moving plan") { editingMovingCouple = couple }.buttonStyle(ForestButton())
                        } else {
                            Label("Waiting for your partner’s Home Mode consent", systemImage: "lock").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Good company, together", systemImage: "person.2").font(.system(size: 22, weight: .medium, design: .serif)).foregroundStyle(Theme.forest)
                        Text("Meet another couple through Nest4. An introduction opens only when all four people agree.").font(.subheadline).foregroundStyle(Theme.muted)
                        Button("Explore Nest4 introductions") { Task { await loadNest4(couple) } }.buttonStyle(OutlineButton())
                    }
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Label(couple.invited_to_me ? "An invitation from \(couple.partner_first_name)" : "Your invitation to \(couple.partner_first_name)", systemImage: "heart.house").font(.title3.weight(.semibold)).foregroundStyle(Theme.forest)
                    Text(couple.invited_to_me ? "Create a private space for shared plans and moments. Home Mode needs separate consent from both of you." : "Your shared space will open after your partner accepts from their account.").font(.subheadline).foregroundStyle(Theme.muted)
                    if couple.invited_to_me { Button("Accept invitation") { Task { await accept(couple) } }.buttonStyle(ForestButton()) }
                }
            }
        }
    }
    @ViewBuilder func reportCard(_ report: LivingReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Living Compatibility").font(.title3.weight(.semibold))
                Text(report.disclaimer).font(.caption).foregroundStyle(Theme.muted)
                Label("You’ve answered \(report.your_answer_count)/\(report.total_questions) · your partner \(report.partner_answer_count)/\(report.total_questions)", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.forest)
                if !report.strong_alignment.isEmpty {
                    Text("Shared ground").font(.headline)
                    ForEach(report.strong_alignment, id: \.self) { Text("• \($0)").font(.subheadline) }
                }
                if !report.acceptable_differences.isEmpty {
                    Text("Room to find your rhythm").font(.headline)
                    ForEach(report.acceptable_differences, id: \.self) { Text("• \($0)").font(.subheadline) }
                }
                if !report.discuss_early.isEmpty {
                    Text("Worth talking through").font(.headline)
                    ForEach(report.discuss_early, id: \.self) { Text("• \($0)").font(.subheadline) }
                }
                if !report.compromises.isEmpty {
                    Text("Ideas to make it work").font(.headline)
                    ForEach(report.compromises, id: \.self) { Text("• \($0)").font(.subheadline) }
                }
            }
        }
    }
    func load() async {
        guard let token = session.token else { return }
        do {
            couples = try await session.api.get("/couples/me", token: token)
            properties = try await session.api.get("/properties", token: token)
            matches = try await session.api.get("/nest4", token: token)
        } catch { notice = error.localizedDescription }
    }
    func invite() async {
        do { let _: CoupleAction = try await session.api.send("/couples/invite", method: "POST", body: ["partner_email": email], token: session.token ?? ""); notice = "Invitation sent. Your partner must accept from their own account."; await load() }
        catch { notice = error.localizedDescription }
    }
    func accept(_ couple: CoupleSummary) async {
        do { let _: CoupleAction = try await session.api.send("/couples/\(couple.id)/accept", method: "POST", token: session.token ?? ""); notice = "Couple space activated."; await load() }
        catch { notice = error.localizedDescription }
    }
    func activateHome(_ couple: CoupleSummary) async {
        do { let result: HomeModeResponse = try await session.api.send("/couples/\(couple.id)/home-mode", method: "POST", body: ["approved": "true"], token: session.token ?? ""); notice = result.active ? "Home Mode is active for both of you." : "Your consent is saved. Your partner needs to activate Home Mode too."; await load() }
        catch { notice = error.localizedDescription }
    }
    func loadReport(_ couple: CoupleSummary) async {
        do { report = try await session.api.get("/couples/\(couple.id)/living-report", token: session.token ?? "") }
        catch { notice = error.localizedDescription }
    }
    func loadNest4(_ couple: CoupleSummary) async {
        do { candidates = try await session.api.get("/couples/\(couple.id)/nest4-candidates", token: session.token ?? "") }
        catch { notice = error.localizedDescription }
    }
    func propose(_ candidate: Nest4Candidate) async {
        guard let couple = couples.first(where: { $0.status == "active" }) else { return }
        do { let _: Nest4ProposalResponse = try await session.api.send("/couples/\(couple.id)/nest4/\(candidate.couple_id)", method: "POST", token: session.token ?? ""); notice = "Nest4 invitation sent to all four people."; await load() }
        catch { notice = error.localizedDescription }
    }
    func decide(_ match: Nest4Match, approved: Bool) async {
        do { let result: Nest4ConsentResult = try await session.api.send("/nest4/\(match.match_id)/decision", method: "POST", body: ["approved": approved], token: session.token ?? ""); notice = result.status == "matched" ? "All four people opted in. Now plan a meetup together." : "Your choice is saved privately."; await load() }
        catch { notice = error.localizedDescription }
    }
    func proposeMeeting(_ match: Nest4Match) async {
        let formatter = ISO8601DateFormatter()
        let startsAt = formatter.string(from: meetupDate)
        let payload: [String: Any] = ["title": meetupTitle, "venue": meetupVenue, "area": meetupArea, "starts_at": startsAt]
        do { let _: Nest4MeetingPlan = try await session.api.send("/nest4/\(match.match_id)/meeting-plans", method: "POST", body: payload, token: session.token ?? ""); notice = "Meetup idea shared. Everyone can privately confirm whether they can make it."; await load() }
        catch { notice = error.localizedDescription }
    }
    func voteMeeting(_ match: Nest4Match, _ plan: Nest4MeetingPlan, attending: Bool) async {
        do { let _: Nest4MeetingPlan = try await session.api.send("/nest4/\(match.match_id)/meeting-plans/\(plan.id)/vote", method: "POST", body: ["attending": attending], token: session.token ?? ""); notice = attending ? "Your attendance is saved." : "Your response is saved privately."; await load() }
        catch { notice = error.localizedDescription }
    }
    func completeMeeting(_ match: Nest4Match, _ plan: Nest4MeetingPlan) async {
        do { let _: Nest4MeetingCompleteResult = try await session.api.send("/nest4/\(match.match_id)/meeting-plans/\(plan.id)/complete", method: "POST", token: session.token ?? ""); notice = "Your private post-meet choices are now open."; await load() }
        catch { notice = error.localizedDescription }
    }
    func followup(_ match: Nest4Match, decision: String) async {
        do { let result: Nest4FollowupResult = try await session.api.send("/nest4/\(match.match_id)/follow-up", method: "POST", body: ["decision": decision], token: session.token ?? ""); notice = result.group_chat_open ? "All four people chose to stay connected. Your group chat is open." : "Your choice is saved privately."; await load() }
        catch { notice = error.localizedDescription }
    }
    func nest4StatusDescription(_ status: String) -> String {
        switch status {
        case "pending": return "Four individual decisions come first. Your choice stays private."
        case "matched": return "Everyone opted in. Plan a relaxed meetup before deciding what comes next."
        case "meeting_complete": return "Your meetup is marked complete. Choose privately whether you’d like to continue."
        case "connected": return "Both couples chose to continue after meeting."
        default: return "This Nest4 introduction has ended."
        }
    }
    func isNest4MeetingPast(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return date.map { $0 <= .now } ?? false
    }
    func shortlist(_ property: PropertyItem) async {
        guard let couple = couples.first(where: { $0.status == "active" }) else { return }
        do { let _: ShortlistResponse = try await session.api.send("/couples/\(couple.id)/properties/\(property.id)/shortlist", method: "POST", body: ["approved": "true"], token: session.token ?? ""); notice = "Added to your shared shortlist." }
        catch { notice = error.localizedDescription }
    }
}

private struct Nest4ConcernView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let match: Nest4Match
    let onSaved: () -> Void
    @State private var details = ""
    @State private var error: String?
    @State private var sending = false
    var body: some View {
        NavigationStack {
            Form {
                Section("A safety concern") {
                    Text("Your choice is private. Reporting ends this Nest4 connection and sends the concern to the safety team.").font(.footnote).foregroundStyle(Theme.muted)
                    TextEditor(text: $details).frame(minHeight: 150).accessibilityLabel("Concern details")
                    Text("Please share at least 10 characters.").font(.caption).foregroundStyle(Theme.muted)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.cream)
            .navigationTitle("Report a concern").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(sending ? "Sending…" : "Send") { Task { await submit() } }.disabled(sending || details.trimmingCharacters(in: .whitespacesAndNewlines).count < 10) }
            }
        }
    }
    private func submit() async {
        guard let token = session.token else { return }
        sending = true; error = nil; defer { sending = false }
        do {
            let _: Nest4FollowupResult = try await session.api.send("/nest4/\(match.match_id)/follow-up", method: "POST", body: ["decision": "report_concern", "details": details], token: token)
            dismiss(); onSaved()
        } catch { self.error = error.localizedDescription }
    }
}

private struct Nest4GroupChatView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let match: Nest4Match
    @State private var messages: [Nest4GroupMessage] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var sending = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            HStack {
                                if message.sender_id == session.user?.id { Spacer(minLength: 38) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.first_name).font(.caption.weight(.semibold)).foregroundStyle(Theme.forest)
                                    Text(message.body).font(.body)
                                }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                if message.sender_id != session.user?.id { Spacer(minLength: 38) }
                            }
                        }
                        if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    }.padding(16)
                }.background(Theme.cream)
                HStack(spacing: 10) {
                    TextField("Say hello to your circle of four", text: $draft, axis: .vertical).lineLimit(1...4).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 42, height: 42).background(Theme.forest, in: Circle()) }
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send group message")
                }.padding(12).background(Theme.cream)
            }
            .navigationTitle(match.other_first_names.joined(separator: " & "))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        guard let token = session.token else { loading = false; return }
        defer { loading = false }
        do { messages = try await session.api.get("/nest4/\(match.match_id)/messages", token: token) }
        catch { self.error = error.localizedDescription }
    }
    private func send() async {
        guard let token = session.token else { return }
        sending = true; defer { sending = false }
        do {
            let message: Nest4GroupMessage = try await session.api.send("/nest4/\(match.match_id)/messages", method: "POST", body: ["body": draft], token: token)
            messages.append(message); draft = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct HomeAnswerDraft {
    var value: APIJSONValue?
    var isPrivate = false
    var isAnswered: Bool {
        guard let value else { return false }
        if case .null = value { return false }
        if case .string(let text) = value { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if case .array(let items) = value { return !items.isEmpty }
        return true
    }
}

private struct HomeQuestionAnswerRow: View {
    let question: QuestionnaireQuestion
    @Binding var draft: HomeAnswerDraft
    private var options: [String] { question.options ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.prompt).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
            answerControl
            Toggle("Keep out of the shared report", isOn: $draft.isPrivate).font(.system(size: 12, design: .rounded)).tint(Theme.forest)
        }.padding(.vertical, 7)
    }

    @ViewBuilder private var answerControl: some View {
        switch question.response_type {
        case "single_select":
            Picker("Choose an answer", selection: Binding<String>(get: { draft.value?.stringValue ?? "" }, set: { draft.value = $0.isEmpty ? nil : .string($0) })) {
                Text("Choose an answer").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case "scale":
            Picker("Your answer", selection: Binding<Int>(get: { draft.value?.integerValue ?? ((question.minimum ?? 1) + (question.maximum ?? 5)) / 2 }, set: { draft.value = .integer($0) })) {
                ForEach((question.minimum ?? 1)...(question.maximum ?? 5), id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented).accessibilityLabel(question.prompt)
        case "ranking":
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap choices in the order you prefer.").font(.caption).foregroundStyle(Theme.muted)
                ForEach(options, id: \.self) { option in
                    let selected = draft.value?.arrayValue ?? []
                    let rank = selected.firstIndex(of: option).map { $0 + 1 }
                    Button {
                        var next = selected
                        if let index = next.firstIndex(of: option) { next.remove(at: index) } else { next.append(option) }
                        draft.value = next.isEmpty ? nil : .array(next.map(APIJSONValue.string))
                    } label: {
                        HStack { if let rank { Text("\(rank)").fontWeight(.bold) }; Text(option); Spacer(); Image(systemName: rank == nil ? "plus" : "checkmark") }
                            .font(.system(size: 13, design: .rounded)).foregroundStyle(rank == nil ? Theme.ink : .white)
                            .padding(11).background(rank == nil ? Theme.cream : Theme.forest, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
        default:
            Text("This home question is not available yet.").font(.footnote).foregroundStyle(Theme.muted)
        }
    }
}

private struct HomeQuestionnaireView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let couple: CoupleSummary
    let onSaved: () -> Void
    @State private var groups: [QuestionnaireGroup] = []
    @State private var drafts: [String: HomeAnswerDraft] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These questions help you explore the everyday parts of sharing a home. Your individual answers are never shown to your partner. Choose which ones may contribute to a broad shared report; anything kept private is left out.")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                }
                if loading { ProgressView("Loading your home questions…").frame(maxWidth: .infinity, alignment: .center) }
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.questions) { question in HomeQuestionAnswerRow(question: question, draft: draftBinding(question.id)) }
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.cream).tint(Theme.forest)
            .navigationTitle("A home, together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : "Save") { Task { await save() } }.disabled(saving || loading) }
            }
            .task { await load() }
        }
    }

    private func draftBinding(_ id: String) -> Binding<HomeAnswerDraft> {
        Binding(get: { drafts[id] ?? HomeAnswerDraft(value: nil) }, set: { drafts[id] = $0 })
    }

    private func load() async {
        guard let token = session.token else { loading = false; return }
        defer { loading = false }
        do {
            let form: HomeModeQuestionnaire = try await session.api.get("/couples/\(couple.id)/home-questionnaire", token: token)
            groups = form.groups
            for answer in form.answers { drafts[answer.question_id] = HomeAnswerDraft(value: answer.value, isPrivate: answer.is_private) }
        } catch { self.error = error.localizedDescription }
    }

    private func save() async {
        guard let token = session.token else { return }
        let answers: [[String: Any]] = drafts.compactMap { id, draft in
            guard draft.isAnswered, let value = draft.value else { return nil }
            return ["question_id": id, "value": value.foundationValue, "is_private": draft.isPrivate]
        }
        guard !answers.isEmpty else { error = "Answer at least one home question before saving."; return }
        saving = true; error = nil; defer { saving = false }
        do {
            let _: HomeModeAnswerSaved = try await session.api.send("/couples/\(couple.id)/home-questionnaire/answers", method: "PUT", body: ["answers": answers], token: token)
            dismiss(); onSaved()
        } catch { self.error = error.localizedDescription }
    }
}

private struct TogetherView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let couple: CoupleSummary
    @State private var stage = "dating"
    @State private var area = ""
    @State private var interests = ""
    @State private var activities = ""
    @State private var food = ""
    @State private var socialEnergy = ""
    @State private var children = ""
    @State private var pets = ""
    @State private var languages = "English"
    @State private var availability = ""
    @State private var budgetMin = 0
    @State private var budgetMax = 100
    @State private var travel = ""
    @State private var moments: [CoupleMoment] = []
    @State private var newTitle = ""
    @State private var newDetails = ""
    @State private var newType = "date"
    @State private var scheduled = false
    @State private var plannedFor = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var hasProfile = false
    @State private var approvedByYou = false
    @State private var approvedByPartner = false
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Your shared chapter").font(.system(size: 24, weight: .medium, design: .serif))
                        Text("Build a private couple profile and plan dates, activities and milestones together.").font(.subheadline).foregroundStyle(Theme.muted)
                    }.padding(.vertical, 6)
                }
                Section("Your shared profile") {
                    Picker("Relationship stage", selection: $stage) {
                        Text("Dating").tag("dating")
                        Text("Early dating").tag("early_dating")
                        Text("Established").tag("established")
                        Text("Preparing for home together").tag("home_mode")
                        Text("Living together").tag("living_together")
                    }
                    TextField("General area", text: $area)
                    TextField("Shared interests · comma separated", text: $interests, axis: .vertical)
                    TextField("Activities you enjoy", text: $activities, axis: .vertical)
                    TextField("Food preferences", text: $food, axis: .vertical)
                    Picker("Social energy", selection: $socialEnergy) {
                        Text("Choose together").tag("")
                        Text("Quiet and cosy").tag("quiet")
                        Text("A little of both").tag("balanced")
                        Text("Lively and social").tag("social")
                    }
                    TextField("Children · only what you both want to share", text: $children)
                    TextField("Pets", text: $pets)
                    TextField("Languages", text: $languages)
                    TextField("When you’re usually free", text: $availability)
                    Stepper("Experience budget · £\(budgetMin)–£\(budgetMax)", value: $budgetMax, in: budgetMin...500, step: 10)
                    Stepper("Minimum · £\(budgetMin)", value: $budgetMin, in: 0...budgetMax, step: 10)
                    TextField("Travel interests", text: $travel, axis: .vertical)
                }
                Section("Share this profile") {
                    Text(hasProfile ? (approvedByPartner ? "Your partner has approved this profile." : "Your partner’s approval is still needed.") : "Save your shared profile first. It stays private until both of you approve it.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Button(saving ? "Saving…" : "Save shared profile") { Task { await saveProfile() } }.disabled(loading || saving)
                    if hasProfile {
                        if approvedByYou {
                            Button("Withdraw my publication approval", role: .destructive) { Task { await setConsent(false) } }
                        } else {
                            Button("I approve sharing this profile") { Task { await setConsent(true) } }.buttonStyle(ForestButton())
                        }
                        Label(approvedByYou && approvedByPartner ? "Published with both approvals" : "Private · waiting for both approvals", systemImage: approvedByYou && approvedByPartner ? "checkmark.seal.fill" : "lock.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(approvedByYou && approvedByPartner ? Theme.forest : Theme.muted)
                    }
                    Text("Editing the shared profile clears both approvals. Each of you can withdraw approval at any time.").font(.caption).foregroundStyle(Theme.muted)
                }
                Section("Dates and milestones") {
                    if moments.isEmpty { Text("Your shared timeline starts with a date, activity or small milestone.").font(.subheadline).foregroundStyle(Theme.muted) }
                    ForEach(moments) { moment in
                        HStack(alignment: .top, spacing: 10) {
                            Button { Task { await toggle(moment) } } label: {
                                Image(systemName: moment.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(moment.completed ? Theme.forest : Theme.muted)
                            }.buttonStyle(.plain).accessibilityLabel(moment.completed ? "Mark incomplete" : "Mark complete")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(moment.title).font(.subheadline.weight(.semibold)).strikethrough(moment.completed)
                                Label(moment.moment_type.capitalized, systemImage: moment.moment_type == "milestone" ? "sparkles" : moment.moment_type == "date" ? "heart" : "figure.walk")
                                    .font(.caption).foregroundStyle(Theme.berry)
                                if let date = moment.planned_for { Text(displayDate(date)).font(.caption).foregroundStyle(Theme.muted) }
                                if !moment.details.isEmpty { Text(moment.details).font(.caption).foregroundStyle(Theme.muted) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Add to your timeline") {
                    TextField("What would you like to plan?", text: $newTitle)
                    TextField("A note for both of you (optional)", text: $newDetails, axis: .vertical)
                    Picker("Add as", selection: $newType) {
                        Text("Date plan").tag("date")
                        Text("Shared activity").tag("activity")
                        Text("Milestone").tag("milestone")
                    }
                    Toggle("Choose a date", isOn: $scheduled)
                    if scheduled { DatePicker("Planned for", selection: $plannedFor, in: Date.now..., displayedComponents: [.date, .hourAndMinute]) }
                    Button("Add to our timeline") { Task { await addMoment() } }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                if let notice { Section { Text(notice).font(.footnote).foregroundStyle(Theme.forest) } }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.cream).tint(Theme.forest)
            .navigationTitle("TwoNest Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        guard let token = session.token else { loading = false; return }
        defer { loading = false }
        do {
            let state: CoupleTogetherState = try await session.api.get("/couples/\(couple.id)/together", token: token)
            let profile = state.profile
            stage = profile.relationship_stage; area = profile.general_area
            interests = profile.shared_interests.joined(separator: ", "); activities = profile.preferred_activities.joined(separator: ", ")
            food = profile.food_preferences.joined(separator: ", "); socialEnergy = profile.social_energy; children = profile.children
            pets = profile.pets.joined(separator: ", "); languages = profile.languages.joined(separator: ", ")
            availability = profile.availability.joined(separator: ", "); budgetMin = profile.event_budget_min; budgetMax = profile.event_budget_max
            travel = profile.travel_interests.joined(separator: ", "); hasProfile = state.has_profile
            approvedByYou = state.approved_by_you; approvedByPartner = state.approved_by_partner
            moments = try await session.api.get("/couples/\(couple.id)/moments", token: token)
        } catch { self.error = error.localizedDescription }
    }

    private func saveProfile() async {
        guard budgetMin <= budgetMax else { error = "Your minimum budget must be no higher than your maximum."; return }
        saving = true; error = nil; notice = nil; defer { saving = false }
        let body: [String: Any] = [
            "relationship_stage": stage, "general_area": area,
            "shared_interests": split(interests), "preferred_activities": split(activities),
            "food_preferences": split(food), "social_energy": socialEnergy, "children": children,
            "pets": split(pets), "languages": split(languages), "availability": split(availability),
            "event_budget_min": budgetMin, "event_budget_max": budgetMax, "travel_interests": split(travel)
        ]
        do {
            let state: CoupleTogetherState = try await session.api.send("/couples/\(couple.id)/together", method: "PUT", body: body, token: session.token ?? "")
            hasProfile = state.has_profile; approvedByYou = state.approved_by_you; approvedByPartner = state.approved_by_partner
            notice = state.published ? "Your updated profile remains approved by both of you." : "Saved. Both partners need to approve before it’s shared."
        } catch { self.error = error.localizedDescription }
    }

    private func setConsent(_ approved: Bool) async {
        do {
            let state: CoupleTogetherState = try await session.api.send("/couples/\(couple.id)/together/consent", method: "POST", body: ["approved": approved], token: session.token ?? "")
            approvedByYou = state.approved_by_you; approvedByPartner = state.approved_by_partner
            notice = state.published ? "Your couple profile is now shared with both partners’ approval." : approved ? "Your approval is saved. Waiting for your partner." : "Your approval is withdrawn. The profile is private."
        } catch { self.error = error.localizedDescription }
    }

    private func addMoment() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return }
        var payload: [String: Any] = ["title": title, "details": newDetails, "moment_type": newType]
        if scheduled { payload["planned_for"] = ISO8601DateFormatter().string(from: plannedFor) }
        do {
            let item: CoupleMoment = try await session.api.send("/couples/\(couple.id)/moments", method: "POST", body: payload, token: session.token ?? "")
            moments.append(item); newTitle = ""; newDetails = ""; notice = "Added to your shared timeline."
        } catch { self.error = error.localizedDescription }
    }

    private func toggle(_ moment: CoupleMoment) async {
        do {
            let result: CoupleMomentUpdate = try await session.api.send("/couples/\(couple.id)/moments/\(moment.id)", method: "PATCH", body: ["completed": !moment.completed], token: session.token ?? "")
            if let index = moments.firstIndex(where: { $0.id == moment.id }) {
                let old = moments[index]
                moments[index] = CoupleMoment(id: old.id, title: old.title, details: old.details, moment_type: old.moment_type, planned_for: old.planned_for, completed: result.completed)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func split(_ value: String) -> [String] {
        Array(Set(value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
}

private struct MovingWorkspaceView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let couple: CoupleSummary
    @State private var tasks: [MovingTaskItem] = []
    @State private var newTask = ""
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("A calmer move, one step at a time").font(.system(size: 23, weight: .medium, design: .serif))
                                Text("A private checklist shared with \(couple.partner_first_name). Keep plans and progress in one place.").font(.subheadline).foregroundStyle(Theme.muted)
                            }
                        }
                        if loading { ProgressView("Loading your plan…").frame(maxWidth: .infinity) }
                        if !tasks.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("YOUR SHARED CHECKLIST").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Theme.berry).padding(.bottom, 10)
                                    ForEach(tasks) { task in
                                        Button { Task { await setCompleted(task, to: !task.completed) } } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(task.completed ? Theme.forest : Theme.muted)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(task.title).font(.subheadline.weight(.medium)).foregroundStyle(task.completed ? Theme.muted : Theme.ink).strikethrough(task.completed)
                                                    Text(task.category.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(Theme.muted)
                                                }
                                                Spacer(minLength: 0)
                                            }.padding(.vertical, 11).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityLabel("\(task.completed ? "Mark incomplete" : "Complete"): \(task.title)")
                                        if task.id != tasks.last?.id { Divider().overlay(Theme.line).padding(.leading, 32) }
                                    }
                                }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 11) {
                                Text("Add a step for both of you").font(.headline)
                                TextField("e.g. Compare moving companies", text: $newTask).textFieldStyle(.roundedBorder).submitLabel(.done)
                                Button("Add to shared plan") { Task { await addTask() } }.buttonStyle(ForestButton()).disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                            }
                        }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 4) }
                    }.padding(20)
                }
            }
            .navigationTitle("Moving together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        guard let token = session.token else { loading = false; return }
        defer { loading = false }
        do { tasks = try await session.api.get("/couples/\(couple.id)/moving-tasks", token: token) }
        catch { self.error = error.localizedDescription }
    }
    private func setCompleted(_ task: MovingTaskItem, to value: Bool) async {
        do {
            let _: [String: APIJSONValue] = try await session.api.send("/couples/\(couple.id)/moving-tasks/\(task.id)", method: "PATCH", body: ["completed": value], token: session.token ?? "")
            if let index = tasks.firstIndex(where: { $0.id == task.id }) { let old = tasks[index]; tasks[index] = MovingTaskItem(id: old.id, title: old.title, category: old.category, due_date: old.due_date, completed: value) }
        } catch { self.error = error.localizedDescription }
    }
    private func addTask() async {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return }
        do {
            let task: MovingTaskItem = try await session.api.send("/couples/\(couple.id)/moving-tasks", method: "POST", body: ["title": title], token: session.token ?? "")
            tasks.append(task); newTask = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct NestLink:View{let icon:String;let title:String;let subtitle:String;var body:some View{Card{HStack{Image(systemName:icon).foregroundStyle(Theme.forest).frame(width:32);VStack(alignment:.leading,spacing:4){Text(title).font(.headline);Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)};Spacer();Image(systemName:"chevron.right").foregroundStyle(Theme.muted)}}}}
struct Card<Content:View>:View{@ViewBuilder var content:Content;var body:some View{content.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Theme.paper,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(Theme.line,lineWidth:1)).shadow(color:Theme.plum.opacity(0.045),radius:10,y:5).nestScrollMotion()}}
struct SignInBenefit:View{let icon:String;let tint:Color;let eyebrow:String;let title:String;var body:some View{HStack(spacing:13){Image(systemName:icon).font(.system(size:15,weight:.semibold)).foregroundStyle(Theme.ink).frame(width:42,height:42).background(tint,in:Circle());VStack(alignment:.leading,spacing:4){Text(eyebrow).font(.system(size:9,weight:.bold,design:.rounded)).tracking(1).foregroundStyle(tint);Text(title).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)};Spacer(minLength:0)}.padding(.vertical,15)} }
struct HomeActionCard:View{let icon:String;let title:String;let detail:String;let tint:Color;let action:()->Void;var body:some View{Button(action:action){VStack(alignment:.leading,spacing:15){Image(systemName:icon).font(.system(size:17,weight:.regular)).foregroundStyle(Theme.forest).frame(width:40,height:40).background(tint,in:Circle());VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:15,weight:.medium,design:.serif)).foregroundStyle(Theme.ink);Text(detail).font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)}}.frame(maxWidth:.infinity,minHeight:120,alignment:.leading).padding(15).background(Theme.paper,in:RoundedRectangle(cornerRadius:19)).overlay(RoundedRectangle(cornerRadius:19).stroke(Theme.line,lineWidth:1))}.buttonStyle(.plain)} }
struct StatCard:View{let value:String;let title:String;var body:some View{VStack(alignment:.leading,spacing:6){Text(value).font(.system(size:27,weight:.semibold,design:.serif));Text(title).font(.caption).foregroundStyle(Theme.muted)}.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(.white,in:RoundedRectangle(cornerRadius:18))}}
struct WelcomeTile:View{let symbol:String;let title:String;let tint:Color;var body:some View{VStack(spacing:9){Image(systemName:symbol).font(.system(size:17,weight:.semibold)).foregroundStyle(Theme.ink).frame(width:43,height:43).background(tint.opacity(0.55),in:RoundedRectangle(cornerRadius:15));Text(title).font(.system(size:10,weight:.semibold,design:.rounded)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)}.frame(maxWidth:.infinity).padding(.vertical,13).background(.white.opacity(0.58),in:RoundedRectangle(cornerRadius:19)).overlay(RoundedRectangle(cornerRadius:19).stroke(.white.opacity(0.8),lineWidth:1))}}
struct JourneyCard:View{let symbol:String;let title:String;let caption:String;let tint:Color;var body:some View{VStack(alignment:.leading,spacing:15){Image(systemName:symbol).font(.system(size:17,weight:.bold)).foregroundStyle(.white).frame(width:43,height:43).background(tint,in:RoundedRectangle(cornerRadius:15));VStack(alignment:.leading,spacing:4){Text(title).font(.system(size:17,weight:.bold,design:.rounded)).foregroundStyle(Theme.ink);Text(caption).font(.system(size:11,design:.rounded)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85)}}.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(.white,in:RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).stroke(Theme.line,lineWidth:1))}}
struct ForestButton:ButtonStyle{func makeBody(configuration:Configuration)->some View{configuration.label.font(.subheadline.weight(.semibold)).padding(.horizontal,16).padding(.vertical,12).background(Theme.forest.opacity(configuration.isPressed ? 0.82:1),in:Capsule()).foregroundStyle(.white)}}
struct OutlineButton:ButtonStyle{func makeBody(configuration:Configuration)->some View{configuration.label.font(.subheadline.weight(.medium)).padding(.horizontal,18).padding(.vertical,12).overlay(Capsule().stroke(Theme.line,lineWidth:1)).foregroundStyle(Theme.ink)}}
func displayDate(_ raw:String)->String{let parser=ISO8601DateFormatter();parser.formatOptions=[.withInternetDateTime,.withFractionalSeconds];let date=parser.date(from:raw) ?? ISO8601DateFormatter().date(from:raw);return date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? raw}
enum Theme{static let cream=Color(red:0.97,green:0.95,blue:0.90);static let paper=Color(red:1,green:0.99,blue:0.96);static let blush=Color(red:0.94,green:0.82,blue:0.77);static let lilac=Color(red:0.84,green:0.87,blue:0.82);static let coral=Color(red:0.78,green:0.39,blue:0.30);static let berry=Color(red:0.68,green:0.32,blue:0.25);static let plum=Color(red:0.16,green:0.30,blue:0.24);static let gold=Color(red:0.82,green:0.68,blue:0.42);static let forest=plum;static let terracotta=coral;static let ink=Color(red:0.17,green:0.19,blue:0.17);static let muted=Color(red:0.42,green:0.43,blue:0.39);static let sage=Color(red:0.72,green:0.80,blue:0.70);static let line=Color(red:0.88,green:0.86,blue:0.81)}
