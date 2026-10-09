import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack { Label("TwoNest", systemImage: "heart.house.fill").font(.system(size: 25, weight: .semibold, design: .serif)); Spacer(); Text("MAKE ROOM\nFOR SOMEONE").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Theme.muted) }
                        ZStack(alignment: .bottomLeading) {
                            GeometryReader { geo in Image("DateNightHero").resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped() }
                            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("A LITTLE SPARK. A BIGGER POSSIBILITY.").font(.system(size: 9, weight: .bold)).tracking(1.3)
                                Text("Someone worth\nmaking room for.").font(.system(size: 35, weight: .medium, design: .serif)).lineSpacing(-2)
                            }.foregroundStyle(.white).padding(24)
                        }.frame(height: 375).clipShape(RoundedRectangle(cornerRadius: 30)).nestScrollMotion()
                        Text("Thoughtful introductions. Real dates. A life that can grow together.").font(.system(size: 17)).lineSpacing(4).foregroundStyle(Theme.muted)
                        NavigationLink { AuthView(isSignup: true) } label: { HStack { Text("Find my person"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(ForestButton())
                        NavigationLink("Already a member? Log in") { AuthView(isSignup: false) }.font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        Label("Your pace. Your preferences. Your boundaries.", systemImage: "hand.raised").font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                    }.padding(24)
                }
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct AuthView: View {
    let isSignup: Bool
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var busy = false
    @FocusState private var focused: Bool
    private var valid: Bool {
        let parts = email.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !email.contains(" ")
    }
    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("TwoNest", systemImage: "heart.house.fill").font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(Theme.forest)
                    NestSculpture().frame(height: 175).accessibilityHidden(true)
                    Text(isSignup ? "Your next chapter\nstarts here." : "Welcome back\nto your space.").font(.system(size: 36, weight: .medium, design: .serif)).foregroundStyle(Theme.ink)
                    Text(isSignup ? "We’ll get to know you, what matters to you and who you’d love to meet. About five minutes, at your pace." : "Log in to pick up your introductions, conversations and plans.").font(.system(size: 16)).foregroundStyle(Theme.muted).lineSpacing(4)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Email address").font(.subheadline.weight(.semibold))
                        TextField("you@example.com", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.emailAddress).focused($focused).padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
                    }
                    if let error = session.error { Text(error).font(.subheadline).foregroundStyle(Theme.berry).accessibilityAddTraits(.updatesFrequently) }
                    Button { Task { await authenticate() } } label: {
                        HStack { if busy { ProgressView().tint(.white) }; Text(isSignup ? "Create account" : "Log in"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(ForestButton()).disabled(!valid || busy)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOCAL PREVIEW").font(.system(size: 10, weight: .bold)).tracking(1.2)
                        Text("Email-only access is for this local preview. Email verification and secure production sign-in still need to be connected.").font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }.foregroundStyle(Theme.muted).padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
                }.padding(24)
            }.scrollDismissesKeyboard(.interactively)
        }.navigationTitle(isSignup ? "Create account" : "Log in").navigationBarTitleDisplayMode(.inline).onAppear { session.error = nil }
    }
    private func authenticate() async {
        focused = false; busy = true; defer { busy = false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isSignup { await session.signUp(normalized) } else { await session.signIn(normalized) }
    }
}

struct GuidedOnboardingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    @State private var birthdayConfirmed = false
    @State private var pronouns = ""
    @State private var gender = ""
    @State private var intention = "serious_dating"
    @State private var area = ""
    @State private var seeking: Set<String> = []
    @State private var ageMin = 24
    @State private var ageMax = 40
    @State private var radius = 40.0
    @State private var interests: Set<String> = []
    @State private var availability: Set<String> = []
    @State private var bio = ""
    @State private var questions: [QuestionnaireQuestion] = []
    @State private var drafts: [String: QuestionnaireDraft] = [:]
    @State private var completedMember: Member?
    @State private var createdCount = 0
    @State private var matchingNotice: String?
    private let interestOptions = ["Cooking", "Travel", "Books", "Live music", "Outdoors", "Quiet weekends", "Running or fitness", "Museums and culture", "Trying new restaurants", "Games"]
    private let questionIDs = ["relationship_timeline", "children", "communication_style", "conflict_style"]
    private let titles = ["Make room for\nsomething real.", "First, a little\nabout you.", "What are you\nhoping to find?", "Who feels\nright for you?", "Let your\npersonality show.", "Go a little\ndeeper.", "This is\nyour starting point.", "You’re ready\nto connect."]
    private let subtitles = ["A few thoughtful steps, so your introductions start with what matters.", "Your first name appears on your profile. Your birthday stays private; TwoNest is for adults 18+.", "We use your intention to introduce people looking for the same kind of connection.", "These are your discovery preferences. You can change them whenever life changes.", "Give someone a few good reasons to start a conversation.", "Choose at least three answers for matching. Private answers are excluded; important differences can be deal-breakers.", "Your preferences shape introductions. Compatibility is a conversation starter, never a promise.", "The best part starts with a hello."]
    private var answerCount: Int { questions.filter { drafts[$0.id]?.isAnswered == true && drafts[$0.id]?.isPrivate == false }.count }
    private var canContinue: Bool {
        switch step {
        case 1: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && birthdayConfirmed && !gender.isEmpty && !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 3: return !seeking.isEmpty && ageMin <= ageMax
        case 4: return interests.count >= 3 && bio.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 && bio.count <= 600
        case 5: return answerCount >= 3
        default: return true
        }
    }
    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            if loading {
                VStack(spacing: 16) { ProgressView(); Text("Getting your space ready…").foregroundStyle(Theme.muted); if let error { Text(error).foregroundStyle(Theme.berry); Button("Try again") { Task { await load() } }; Button("Log out") { session.signOut() } } }.padding(24)
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 22) {
                                Color.clear.frame(height: 1).id("top")
                                Text(titles[step]).font(.system(size: 35, weight: .medium, design: .serif)).foregroundStyle(Theme.ink).lineSpacing(-1)
                                Text(subtitles[step]).font(.system(size: 15)).foregroundStyle(Theme.muted).lineSpacing(4)
                                stepContent
                                if let error { Text(error).font(.subheadline).foregroundStyle(Theme.berry).accessibilityAddTraits(.updatesFrequently) }
                            }.padding(.horizontal, 24).padding(.bottom, 28).id(step).transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : 20)))
                        }.scrollDismissesKeyboard(.interactively).onChange(of: step) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    }
                    footer
                }
            }
        }.task { await load() }
    }
    private var header: some View {
        VStack(spacing: 18) {
            HStack {
                Button { if step > 0 && step < 7 { changeStep(step - 1) } else { session.signOut() } } label: { Image(systemName: step > 0 && step < 7 ? "arrow.left" : "xmark").frame(width: 44, height: 44).background(Theme.paper, in: Circle()) }.accessibilityLabel(step > 0 && step < 7 ? "Previous step" : "Log out")
                Spacer(); Text("TwoNest").font(.system(size: 23, weight: .semibold, design: .serif)); Spacer()
                Text(step == 7 ? "READY" : "\(min(step + 1, 7)) / 7").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 44)
            }
            HStack(spacing: 5) { ForEach(0..<7) { index in Capsule().fill(index <= step ? Theme.forest : Theme.line).frame(height: 3) } }
        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 8)
    }
    private var footer: some View {
        VStack(spacing: 10) {
            Button { Task { await advance() } } label: {
                HStack { if saving { ProgressView().tint(.white) }; Text(step == 0 ? "Let’s get to know you" : step == 6 ? "Find my introductions" : step == 7 ? "Explore my introductions" : "Continue"); Spacer(); Image(systemName: "arrow.right") }
            }.buttonStyle(ForestButton()).disabled(!canContinue || saving)
            Text(step == 0 ? "Your progress is saved after each step." : step == 7 ? "Messages open when interest is mutual." : "Saved as you go · change your preferences anytime").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }.padding(24).background(Theme.cream).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0:
            NestSculpture().frame(height: 230).accessibilityHidden(true)
            VStack(spacing: 18) {
                journeyRow("01", "Your story", "A first name, a few interests, a little personality.")
                journeyRow("02", "Your kind of person", "Who you want to meet, and what you value.")
                journeyRow("03", "A real possibility", "Thoughtful introductions, with reasons to connect.")
            }
        case 1:
            VStack(alignment: .leading, spacing: 20) {
                field("First name", text: $name)
                VStack(alignment: .leading, spacing: 8) { Text("Date of birth").font(.subheadline.weight(.semibold)); DatePicker("Your birthday", selection: $birthDate, in: ...Date.now, displayedComponents: .date).datePickerStyle(.compact); Toggle("This is my date of birth", isOn: $birthdayConfirmed).font(.footnote) }.padding(16).background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
                Text("How do you describe your gender?").font(.subheadline.weight(.semibold))
                choiceGrid([("woman", "Woman"), ("man", "Man"), ("non binary", "Non-binary")], selected: Set([gender])) { gender = $0 }
                field("Pronouns (optional)", text: $pronouns)
                field("Your neighbourhood", text: $area, hint: "e.g. Hackney, London")
            }
        case 2:
            VStack(spacing: 12) {
                intentionCard("serious_dating", "A lasting relationship", "I’d love to build something meaningful.", "heart")
                intentionCard("dating", "Dating and seeing what grows", "Open to connection, without rushing the future.", "sparkles")
                intentionCard("friendship", "New friendships", "Good company and people to share life with.", "person.2")
            }
        case 3:
            VStack(alignment: .leading, spacing: 22) {
                Text("I’d like to meet").font(.headline)
                choiceGrid([("woman", "Women"), ("man", "Men"), ("non binary", "Non-binary people"), ("any", "All genders")], selected: seeking) { key in
                    if key == "any" { seeking = seeking == ["any"] ? [] : ["any"] }
                    else { seeking.remove("any"); toggle(key, in: &seeking) }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Partner age range").font(.headline)
                    Stepper("From \(ageMin)", value: $ageMin, in: 18...ageMax)
                    Stepper("To \(ageMax)", value: $ageMax, in: ageMin...120)
                    Text("Both people’s age and gender preferences must fit.").font(.footnote).foregroundStyle(Theme.muted)
                }.padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Preferred distance").font(.headline); Spacer(); Text("\(Int(radius)) km").foregroundStyle(Theme.forest) }
                    Slider(value: $radius, in: 1...250, step: 1)
                    Text("Your neighbourhood helps rank local introductions. Exact distance filtering needs the location service, which isn’t connected in this preview.").font(.footnote).foregroundStyle(Theme.muted)
                }.padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
            }
        case 4:
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("What lights you up?").font(.headline); Spacer(); Text("\(interests.count) selected").font(.caption).foregroundStyle(Theme.forest) }
                Text("Pick at least three.").font(.subheadline).foregroundStyle(Theme.muted)
                choiceGrid(interestOptions.map { ($0, $0) }, selected: interests) { toggle($0, in: &interests) }
                Text("A little about you").font(.headline)
                TextField("My ideal Sunday looks like…", text: $bio, axis: .vertical).lineLimit(3...6).padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
                Text("\(bio.count)/600 · at least 10 characters").font(.caption).foregroundStyle(Theme.muted)
                Text("When are you usually free?").font(.headline)
                choiceGrid([("weekends", "Weekends"), ("weekday evenings", "Weekday evenings"), ("weekday daytime", "Weekday daytime")], selected: availability) { toggle($0, in: &availability) }
            }
        case 5:
            VStack(alignment: .leading, spacing: 16) {
                Label("\(answerCount)/3 matching answers ready", systemImage: answerCount >= 3 ? "checkmark.circle.fill" : "circle.dotted").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.forest)
                ForEach(questions) { question in
                    CompatibilityChoiceCard(question: question, draft: binding(question.id))
                }
            }
        case 6:
            VStack(spacing: 14) {
                reviewCard("About you", "\(name) · \(gender.capitalized)\n\(area)", editStep: 1)
                reviewCard("What you’re looking for", intentionLabel + "\nAges \(ageMin)–\(ageMax) · " + seeking.sorted().map { $0 == "any" ? "All genders" : $0.capitalized }.joined(separator: ", "), editStep: 3)
                reviewCard("Your personality", interests.sorted().joined(separator: " · ") + "\n\n" + bio, editStep: 4)
                reviewCard("Your compatibility", "\(answerCount) answers ready for matching. Private answers are excluded.", editStep: 5)
                Label("You control who you connect with. A chat opens only after both people choose interest.", systemImage: "lock.shield").font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        default:
            NestSculpture().frame(height: 210).accessibilityHidden(true)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(createdCount > 0 ? "\(createdCount) introductions to explore" : "Your profile is ready").font(.title3.weight(.semibold))
                    Text(createdCount > 0 ? "We’ve used your intention, mutual preferences, interests and answers to find these introductions." : "No new compatible introduction is available right now. Explore hosted experiences or check Connect again as more members join.").font(.subheadline).foregroundStyle(Theme.muted)
                    if let matchingNotice { Text(matchingNotice).font(.footnote).foregroundStyle(Theme.berry) }
                }
            }
        }
    }
    private var intentionLabel: String { intention == "friendship" ? "Friendship" : intention == "dating" ? "Dating and seeing what grows" : "A lasting relationship" }
    private func journeyRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 18) { Text(number).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.berry).padding(.top, 4); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(Theme.muted) }; Spacer() }
    }
    private func field(_ label: String, text: Binding<String>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(label).font(.subheadline.weight(.semibold)); TextField(hint ?? label, text: text).padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 16)).autocorrectionDisabled() }
    }
    private func choiceGrid(_ choices: [(String, String)], selected: Set<String>, onSelect: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(choices, id: \.0) { key, label in
                Button { onSelect(key) } label: { HStack { Text(label).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.leading); Spacer(minLength: 4); if selected.contains(key) { Image(systemName: "checkmark").font(.caption.bold()) } }.padding(14).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(selected.contains(key) ? .white : Theme.ink).background(selected.contains(key) ? Theme.forest : Theme.paper, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(selected.contains(key) ? Theme.forest : Theme.line)) }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(key) ? [.isSelected] : [])
            }
        }
    }
    private func intentionCard(_ key: String, _ title: String, _ detail: String, _ icon: String) -> some View {
        Button { intention = key } label: {
            HStack(spacing: 14) { Image(systemName: icon).font(.title2).frame(width: 44); VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(intention == key ? .white.opacity(0.8) : Theme.muted) }; Spacer(minLength: 0); Image(systemName: intention == key ? "checkmark.circle.fill" : "circle").font(.title3) }.padding(20).foregroundStyle(intention == key ? .white : Theme.forest).background(intention == key ? Theme.forest : Theme.paper, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityAddTraits(intention == key ? [.isSelected] : [])
    }
    private func reviewCard(_ title: String, _ value: String, editStep: Int) -> some View {
        Card { VStack(alignment: .leading, spacing: 10) { HStack { Text(title).font(.headline); Spacer(); Button("Edit") { changeStep(editStep) }.font(.subheadline.weight(.semibold)) }; Text(value).font(.subheadline).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) } }
    }
    private func toggle(_ value: String, in set: inout Set<String>) { if set.contains(value) { set.remove(value) } else { set.insert(value) } }
    private func binding(_ id: String) -> Binding<QuestionnaireDraft> { Binding(get: { drafts[id] ?? QuestionnaireDraft(value: nil) }, set: { drafts[id] = $0 }) }
    private func changeStep(_ next: Int) { error = nil; withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) { step = next } }
    private static var dateFormatter: DateFormatter { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }
    private func load() async {
        guard let token = session.token else { return }
        do {
            let p: OnboardingProfile = try await session.api.get("/onboarding", token: token)
            let form: QuestionnaireForm = try await session.api.get("/questionnaire", token: token)
            name = p.first_name == "You" ? "" : p.first_name; pronouns = p.pronouns; gender = p.gender_identity; intention = p.intention; area = p.area
            if let raw = p.date_of_birth, let date = Self.dateFormatter.date(from: raw) { birthDate = date; birthdayConfirmed = true }
            seeking = Set(p.dating_preferences); ageMin = p.preferred_age_min ?? 24; ageMax = p.preferred_age_max ?? 40; radius = Double(p.search_radius_km)
            interests = Set(p.interests); availability = Set(p.availability); bio = p.bio
            let all = form.groups.flatMap(\.questions)
            questions = questionIDs.compactMap { id in all.first { $0.id == id } }
            for a in form.answers { drafts[a.question_id] = QuestionnaireDraft(value: a.value, importance: a.importance, dealBreaker: a.deal_breaker, isPrivate: a.is_private) }
            step = min(p.onboarding_step ?? 0, 6); error = nil; loading = false
        } catch { self.error = error.localizedDescription }
    }
    private func advance() async {
        if step == 7 { session.preferredTab = 1; session.user = completedMember; return }
        guard canContinue, let token = session.token else { return }
        saving = true; error = nil; defer { saving = false }
        do {
            if step == 6 {
                let member: Member = try await session.api.send("/onboarding/complete", method: "POST", token: token)
                completedMember = member
                do { let result: IntroductionRefreshResponse = try await session.api.send("/introductions/refresh", method: "POST", token: token); createdCount = result.created_count }
                catch { matchingNotice = "Your profile was saved. Introductions couldn’t refresh just now; try again in Connect." }
                changeStep(7); return
            }
            var payload: [String: Any] = ["onboarding_step": step + 1]
            switch step {
            case 1: payload.merge(["first_name": name.trimmingCharacters(in: .whitespacesAndNewlines), "date_of_birth": Self.dateFormatter.string(from: birthDate), "pronouns": pronouns, "gender_identity": gender, "area": area.trimmingCharacters(in: .whitespacesAndNewlines)]) { _, new in new }
            case 2: payload["intention"] = intention
            case 3: payload.merge(["dating_preferences": seeking.sorted(), "preferred_age_min": ageMin, "preferred_age_max": ageMax, "search_radius_km": Int(radius)]) { _, new in new }
            case 4: payload.merge(["bio": bio.trimmingCharacters(in: .whitespacesAndNewlines), "interests": interests.sorted(), "availability": availability.sorted()]) { _, new in new }
            case 5:
                let answers: [[String: Any]] = questions.compactMap { q in guard let d = drafts[q.id], d.isAnswered, let v = d.value else { return nil }; return ["question_id": q.id, "value": v.foundationValue, "importance": d.importance, "deal_breaker": d.dealBreaker, "is_private": d.isPrivate] }
                let _: QuestionnaireSavedResponse = try await session.api.send("/questionnaire/answers", method: "PUT", body: ["answers": answers], token: token)
            default: break
            }
            let _: OnboardingProfile = try await session.api.send("/onboarding", method: "PATCH", body: payload, token: token)
            changeStep(step + 1)
        } catch { self.error = error.localizedDescription }
    }
}

struct CompatibilityChoiceCard: View {
    let question: QuestionnaireQuestion
    @Binding var draft: QuestionnaireDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(question.prompt).font(.system(size: 20, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
            ForEach(question.options ?? [], id: \.self) { option in
                Button { draft.value = .string(option) } label: {
                    HStack { Text(option).font(.subheadline).multilineTextAlignment(.leading); Spacer(); Image(systemName: draft.value?.stringValue == option ? "checkmark.circle.fill" : "circle") }.padding(14).foregroundStyle(draft.value?.stringValue == option ? Theme.forest : Theme.muted).background(draft.value?.stringValue == option ? Theme.sage.opacity(0.25) : Theme.cream, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain).accessibilityAddTraits(draft.value?.stringValue == option ? [.isSelected] : [])
            }
            Picker("How much does this matter?", selection: $draft.importance) { Text("A little").tag(1); Text("Some").tag(2); Text("A lot").tag(3) }.font(.footnote)
            Toggle("Treat differences as a deal-breaker", isOn: $draft.dealBreaker).font(.footnote)
            Toggle("Keep private, exclude from matching", isOn: $draft.isPrivate).font(.footnote)
        }.padding(20).background(Theme.paper, in: RoundedRectangle(cornerRadius: 23))
    }
}
