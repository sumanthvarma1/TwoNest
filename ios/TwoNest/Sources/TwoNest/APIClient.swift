import Foundation
import Security
struct Member:Codable,Identifiable{let id:String;let first_name:String;let role:String;let profile:MemberProfile}
struct MemberProfile:Codable{let intention:String;let bio:String;let area:String;let interests:[String];let complete:Bool;let onboarding_completed:Bool?}
struct OnboardingProfile:Codable{
 let first_name:String
 let date_of_birth:String?
 let pronouns:String
 let gender_identity:String
 let sexual_orientation:String
 let dating_preferences:[String]
 let intention:String
 let friendship_intention:String
 let area:String
 let search_radius_km:Int
 let preferred_age_min:Int?
 let preferred_age_max:Int?
 let onboarding_step:Int?
 let languages:[String]
 let availability:[String]
 let dietary_requirements:[String]
 let accessibility_needs:[String]
 let event_budget_min:Int
 let event_budget_max:Int
 let discovery_paused:Bool
 let travel_mode_area:String
 let travel_mode_until:String?
 let bio:String
 let interests:[String]
 let visibility:String
 let complete:Bool
}
enum APIJSONValue:Codable{
 case string(String), integer(Int), number(Double), boolean(Bool), array([APIJSONValue]), object([String:APIJSONValue]), null
 init(from decoder:Decoder)throws{
  let value=try decoder.singleValueContainer()
  if value.decodeNil(){self = .null}
  else if let v=try? value.decode(Bool.self){self = .boolean(v)}
  else if let v=try? value.decode(Int.self){self = .integer(v)}
  else if let v=try? value.decode(Double.self){self = .number(v)}
  else if let v=try? value.decode(String.self){self = .string(v)}
  else if let v=try? value.decode([APIJSONValue].self){self = .array(v)}
  else if let v=try? value.decode([String:APIJSONValue].self){self = .object(v)}
  else{throw DecodingError.dataCorruptedError(in:value,debugDescription:"Unsupported JSON value")}
 }
 func encode(to encoder:Encoder)throws{
  var value=encoder.singleValueContainer()
  switch self{case .string(let v):try value.encode(v);case .integer(let v):try value.encode(v);case .number(let v):try value.encode(v);case .boolean(let v):try value.encode(v);case .array(let v):try value.encode(v);case .object(let v):try value.encode(v);case .null:try value.encodeNil()}
 }
 var foundationValue:Any{
  switch self{case .string(let v):return v;case .integer(let v):return v;case .number(let v):return v;case .boolean(let v):return v;case .array(let v):return v.map(\.foundationValue);case .object(let v):return v.mapValues(\.foundationValue);case .null:return NSNull()}
 }
 var stringValue:String?{if case .string(let value)=self{return value};return nil}
 var integerValue:Int?{if case .integer(let value)=self{return value};return nil}
 var arrayValue:[String]?{if case .array(let values)=self{return values.compactMap(\.stringValue)};return nil}
}
struct QuestionnaireQuestion:Codable,Identifiable{let id:String;let category:String;let prompt:String;let response_type:String;let options:[String]?;let minimum:Int?;let maximum:Int?;let maximum_length:Int?}
struct QuestionnaireGroup:Codable,Identifiable{let id:String;let title:String;let questions:[QuestionnaireQuestion]}
struct MemberCompatibilityAnswer:Codable,Identifiable{var id:String{question_id};let question_id:String;let value:APIJSONValue;let importance:Int;let deal_breaker:Bool;let is_private:Bool}
struct QuestionnaireForm:Codable{let groups:[QuestionnaireGroup];let answers:[MemberCompatibilityAnswer]}
struct QuestionnaireSavedResponse:Codable{let saved:Int;let answer_count:Int}
struct IntroductionRefreshResponse:Codable{let created_count:Int;let remaining_this_week:Int}
struct LoginResponse:Codable{let access_token:String;let token_type:String;let user:Member}
struct Introduction:Codable,Identifiable{let id:String;let score:Int;let label:String;let reasons:String;let status:String;let candidate:Member}
struct DecisionResponse:Codable{let decision:String;let mutual:Bool;let conversation_id:String?}
struct MemberBlockResponse:Codable{let blocked:Bool}
struct SafetyReportResponse:Codable{let report_id:String;let status:String;let `private`:Bool;let next_step:String}
struct UnmatchResponse:Codable{let unmatched:Bool}
struct CircleCard:Codable,Identifiable{let id:String;let title:String;let theme:String;let area:String;let starts_at:String;let week:Int;let member_count:Int;let max_members:Int;let joined:Bool;let status:String}
struct CirclePrompt:Codable,Identifiable{let id:String;let week:Int;let title:String;let prompt_type:String;let body:String;let options:[String]?;let poll_counts:[String:Int]?}
struct CircleReflection:Codable{let response_text:String;let selected_options:[String];let has_voice_note:Bool;let voice_asset_key:String?}
struct CircleGroupResponse:Codable,Identifiable{var id:String{first_name+response_text+(voice_asset_key ?? "")};let first_name:String;let response_text:String;let selected_options:[String];let has_voice_note:Bool;let voice_asset_key:String?}
struct CircleChatMessage:Codable,Identifiable{let id:Int;let sender_id:String;let first_name:String;let body:String;let created_at:String}
struct CircleMeetingPlan:Codable,Identifiable{let id:String;let title:String;let venue:String;let area:String;let starts_at:String;let status:String;let yes_count:Int;let no_count:Int;let my_vote:Bool?}
struct CircleDetail:Codable{let id:String;let title:String;let theme:String;let area:String;let starts_at:String;let week:Int;let member_count:Int;let max_members:Int;let joined:Bool;let status:String;let members:[String];let current_prompt:CirclePrompt?;let my_response:CircleReflection?;let group_responses:[CircleGroupResponse];let messages:[CircleChatMessage];let meeting_plans:[CircleMeetingPlan]}
struct CircleResponseResult:Codable{let submitted:Bool;let prompt_id:String;let has_voice_note:Bool;let voice_asset_key:String?}
struct CircleMeetingVoteResult:Codable{let status:String;let yes_count:Int;let no_count:Int;let votes_required:Int}
struct Experience:Codable,Identifiable{let id:String;let title:String;let format:String;let venue:String;let area:String;let starts_at:String;let capacity:Int;let spaces_remaining:Int;let waitlist_count:Int;let on_waitlist:Bool}
struct BookingResponse:Codable{let booking_id:String;let status:String;let check_code:String;let experience:String;let venue_revealed:Bool}
struct WaitlistResponse:Codable{let status:String;let position:Int?;let experience:String?}
struct BookingCancellationResponse:Codable{let cancelled:Bool;let waitlist_member_promoted:Bool}
struct MessageItem:Codable,Identifiable{let id:Int;let sender_id:String;let body:String;let created_at:String}
struct Conversation:Codable,Identifiable{let id:String;let with:String;let member_id:String?;var messages:[MessageItem]}
struct CheckResponse:Codable{let status:String;let checked_in:Bool?;let safety_check_complete:Bool?}
struct FeedbackResponse:Codable{let submitted:Bool;let `private`:Bool;let follow_up:String}
struct CoupleSummary:Codable,Identifiable{let id:String;let status:String;let invited_to_me:Bool;let partner_first_name:String;let your_home_consent:Bool;let partner_home_consent:Bool;let your_home_answer_count:Int;let partner_home_answer_count:Int}
struct CoupleTogetherProfile:Codable{var relationship_stage:String;var general_area:String;var shared_interests:[String];var preferred_activities:[String];var food_preferences:[String];var social_energy:String;var children:String;var pets:[String];var languages:[String];var availability:[String];var event_budget_min:Int;var event_budget_max:Int;var travel_interests:[String]}
struct CoupleTogetherState:Codable{let profile:CoupleTogetherProfile;let has_profile:Bool;let approved_by_you:Bool;let approved_by_partner:Bool;let published:Bool}
struct CoupleMoment:Codable,Identifiable{let id:String;let title:String;let details:String;let moment_type:String;let planned_for:String?;let completed:Bool}
struct CoupleMomentUpdate:Codable{let id:String;let completed:Bool}
struct CoupleAction:Codable{let couple_id:String?;let status:String;let your_consent:Bool?;let active:Bool?}
struct HomeModeResponse:Codable{let your_consent:Bool;let active:Bool}
struct LivingReport:Codable{let disclaimer:String;let status:String;let your_answer_count:Int;let partner_answer_count:Int;let total_questions:Int;let shared_answer_count:Int;let strong_alignment:[String];let acceptable_differences:[String];let discuss_early:[String];let compromises:[String];let conversation_prompts:[String]}
struct HomeModeQuestionnaire:Codable{let groups:[QuestionnaireGroup];let answers:[HomeModeAnswer]}
struct HomeModeAnswer:Codable,Identifiable{var id:String{question_id};let question_id:String;let value:APIJSONValue;let is_private:Bool}
struct HomeModeAnswerSaved:Codable{let saved:Int;let answer_count:Int;let total_questions:Int}
struct PropertyItem:Codable,Identifiable{let id:String;let title:String;let area:String;let rent_pcm:Int;let bedrooms:Int;let verified:Bool}
struct Nest4Candidate:Codable,Identifiable{var id:String{couple_id};let couple_id:String;let first_names:[String]}
struct Nest4Match:Codable,Identifiable{var id:String{match_id};let match_id:String;let status:String;let other_first_names:[String];let your_choice:Bool?;let approval_count:Int;let meeting_plan:Nest4MeetingPlan?;let your_followup:String?;let followup_count:Int}
struct Nest4ProposalResponse:Codable{let match_id:String;let status:String;let consents_required:Int?}
struct Nest4ConsentResult:Codable{let status:String;let your_choice_saved:Bool;let group_chat_open:Bool}
struct Nest4MeetingPlan:Codable,Identifiable{let id:String;let title:String;let venue:String;let area:String;let starts_at:String;let status:String;let attending_count:Int;let declined_count:Int;let my_vote:Bool?}
struct Nest4MeetingCompleteResult:Codable{let status:String;let meeting_status:String;let follow_up_open:Bool}
struct Nest4FollowupResult:Codable{let status:String;let your_decision:String?;let decisions_received:Int;let decisions_required:Int;let group_chat_open:Bool}
struct Nest4GroupMessage:Codable,Identifiable{let id:Int;let sender_id:String;let first_name:String;let body:String;let created_at:String}
struct ShortlistResponse:Codable{let property_id:String;let vote:String;let shared_with_partner:Bool}
struct MovingTaskItem:Codable,Identifiable{let id:String;let title:String;let category:String;let due_date:String?;let completed:Bool}
@MainActor struct APIClient{
 private static var configuredBaseURL: URL {
  let environmentURL = ProcessInfo.processInfo.environment["TWONEST_API_URL"]
  let bundledURL = Bundle.main.object(forInfoDictionaryKey: "TWONEST_API_URL") as? String
  #if DEBUG
  if let environmentURL, let url = URL(string: environmentURL), ["http", "https"].contains(url.scheme ?? "") { UserDefaults.standard.set(environmentURL, forKey: "twonest.preview.apiURL") }
  let savedURL = UserDefaults.standard.string(forKey: "twonest.preview.apiURL")
  #else
  let savedURL: String? = nil
  #endif
  let value = [environmentURL, savedURL, bundledURL].compactMap { $0 }.first { !$0.isEmpty && !$0.contains("$(") } ?? "http://localhost:8000"
  guard let url = URL(string: value), let scheme = url.scheme, scheme == "http" || scheme == "https" else {
   preconditionFailure("TWONEST_API_URL must be a valid http or https URL")
  }
  return url
 }
 let baseURL = APIClient.configuredBaseURL
 func get<T:Decodable>(_ path:String,token:String)async throws->T{try await request(path,method:"GET",body:nil,token:token)}
 func send<T:Decodable>(_ path:String,method:String,body:[String:Any]?=nil,token:String?=nil)async throws->T{try await request(path,method:method,body:body,token:token)}
 func sendAudio<T:Decodable>(_ path:String,data:Data,token:String)async throws->T{var req=URLRequest(url:try endpoint(path));req.httpMethod="POST";req.setValue("audio/mp4",forHTTPHeaderField:"Content-Type");req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization");req.httpBody=data;let(bytes,response)=try await URLSession.shared.data(for:req);guard let response=response as? HTTPURLResponse,(200..<300).contains(response.statusCode)else{throw APIError.failed(String(data:bytes,encoding:.utf8) ?? "Upload failed")};return try JSONDecoder().decode(T.self,from:bytes)}
 func getAudio(_ path:String,token:String)async throws->Data{var req=URLRequest(url:try endpoint(path));req.httpMethod="GET";req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization");let(bytes,response)=try await URLSession.shared.data(for:req);guard let response=response as? HTTPURLResponse,(200..<300).contains(response.statusCode)else{throw APIError.failed(String(data:bytes,encoding:.utf8) ?? "Audio unavailable")};return bytes}
 private func endpoint(_ path: String) throws -> URL {
  let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
  let url = baseURL.appending(path: String(parts[0]))
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.failed("Invalid API address") }
  if parts.count == 2 { components.percentEncodedQuery = String(parts[1]) }
  guard let endpoint = components.url else { throw APIError.failed("Invalid API address") }
  return endpoint
 }
 private func request<T:Decodable>(_ path:String,method:String,body:[String:Any]?,token:String?=nil)async throws->T{var req=URLRequest(url:try endpoint(path));req.httpMethod=method;req.timeoutInterval=15;req.setValue("application/json",forHTTPHeaderField:"Content-Type");if let token{req.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")};if let body{req.httpBody=try JSONSerialization.data(withJSONObject:body)};let(data,response)=try await URLSession.shared.data(for:req);guard let response=response as? HTTPURLResponse,(200..<300).contains(response.statusCode)else{throw APIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data:data,encoding:.utf8) ?? "Request failed")};return try JSONDecoder().decode(T.self,from:data)}
}
enum APIError:Error,LocalizedError {
 case failed(String)
 case http(status: Int, body: String)
 var statusCode: Int? { if case let .http(status, _) = self { return status }; return nil }
 var errorDescription:String? {
  let raw: String
  switch self { case .failed(let value): raw = value; case .http(_, let body): raw = body }
  if let data=raw.data(using:.utf8), let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
   if let detail=object["detail"] as? String{return detail}
   if let details=object["detail"] as? [[String:Any]], let message=details.first?["msg"] as? String{return message}
  }
  return raw
 }
}
enum Keychain{
 static let key="twonest.session"
 static func save(_ value:String){let data=Data(value.utf8);let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrAccount as String:key];SecItemDelete(q as CFDictionary);SecItemAdd(q.merging([kSecValueData as String:data]){$1} as CFDictionary,nil)}
 static func read()->String?{let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne];var result:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil};return String(data:data,encoding:.utf8)}
 static func clear(){let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrAccount as String:key];SecItemDelete(q as CFDictionary)}
}

struct ActivityMember: Codable, Identifiable { let id: String; let first_name: String; let area: String; let bio: String; let interests: [String] }
struct ActivityMessage: Codable, Identifiable { let id: Int; let sender_id: String; let first_name: String; let body: String; let created_at: String }
struct ActivityApplicant: Codable, Identifiable { let id: String; let member: ActivityMember; let note: String; let status: String }
struct ActivityPlan: Codable, Identifiable {
 let id: String; let revision: Int; let host: ActivityMember; let category: String; let title: String; let description: String
 let mode: String; let area: String; let starts_at: String; let expires_at: String; let companion_limit: Int
 let accepted_count: Int; let status: String; let is_host: Bool; let my_join_status: String?; let chat_open: Bool
 let pending_count: Int; let available_members: Int; let meeting_details: String?
 let latitude: Double?; let longitude: Double?; let meeting_latitude: Double?; let meeting_longitude: Double?; let meeting_name: String?
 let participants: [ActivityMember]?; let applicants: [ActivityApplicant]?; var messages: [ActivityMessage]?
 var isEnded: Bool { status == "cancelled" || status == "completed" }
 var statusLabel: String { switch status { case "open": return "Finding company"; case "filled": return "Your people are in"; case "expired": return "Requests closed"; case "cancelled": return "Cancelled"; case "completed": return "Completed"; default: return status.capitalized } }
}
struct ActivityAvailabilityState: Codable { let enabled: Bool; let area: String; let categories: [String]; let mode: String; let expires_at: String?; let show_on_map: Bool?; let latitude: Double?; let longitude: Double? }

struct ActivityMapMember: Codable, Identifiable {
 let id: String; let member: ActivityMember; let latitude: Double; let longitude: Double
 let categories: [String]; let expires_at: String; let approx_distance_km: Double
}
struct ActivityTransitStep: Codable {
 let instruction: String; let mode: String; let line: String; let vehicle: String; let headsign: String
 let departure_stop: String; let arrival_stop: String; let departure_time: String; let arrival_time: String; let stop_count: Int?
}
struct ActivityTransitRoute: Codable, Identifiable {
 let id: String; let duration_seconds: Double; let distance_meters: Double; let fare_amount: Double?; let fare_currency: String?; let fare_text: String?; let steps: [ActivityTransitStep]
 var fareLabel: String { if let fare_text { return fare_text }; if let fare_amount, let fare_currency { return fare_amount.formatted(.currency(code: fare_currency)) }; return "Fare unavailable" }
}
struct ActivityTransitResponse: Codable { let available: Bool; let notice: String; let provider: String; let routes: [ActivityTransitRoute]; let approximate_destination: Bool }
