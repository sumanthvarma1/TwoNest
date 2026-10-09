import SwiftUI
import MapKit
import CoreLocation
import Observation

@MainActor @Observable
final class ActivityLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var message: String?
    var locating = false
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() {
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined: locating = true; manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locating = true; manager.requestLocation()
        case .denied, .restricted: locating = false; message = "Location is off. Search a neighbourhood instead, or enable location in Settings."
        @unknown default: locating = false
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if locating && [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { manager.requestLocation() }
        else if [.denied, .restricted].contains(manager.authorizationStatus) { locating = false; message = "Location is off. You can still search an area." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locating = false
        guard let last = locations.last, last.horizontalAccuracy >= 0, abs(last.timestamp.timeIntervalSinceNow) < 120 else { message = "No recent location. Try again or search an area."; return }
        coordinate = last.coordinate
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { locating = false; message = "Couldn’t locate you. Try again or search a neighbourhood." }
}

@MainActor @Observable
final class ActivityLiveConnection {
    var connected = false
    var reconnecting = false
    func run(api: APIClient, token: String, onRefresh: @escaping @MainActor () async -> Void) async {
        defer { connected = false; reconnecting = false }
        var delay = 2
        while !Task.isCancelled {
            guard var parts = URLComponents(url: api.baseURL.appending(path: "activities/live"), resolvingAgainstBaseURL: false) else { return }
            parts.scheme = parts.scheme == "https" ? "wss" : "ws"
            guard let url = parts.url else { return }
            var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let socket = URLSession.shared.webSocketTask(with: request); socket.resume()
            do {
                try await withTaskCancellationHandler {
                    while !Task.isCancelled {
                        _ = try await socket.receive()
                        connected = true; reconnecting = false; delay = 2
                        await onRefresh()
                    }
                } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
            } catch { connected = false; reconnecting = !Task.isCancelled }
            socket.cancel(with: .goingAway, reason: nil)
            guard !Task.isCancelled else { break }
            await onRefresh() // REST fallback while the connection recovers.
            do { try await Task.sleep(for: .seconds(delay)) } catch { break }
            delay = min(delay * 2, 30)
        }
    }
}

struct ActivityPlaceChoice: Identifiable {
    let id = UUID(); let name: String; let address: String; let coordinate: CLLocationCoordinate2D; let city: String
}

struct ActivityPlaceSearch: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSelect: (ActivityPlaceChoice) -> Void
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var error: String?
    @State private var busy = false
    @State private var lookup: MKLocalSearch?
    var body: some View {
        NavigationStack {
            List {
                Section { TextField("Park, café, address or neighbourhood", text: $query).autocorrectionDisabled().submitLabel(.search).onSubmit { Task { await search() } }; Button("Search places") { Task { await search() } }.disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); if busy { ProgressView("Searching…") }; if let error { Text(error).foregroundStyle(Theme.berry) } }
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button { let place = item.placemark; onSelect(.init(name: item.name ?? "Selected place", address: [place.subThoroughfare, place.thoroughfare, place.locality, place.administrativeArea].compactMap { $0 }.joined(separator: " "), coordinate: place.coordinate, city: place.locality ?? place.subAdministrativeArea ?? "")); dismiss() } label: { VStack(alignment: .leading, spacing: 5) { Text(item.name ?? "Selected place").foregroundStyle(Theme.ink); Text(item.placemark.title ?? "").font(.caption).foregroundStyle(Theme.muted) } }
                }
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }.onDisappear { lookup?.cancel() }
        }
    }
    private func search() async {
        lookup?.cancel(); busy = true; error = nil; defer { busy = false }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query; request.region = ActivityMapDiscovery.launchRegion
        let search = MKLocalSearch(request: request); lookup = search
        do { let response = try await search.start(); guard lookup === search else { return }; results = response.mapItems; if results.isEmpty { error = "No places found. Include the city or postcode." } }
        catch { if lookup === search { self.error = "Place search is unavailable. Try again." } }
    }
}

struct ActivityMapDiscovery: View {
    static let launchRegion = MKCoordinateRegion(center: .init(latitude: 40.69, longitude: -74.13), span: .init(latitudeDelta: 0.48, longitudeDelta: 0.55))
    @Environment(SessionStore.self) private var session
    let category: String
    let mode: String
    let refresh: Int
    let ownPlans: [ActivityPlan]
    let onOpen: (String) -> Void
    let onInvite: (ActivityMapMember) -> Void
    let onPlans: ([ActivityPlan]) -> Void
    @State private var location = ActivityLocation()
    @State private var camera: MapCameraPosition = .region(launchRegion)
    @State private var center = launchRegion.center
    @State private var radius = 10.0
    @State private var plans: [ActivityPlan] = []
    @State private var people: [ActivityMapMember] = []
    @State private var layer = "both"
    @State private var searching = false
    @State private var areaName = "NYC & New Jersey"
    @State private var error: String?
    @State private var loading = true
    private var mapPlans: [ActivityPlan] {
        plans + ownPlans.filter { plan in
            guard let lat = plan.latitude, let lon = plan.longitude, !plan.isEnded else { return false }
            return CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: CLLocation(latitude: lat, longitude: lon)) <= radius * 1000 && (category.isEmpty || category == plan.category)
        }
    }
    private var queryID: String { "\(category)-\(mode)-\(refresh)-\(center.latitude)-\(center.longitude)-\(radius)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Find your company", systemImage: "map").font(.headline); Spacer(); Button { searching = true } label: { Label("Search area", systemImage: "magnifyingglass").font(.caption.weight(.semibold)) } }
            Picker("Show on map", selection: $layer) { Text("People & plans").tag("both"); Text("People").tag("people"); Text("Plans").tag("plans") }.pickerStyle(.segmented)
            Map(position: $camera) {
                if let coordinate = location.coordinate { Annotation("You", coordinate: coordinate) { Image(systemName: "location.fill").padding(10).background(.blue, in: Circle()).foregroundStyle(.white) } }
                if layer != "people" {
                    ForEach(mapPlans.filter { $0.mode == "in_person" && $0.latitude != nil }) { plan in
                        Annotation(plan.title, coordinate: .init(latitude: plan.latitude!, longitude: plan.longitude!)) {
                            Button { onOpen(plan.id) } label: { Image(systemName: ActivityCategory.find(plan.category).icon).font(.headline).foregroundStyle(.white).padding(13).background(Theme.forest, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 3)).shadow(radius: 3) }.accessibilityLabel("\(plan.title), with \(plan.host.first_name). Open request.")
                        }
                    }
                }
                if layer != "plans" && mode != "online" {
                    ForEach(people) { person in
                        Annotation(person.member.first_name, coordinate: .init(latitude: person.latitude, longitude: person.longitude)) {
                            Button { onInvite(person) } label: { Text(String(person.member.first_name.prefix(1))).font(.headline).foregroundStyle(Theme.forest).frame(width: 40, height: 40).background(Theme.blush, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3)).overlay(alignment: .bottomTrailing) { Circle().fill(Theme.forest).frame(width: 11, height: 11).overlay(Circle().stroke(.white, lineWidth: 2)) }.shadow(radius: 3) }.accessibilityLabel("\(person.member.first_name), available nearby. View and invite.")
                        }
                    }
                }
                MapCircle(center: center, radius: radius * 1000).foregroundStyle(Theme.forest.opacity(0.045)).stroke(Theme.forest.opacity(0.2), lineWidth: 1)
            }.mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.cafe, .park, .restaurant, .publicTransport]))).mapControls { MapCompass(); MapScaleView() }.onMapCameraChange(frequency: .onEnd) { context in center = context.region.center }.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 25))
                .overlay(alignment: .topLeading) { Text(areaName).font(.caption.weight(.semibold)).padding(10).background(.regularMaterial, in: Capsule()).padding(12) }
                .overlay(alignment: .bottomTrailing) { Button { location.request() } label: { Image(systemName: location.locating ? "hourglass" : "location.fill").padding(13).background(Theme.paper, in: Circle()).shadow(radius: 2) }.accessibilityLabel("Use my location").padding(12) }
            HStack { Text("Within \(Int(radius)) km").font(.caption.weight(.semibold)); Slider(value: $radius, in: 1...50, step: 1).tint(Theme.forest); if loading { ProgressView() } }
            HStack(spacing: 15) { Label("\(people.count) available", systemImage: "person.fill"); Label("\(mapPlans.filter { $0.mode == "in_person" }.count) plans", systemImage: "mappin") }.font(.caption).foregroundStyle(Theme.forest)
            Text("Pins show approximate areas, not someone’s exact position. Tap a person to invite them to a plan; they choose whether to accept.").font(.caption).foregroundStyle(Theme.muted)
            if people.isEmpty && mapPlans.filter({ $0.mode == "in_person" }).isEmpty && !loading { Text("No map-visible people or plans in this area yet. Try a wider radius or make yourself available.").font(.footnote).foregroundStyle(Theme.muted) }
            if let message = location.message { Text(message).font(.caption).foregroundStyle(Theme.berry) }
            if let error { Text(error).font(.caption).foregroundStyle(Theme.berry) }
        }.sheet(isPresented: $searching) { ActivityPlaceSearch(title: "Find an area") { choice in areaName = choice.name; center = choice.coordinate; camera = .region(.init(center: center, span: .init(latitudeDelta: radius/45, longitudeDelta: radius/35))) } }
            .onChange(of: location.coordinate?.latitude) { _, _ in if let coordinate = location.coordinate { center = coordinate; areaName = "Around you"; camera = .region(.init(center: coordinate, span: .init(latitudeDelta: radius/45, longitudeDelta: radius/35))) } }
            .task(id: queryID) { do { try await Task.sleep(for: .milliseconds(350)) } catch { return }; await load() }
    }
    private func load() async {
        guard let token = session.token else { return }; loading = true; defer { loading = false }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "latitude", value: String((center.latitude / 0.005).rounded() * 0.005)), URLQueryItem(name: "longitude", value: String((center.longitude / 0.005).rounded() * 0.005)), URLQueryItem(name: "radius_km", value: String(radius)), URLQueryItem(name: "category", value: category)]
        do {
            let people: [ActivityMapMember] = try await session.api.get("/activities/nearby-members?" + (query.percentEncodedQuery ?? ""), token: token)
            query.queryItems?.append(URLQueryItem(name: "mode", value: mode))
            let plans: [ActivityPlan] = try await session.api.get("/activities?" + (query.percentEncodedQuery ?? ""), token: token)
            guard !Task.isCancelled else { return }; self.people = mode == "online" ? [] : people; self.plans = plans; onPlans(plans); error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ActivityInviteSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let person: ActivityMapMember
    let onCreate: () -> Void
    @State private var plans: [ActivityPlan] = []
    @State private var notice: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Invite \(person.member.first_name)").font(.system(size: 27, weight: .medium, design: .serif)); Text("Approximately \(person.approx_distance_km.formatted()) km away · available until \(ActivityDates.parse(person.expires_at)?.formatted(date: .omitted, time: .shortened) ?? "soon")").font(.caption).foregroundStyle(Theme.muted); Text(person.categories.isEmpty ? "Open to any activity" : person.categories.map { ActivityCategory.find($0).title }.joined(separator: " · ")); if !person.member.bio.isEmpty { Text(person.member.bio) }; Text("Choose a plan you host. They receive an invitation and decide whether to join. Chat opens only if they accept.").font(.footnote).foregroundStyle(Theme.muted) }
                Section("Your open plans") { ForEach(plans) { plan in Button { Task { await invite(plan) } } label: { VStack(alignment: .leading, spacing: 5) { Text(plan.title); Text(ActivityDates.display(plan.starts_at)).font(.caption).foregroundStyle(Theme.muted) } }.disabled(busy) }; if plans.isEmpty { Text("No open plan fits their activities and availability window.").font(.subheadline) }; Button("Create a plan") { dismiss(); onCreate() } }
                if let notice { Section { Text(notice).foregroundStyle(Theme.forest) } }
            }.navigationTitle("A little company").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }.task { do { let mine: [ActivityPlan] = try await session.api.get("/activities/mine", token: session.token ?? ""); plans = mine.filter { $0.is_host && $0.status == "open" && (person.categories.isEmpty || person.categories.contains($0.category)) && (ActivityDates.parse($0.starts_at) ?? .distantFuture) <= (ActivityDates.parse(person.expires_at) ?? .distantPast) } } catch { notice = error.localizedDescription } }
        }
    }
    private func invite(_ plan: ActivityPlan) async { busy = true; defer { busy = false }; do { let _: ActivityPlan = try await session.api.send("/activities/\(plan.id)/invite", method: "POST", body: ["member_id": person.id], token: session.token); notice = "Invitation sent. You’ll see them in the plan when they accept."; plans.removeAll { $0.id == plan.id } } catch { notice = error.localizedDescription } }
}


@MainActor private final class ActivityDirectionsQuery {
    let directions: MKDirections
    init(_ request: MKDirections.Request) { directions = MKDirections(request: request) }
    func calculate() async throws -> MKRoute? { try await directions.calculate().routes.first }
    func cancel() { directions.cancel() }
}

struct ActivityTravelView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let plan: ActivityPlan
    @State private var location = ActivityLocation()
    @State private var origin: ActivityPlaceChoice?
    @State private var choosingOrigin = false
    @State private var walking: MKRoute?
    @State private var driving: MKRoute?
    @State private var transit: ActivityTransitResponse?
    @State private var transitMode = "all"
    @State private var selectedRoute = "walking"
    @State private var busy = false
    @State private var error: String?
    @State private var routeNotice: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var nycTaxiTrip = false
    private var privateDestination: Bool { plan.is_host || plan.my_join_status == "accepted" }
    private var destination: CLLocationCoordinate2D? {
        let lat = privateDestination ? plan.meeting_latitude ?? plan.latitude : plan.latitude
        let lon = privateDestination ? plan.meeting_longitude ?? plan.longitude : plan.longitude
        guard let lat, let lon else { return nil }; return .init(latitude: lat, longitude: lon)
    }
    private var route: MKRoute? { selectedRoute == "walking" ? walking : driving }
    private var destinationName: String { privateDestination ? plan.meeting_name ?? plan.area : "Approximate plan area" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) { Text("A plan worth showing up for.").font(.system(size: 28, weight: .medium, design: .serif)); Text(destinationName).font(.headline); Text(privateDestination ? "Compare your journey to the meetup point." : "This is a travel preview to the approximate area. The exact meeting point opens after you’re accepted; travel times may change.").font(.footnote).foregroundStyle(Theme.muted) }
                    Map(position: $camera) {
                        if let destination { Marker(destinationName, coordinate: destination).tint(Theme.berry) }
                        if let origin { Marker("Start", coordinate: origin.coordinate).tint(Theme.forest) }
                        if let route { MapPolyline(route.polyline).stroke(Theme.forest, lineWidth: 5) }
                    }.mapStyle(.standard(elevation: .realistic)).frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 24))
                    Card { VStack(alignment: .leading, spacing: 14) {
                        Text("Where are you starting?").font(.headline)
                        if let origin { Label(origin.name, systemImage: "location").font(.subheadline); if !origin.address.isEmpty { Text(origin.address).font(.caption).foregroundStyle(Theme.muted) } }
                        HStack { Button(location.locating ? "Locating…" : "My location") { location.request() }.buttonStyle(OutlineButton()).disabled(location.locating); Button("Choose a place") { choosingOrigin = true }.buttonStyle(OutlineButton()) }
                        Picker("Transit preference", selection: $transitMode) { Text("Bus & train").tag("all"); Text("Prefer bus").tag("bus") }.pickerStyle(.segmented)
                        Button { Task { await compare() } } label: { HStack { if busy { ProgressView().tint(.white) }; Text(busy ? "Comparing routes…" : "Compare routes & cost"); Spacer(); Image(systemName: "arrow.right") } }.buttonStyle(ForestButton()).disabled(origin == nil || destination == nil || busy)
                        Text("Your starting point is used by route providers to plan this journey. It isn’t shared with Rally members.").font(.caption).foregroundStyle(Theme.muted)
                        if let message = location.message { Text(message).font(.footnote).foregroundStyle(Theme.berry) }
                    } }
                    if walking != nil || driving != nil {
                        Picker("Route on map", selection: $selectedRoute) { Text("Walk").tag("walking"); Text("Drive").tag("driving") }.pickerStyle(.segmented)
                        if let walking { transportCard("Walk", icon: "figure.walk", route: walking, cost: "$0", detail: "Walking route · no transport fare", mode: MKLaunchOptionsDirectionsModeWalking) }
                        if let driving { transportCard("Drive", icon: "car", route: driving, cost: "Fuel + parking", detail: "Travel time estimate. Fuel, tolls and parking depend on your trip.", mode: MKLaunchOptionsDirectionsModeDriving) }
                    }
                    if let routeNotice { Text(routeNotice).font(.footnote).foregroundStyle(Theme.muted) }
                    if let transit {
                        Text("Bus & train").font(.system(size: 25, weight: .medium, design: .serif))
                        Text(transit.notice).font(.footnote).foregroundStyle(Theme.muted)
                        ForEach(transit.routes) { itinerary in
                            Card { VStack(alignment: .leading, spacing: 13) {
                                HStack { Label("\(Int(ceil(itinerary.duration_seconds / 60))) min", systemImage: "tram").font(.headline); Spacer(); Text(itinerary.fareLabel).font(.headline).foregroundStyle(Theme.forest) }
                                ForEach(Array(itinerary.steps.enumerated()), id: \.offset) { _, step in
                                    HStack(alignment: .top, spacing: 10) { Image(systemName: step.mode == "WALK" ? "figure.walk" : step.vehicle == "BUS" ? "bus" : "tram").frame(width: 20).foregroundStyle(Theme.forest); VStack(alignment: .leading, spacing: 4) { Text(step.line.isEmpty ? step.instruction : step.line + (step.headsign.isEmpty ? "" : " → " + step.headsign)).font(.subheadline.weight(.medium)); if !step.departure_stop.isEmpty { Text(step.departure_stop + " → " + step.arrival_stop).font(.caption).foregroundStyle(Theme.muted) }; if !step.departure_time.isEmpty { Text("Departs " + ActivityDates.display(step.departure_time)).font(.caption).foregroundStyle(Theme.muted) } } }
                                }
                                Text("Google Maps").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                                Button("Open this journey in Google Maps") { openPlanner() }.buttonStyle(OutlineButton())
                            } }
                        }
                    }
                    Card { VStack(alignment: .leading, spacing: 13) {
                        Label("Local transit budget", systemImage: "dollarsign.circle").font(.headline)
                        Text("NYC subway / local bus: $3.00 base fare").font(.subheadline.weight(.semibold))
                        Text("Reference fare, not the total for this trip. Express buses, commuter rail, PATH and NJ TRANSIT have different fares; transfers and ticket choices can affect cost.").font(.footnote).foregroundStyle(Theme.muted)
                        Link("MTA fare information", destination: URL(string: "https://www.mta.info/fares")!).font(.caption)
                        Link("NJ TRANSIT fares & tickets", destination: URL(string: "https://www.njtransit.com/tickets-and-fares")!).font(.caption)
                        Button("Bus & train directions in Apple Maps") { openApple(MKLaunchOptionsDirectionsModeTransit) }.buttonStyle(OutlineButton())
                        Button("Bus & train directions in Google Maps") { openPlanner() }.buttonStyle(OutlineButton())
                    } }
                    Card { VStack(alignment: .leading, spacing: 13) {
                        Label("Cab or Uber", systemImage: "car.side").font(.headline)
                        if let driving { Text("Drive estimate · \(Int(ceil(driving.expectedTravelTime / 60))) min · \(miles(driving.distance))").font(.subheadline) }
                        if nycTaxiTrip, privateDestination, let driving {
                            let baseline = 4.5 + ceil(driving.distance / 1609.344 * 5) * 0.7
                            Text("NYC taxi meter baseline ≈ " + baseline.formatted(.currency(code: "USD"))).font(.headline).foregroundStyle(Theme.forest)
                            Text("Distance-based planning estimate for a standard NYC trip. Includes the initial charge and $1.50 standard surcharges. Slow traffic, congestion charges, time-of-day extras, tolls and tip add to this. Airport and trips outside NYC need a separate quote.").font(.footnote).foregroundStyle(Theme.muted)
                        } else { Text("Check a live quote for NYC / New Jersey trips. Cross-state, airport and local cab prices differ.").font(.footnote).foregroundStyle(Theme.muted) }
                        Text("Uber confirms the price and pickup time before you book. Rally doesn’t book or charge for a ride.").font(.footnote).foregroundStyle(Theme.muted)
                        Button("Check price in Uber") { openUber() }.buttonStyle(ForestButton()).disabled(destination == nil || !privateDestination)
                        if !privateDestination { Text("Uber destination opens after acceptance, when the exact meetup point is shared.").font(.caption).foregroundStyle(Theme.muted) }
                        Link("Cab quotes with Curb", destination: URL(string: "https://mobileapp.gocurb.com/")!).font(.subheadline.weight(.semibold))
                        Link("NYC taxi fares / other e-hail options", destination: URL(string: "https://www.nyc.gov/site/tlc/passengers/taxi-fare.page")!).font(.caption)
                    } }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.berry) }
                    Text("Route times and provider fares are estimates. Check current service and the final fare with the operator.").font(.caption).foregroundStyle(Theme.muted)
                }.padding(24)
            }.background(Theme.cream).navigationTitle("Get there").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .sheet(isPresented: $choosingOrigin) { ActivityPlaceSearch(title: "Your starting point") { origin = $0; clearRoutes() } }
                .onChange(of: location.coordinate?.latitude) { _, _ in if let coordinate = location.coordinate { origin = .init(name: "My location", address: "", coordinate: coordinate, city: ""); clearRoutes() } }
                .onChange(of: transitMode) { _, _ in transit = nil }
                .onChange(of: selectedRoute) { _, _ in camera = .automatic }
        }
    }
    private func miles(_ distance: Double) -> String { (distance / 1609.344).formatted(.number.precision(.fractionLength(1))) + " mi" }
    private func clearRoutes() { walking = nil; driving = nil; transit = nil; nycTaxiTrip = false; error = nil; camera = .automatic }
    private func transportCard(_ title: String, icon: String, route: MKRoute, cost: String, detail: String, mode: String) -> some View {
        Card { VStack(alignment: .leading, spacing: 12) { HStack { Label(title, systemImage: icon).font(.headline); Spacer(); Text(cost).font(.headline).foregroundStyle(Theme.forest) }; Text("\(Int(ceil(route.expectedTravelTime / 60))) min · \(miles(route.distance))").font(.system(size: 24, weight: .medium, design: .serif)); Text(detail).font(.footnote).foregroundStyle(Theme.muted); Button("Directions in Apple Maps") { openApple(mode) }.buttonStyle(OutlineButton()) } }
    }
    private func calculate(_ transport: MKDirectionsTransportType, origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async throws -> MKRoute? {
        let request = MKDirections.Request(); request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin)); request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination)); request.transportType = transport
        let query = ActivityDirectionsQuery(request)
        return try await withTaskCancellationHandler { try await query.calculate() } onCancel: { Task { @MainActor in query.cancel() } }
    }
    private func compare() async {
        guard let origin, let destination else { return }; busy = true; error = nil; routeNotice = nil; defer { busy = false }
        walking = nil; driving = nil; transit = nil; nycTaxiTrip = false
        do { walking = try await calculate(.walking, origin: origin.coordinate, destination: destination) } catch { routeNotice = "A walking route wasn’t returned for this journey." }
        do { driving = try await calculate(.automobile, origin: origin.coordinate, destination: destination) } catch { routeNotice = "Some route options are unavailable. Use the route planners below." }
        if let token = session.token {
            do { transit = try await session.api.send("/activities/\(plan.id)/transit", method: "POST", body: ["origin_latitude": origin.coordinate.latitude, "origin_longitude": origin.coordinate.longitude, "transit_mode": transitMode], token: token) }
            catch { self.error = error.localizedDescription }
        }
        if privateDestination {
            let geocoder = CLGeocoder()
            if let start = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude)).first,
               let end = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: destination.latitude, longitude: destination.longitude)).first {
                let counties: Set<String> = ["New York", "New York County", "Kings", "Kings County", "Queens", "Queens County", "Bronx", "Bronx County", "Richmond", "Richmond County"]
                let airportWords = ["airport", "jfk", "laguardia", "airtrain", "terminal"]
                let names = [start.name, end.name, plan.meeting_name].compactMap { $0 }.joined(separator: " ").lowercased()
                nycTaxiTrip = start.administrativeArea == "NY" && end.administrativeArea == "NY" && counties.contains(start.subAdministrativeArea ?? "") && counties.contains(end.subAdministrativeArea ?? "") && !airportWords.contains { names.contains($0) }
            }
        }
        camera = .automatic
    }
    private func openApple(_ mode: String) {
        guard let destination else { return }; let item = MKMapItem(placemark: MKPlacemark(coordinate: destination)); item.name = destinationName
        var items = [item]; if let origin { let start = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate)); start.name = origin.name; items.insert(start, at: 0) }
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
    private func openPlanner() {
        guard let destination else { return }; var parts = URLComponents(string: "https://www.google.com/maps/dir/")!
        parts.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"), URLQueryItem(name: "travelmode", value: "transit")]
        if let origin { parts.queryItems?.append(.init(name: "origin", value: "\(origin.coordinate.latitude),\(origin.coordinate.longitude)")) }
        if let url = parts.url { openURL(url) }
    }
    private func openUber() {
        guard privateDestination, let destination else { return }
        var parts = URLComponents(string: "https://m.uber.com/looking")!
        var drop: [String: Any] = ["latitude": destination.latitude, "longitude": destination.longitude, "addressLine1": destinationName]
        if let details = plan.meeting_details, !details.isEmpty { drop["addressLine2"] = details }
        guard let data = try? JSONSerialization.data(withJSONObject: drop), let text = String(data: data, encoding: .utf8) else { return }
        parts.queryItems = [URLQueryItem(name: "drop[0]", value: text)]
        if let origin, let start = try? JSONSerialization.data(withJSONObject: ["latitude": origin.coordinate.latitude, "longitude": origin.coordinate.longitude]), let value = String(data: start, encoding: .utf8) { parts.queryItems?.append(.init(name: "pickup", value: value)) }
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "UBER_CLIENT_ID") as? String, !clientID.isEmpty { parts.queryItems?.append(.init(name: "client_id", value: clientID)) }
        if let url = parts.url { openURL(url) }
    }
}
