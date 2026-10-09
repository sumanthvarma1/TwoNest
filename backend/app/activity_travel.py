"""Provider-backed transit itineraries. Missing fares remain missing."""
import os
import httpx
from fastapi import BackgroundTasks, Depends, HTTPException
from .activities import router, eligible_member, get_request, card
from .db import get_db
from .models import User
from .schemas import TravelInput
from sqlalchemy.orm import Session

@router.post("/{request_id}/transit")
async def transit_routes(request_id: str, payload: TravelInput, user: User = Depends(eligible_member), db: Session = Depends(get_db)):
    request = get_request(db, request_id, user.id)
    view = card(db, request, user.id)
    private = view["is_host"] or view["my_join_status"] == "accepted"
    latitude = request.meeting_latitude if private else request.latitude
    longitude = request.meeting_longitude if private else request.longitude
    if request.mode != "in_person" or latitude is None: raise HTTPException(422, "This plan has no map destination")
    if payload.transit_mode not in {"all", "bus"}: raise HTTPException(422, "Choose bus or all transit")
    key = os.getenv("GOOGLE_ROUTES_API_KEY", "")
    if not key:
        return {"available": False, "notice": "In-app bus and train itineraries need the transit provider connection. Open a route planner below for current routes and fares.", "provider": "Google Maps", "routes": [], "approximate_destination": not private}
    body = {"origin": {"location": {"latLng": {"latitude": payload.origin_latitude, "longitude": payload.origin_longitude}}},
        "destination": {"location": {"latLng": {"latitude": latitude, "longitude": longitude}}},
        "travelMode": "TRANSIT", "computeAlternativeRoutes": True, "languageCode": "en-US"}
    if payload.transit_mode == "bus": body["transitPreferences"] = {"allowedTravelModes": ["BUS"]}
    mask = "routes.duration,routes.distanceMeters,routes.legs.steps.navigationInstruction,routes.legs.steps.transitDetails,routes.legs.steps.travelMode,routes.travelAdvisory.transitFare,routes.localizedValues.transitFare"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            result = await client.post("https://routes.googleapis.com/directions/v2:computeRoutes", headers={"X-Goog-Api-Key": key, "X-Goog-FieldMask": mask}, json=body)
        if result.status_code != 200: raise HTTPException(502, "The transit provider could not return routes. Use the route planner below.")
        raw = result.json()
    except (httpx.HTTPError, ValueError): raise HTTPException(502, "Transit routes are temporarily unavailable. Use the route planner below.")
    routes = []
    for index, route in enumerate(raw.get("routes", [])[:4]):
        steps = []
        for leg in route.get("legs", []):
            for step in leg.get("steps", []):
                details = step.get("transitDetails", {}); stops = details.get("stopDetails", {}); line = details.get("transitLine", {})
                steps.append({"instruction": step.get("navigationInstruction", {}).get("instructions", ""),
                    "mode": step.get("travelMode", ""), "line": line.get("nameShort") or line.get("name", ""),
                    "vehicle": line.get("vehicle", {}).get("type", ""), "headsign": details.get("headsign", ""),
                    "departure_stop": stops.get("departureStop", {}).get("name", ""), "arrival_stop": stops.get("arrivalStop", {}).get("name", ""),
                    "departure_time": stops.get("departureTime", ""), "arrival_time": stops.get("arrivalTime", ""),
                    "stop_count": details.get("stopCount")})
        fare = route.get("travelAdvisory", {}).get("transitFare")
        amount = None
        if fare is not None: amount = float(fare.get("units", 0)) + float(fare.get("nanos", 0))/1_000_000_000
        try: duration = float(route.get("duration", "0s").removesuffix("s"))
        except ValueError: duration = 0
        routes.append({"id": str(index), "duration_seconds": duration, "distance_meters": route.get("distanceMeters", 0), "fare_amount": amount, "fare_currency": fare.get("currencyCode") if fare else None, "fare_text": route.get("localizedValues", {}).get("transitFare", {}).get("text"), "steps": steps})
    return {"available": bool(routes), "notice": "Fare estimates are shown only when the provider prices the complete itinerary. Check agency service alerts before travelling." if routes else "No transit itinerary found. Try the route planners below.", "provider": "Google Maps", "routes": routes, "approximate_destination": not private}
