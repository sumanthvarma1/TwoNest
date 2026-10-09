import SwiftUI

struct MessagesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: Int
    @State private var rows: [Conversation] = []
    @State private var loading = true
    @State private var error: String?
    @State private var readIDs: [String: Int] = [:]
    private var storageKey: String { "twonest.message.read.\(session.user?.id ?? "")" }
    private var sortedRows: [Conversation] { rows.sorted { ($0.messages.last?.created_at ?? "") > ($1.messages.last?.created_at ?? "") } }
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.cream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack { VStack(alignment: .leading, spacing: 7) { Text("KEEP THE SPARK GOING").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(Theme.berry); Text("Conversations.").font(.system(size: 34, weight: .medium, design: .serif)) }; Spacer(); Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 27, weight: .light)).foregroundStyle(Theme.forest) }
                        if loading && rows.isEmpty { ProgressView("Loading your conversations…").frame(maxWidth: .infinity).padding(40) }
                        else if rows.isEmpty && error == nil { emptyState }
                        else {
                            if !rows.isEmpty { Text("\(rows.count) CONNECTION\(rows.count == 1 ? "" : "S")").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Theme.muted) }
                            LazyVStack(spacing: 12) {
                                ForEach(sortedRows) { row in
                                    NavigationLink { ChatDetailView(conversation: row, onRead: { markRead(row.id, lastID: $0) }, onClosed: { rows.removeAll { $0.id == row.id } }) } label: { inboxRow(row) }.buttonStyle(.plain)
                                }
                            }
                        }
                        if let error { VStack(alignment: .leading, spacing: 12) { Text(error).font(.subheadline).foregroundStyle(Theme.berry); Button("Try again") { Task { await load() } }.buttonStyle(OutlineButton()) } }
                        Label("Conversations open after mutual interest.", systemImage: "lock.shield").font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }.padding(24)
                }.refreshable { await load() }
            }.toolbar(.hidden, for: .navigationBar)
        }.task(id: "\(selection)-\(scenePhase)") {
            guard selection == 3 && scenePhase == .active else { return }
            readIDs = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
            await load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                guard !Task.isCancelled else { break }; await load()
            }
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Theme.sage.opacity(0.3)).frame(width: 190, height: 105).rotationEffect(.degrees(-9)).offset(x: -26, y: -14)
                VStack(alignment: .leading, spacing: 8) { Text("A good conversation").font(.system(size: 18, weight: .medium, design: .serif)); HStack(spacing: 6) { ForEach(0..<3) { _ in Circle().fill(Theme.berry.opacity(0.6)).frame(width: 6, height: 6) } }; Text("starts with mutual interest.").font(.footnote).foregroundStyle(Theme.muted) }.padding(23).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24)).rotation3DEffect(.degrees(-10), axis: (x: 0.3, y: 1, z: 0), perspective: 0.5).shadow(color: Theme.forest.opacity(0.08), radius: 18, y: 14)
            }.frame(maxWidth: .infinity).frame(height: 180).accessibilityHidden(true)
            Text("Your first hello\nis still ahead.").font(.system(size: 29, weight: .medium, design: .serif))
            Text("Explore your introductions and let someone know you’re interested. When they feel the same, your conversation appears here.").font(.system(size: 15)).lineSpacing(4).foregroundStyle(Theme.muted)
            Button { selection = 1 } label: { HStack { Text("Explore introductions"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(ForestButton())
            Button("Meet through an experience") { selection = 2 }.buttonStyle(OutlineButton())
        }.padding(22).background(Theme.paper.opacity(0.5), in: RoundedRectangle(cornerRadius: 28)).nestScrollMotion()
    }
    private func inboxRow(_ row: Conversation) -> some View {
        let unread = row.messages.filter { $0.id > (readIDs[row.id] ?? 0) && $0.sender_id != session.user?.id }.count
        return HStack(spacing: 15) {
            Text(String(row.with.prefix(1))).font(.system(size: 24, weight: .medium, design: .serif)).foregroundStyle(Theme.forest).frame(width: 58, height: 58).background(Theme.sage.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 7) { HStack { Text(row.with).font(.headline).foregroundStyle(Theme.ink); Spacer(); if let last = row.messages.last { Text(messageDate(last.created_at, timeOnly: false)).font(.caption).foregroundStyle(Theme.muted) } }; Text(row.messages.last.map { ($0.sender_id == session.user?.id ? "You: " : "") + $0.body } ?? "You both chose to connect. Say hello.").font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2) }
            if unread > 0 { Text("\(unread)").font(.caption.bold()).foregroundStyle(.white).padding(7).background(Theme.berry, in: Circle()).accessibilityLabel("\(unread) unread messages") }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }.padding(18).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24))
    }
    private func markRead(_ id: String, lastID: Int) { readIDs[id] = max(readIDs[id] ?? 0, lastID); UserDefaults.standard.set(readIDs, forKey: storageKey) }
    private func load() async {
        guard let token = session.token else { return }
        defer { loading = false }
        do { rows = try await session.api.get("/conversations", token: token); error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ChatDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let conversation: Conversation
    let onRead: (Int) -> Void
    let onClosed: () -> Void
    @State private var messages: [MessageItem]
    @State private var draft = ""
    @State private var sending = false
    @State private var closed = false
    @State private var error: String?
    @State private var confirmUnmatch = false
    @State private var showReport = false
    @FocusState private var focused: Bool
    init(conversation: Conversation, onRead: @escaping (Int) -> Void, onClosed: @escaping () -> Void) { self.conversation = conversation; self.onRead = onRead; self.onClosed = onClosed; _messages = State(initialValue: conversation.messages) }
    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        VStack(spacing: 8) { Image(systemName: "heart.circle").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.berry); Text("You and \(conversation.with) chose to connect.").font(.subheadline.weight(.semibold)); Text("Keep it thoughtful. Share at your own pace.").font(.footnote).foregroundStyle(Theme.muted) }.padding(.vertical, 24)
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Make the first hello yours.").font(.system(size: 23, weight: .medium, design: .serif))
                                Text("Ask about something you’re curious about, or borrow a starting point.").font(.subheadline).foregroundStyle(Theme.muted)
                                ForEach(["What does your ideal weekend look like?", "What’s a place you’ve loved exploring recently?", "What’s something you’re looking forward to?"], id: \.self) { prompt in Button(prompt) { draft = prompt; focused = true }.font(.subheadline).multilineTextAlignment(.leading).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.paper, in: RoundedRectangle(cornerRadius: 16)) }
                            }.padding(20)
                        }
                        ForEach(messages) { item in messageBubble(item) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 20).padding(.bottom, 20)
                }.scrollDismissesKeyboard(.interactively).onAppear { proxy.scrollTo("bottom", anchor: .bottom) }.onChange(of: messages.last?.id) { _, _ in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(conversation.with).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { if conversation.member_id != nil { Button("Report a concern", systemImage: "flag") { showReport = true } }; Button("Unmatch", systemImage: "person.crop.circle.badge.minus", role: .destructive) { confirmUnmatch = true } } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Conversation options") } } }
            .confirmationDialog("End this connection?", isPresented: $confirmUnmatch, titleVisibility: .visible) { Button("Unmatch", role: .destructive) { Task { await unmatch() } }; Button("Cancel", role: .cancel) {} } message: { Text("The conversation will close for both people.") }
            .sheet(isPresented: $showReport) { if let memberID = conversation.member_id { SafetyReportSheet(memberID: memberID, firstName: conversation.with) { notice in error = notice } } }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                onRead(messages.last?.id ?? 0); await refresh()
                while !Task.isCancelled && !closed {
                    do { try await Task.sleep(for: .seconds(8)) } catch { break }
                    guard !Task.isCancelled else { break }; await refresh()
                }
            }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error { HStack { Text(error).font(.footnote).foregroundStyle(Theme.berry); Spacer(); Button { self.error = nil } label: { Image(systemName: "xmark").font(.caption) }.accessibilityLabel("Dismiss message") } }
            if closed { Button("Return to conversations") { onClosed(); dismiss() }.buttonStyle(OutlineButton()) }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message \(conversation.with)…", text: $draft, axis: .vertical).disabled(closed).lineLimit(1...5).focused($focused).padding(14).background(Theme.cream, in: RoundedRectangle(cornerRadius: 20)).submitLabel(.send).onSubmit { Task { await send() } }
                Button { Task { await send() } } label: { Group { if sending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.headline) } }.foregroundStyle(.white).frame(width: 48, height: 48).background(Theme.forest, in: Circle()) }.disabled(closed || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 4000).accessibilityLabel("Send message")
            }
            if draft.count > 4000 { Text("Keep your message under 4,000 characters.").font(.caption).foregroundStyle(Theme.berry) }
        }.padding(16).background(Theme.paper).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
    private func messageBubble(_ item: MessageItem) -> some View {
        let mine = item.sender_id == session.user?.id
        return HStack {
            if mine { Spacer(minLength: 45) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 5) { Text(item.body).font(.system(size: 16)).foregroundStyle(mine ? .white : Theme.ink).padding(.horizontal, 16).padding(.vertical, 13).background(mine ? Theme.forest : Theme.paper, in: RoundedRectangle(cornerRadius: 21)); Text(messageDate(item.created_at, timeOnly: true)).font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 5) }
            if !mine { Spacer(minLength: 45) }
        }.accessibilityElement(children: .combine).accessibilityLabel("\(mine ? "You" : conversation.with): \(item.body), \(messageDate(item.created_at, timeOnly: true))")
    }
    private func refresh() async {
        guard !closed, let token = session.token else { return }
        do { let result: Conversation = try await session.api.get("/conversations/\(conversation.id)", token: token); var combined = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) }); for item in result.messages { combined[item.id] = item }; messages = combined.values.sorted { $0.id < $1.id }; onRead(messages.last?.id ?? 0); error = nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; if (error as? APIError)?.statusCode == 404 { closed = true } } }
    }
    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !closed, !body.isEmpty, body.count <= 4000, !sending, let token = session.token else { return }
        sending = true; error = nil; defer { sending = false }
        do { let message: MessageItem = try await session.api.send("/conversations/\(conversation.id)/messages", method: "POST", body: ["body": body], token: token); if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }; draft = ""; onRead(message.id) }
        catch { self.error = error.localizedDescription; if (error as? APIError)?.statusCode == 404 { closed = true } }
    }
    private func unmatch() async {
        do { let _: UnmatchResponse = try await session.api.send("/conversations/\(conversation.id)/unmatch", method: "POST", token: session.token); onClosed(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private func messageDate(_ raw: String, timeOnly: Bool) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var normalized = raw
    let timePart = raw.dropFirst(min(10, raw.count))
    if !timePart.contains("Z") && !timePart.contains("+") && !timePart.contains("-") { normalized += "Z" }
    let parsed = formatter.date(from: normalized)
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = parsed ?? formatter.date(from: normalized) else { return "" }
    if timeOnly { return date.formatted(date: .omitted, time: .shortened) }
    if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
    return date.formatted(.dateTime.month(.abbreviated).day())
}
