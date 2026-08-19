"use client";

import "maplibre-gl/dist/maplibre-gl.css";
import "leaflet/dist/leaflet.css";
import { useEffect, useMemo, useRef, useState } from "react";
import type { FeatureCollection, LineString, Point } from "geojson";
import type { GeoJSONSource, Map as MapLibreMap } from "maplibre-gl";
import type { LayerGroup as LeafletLayerGroup, Map as LeafletMap } from "leaflet";
import { Activity, HeartHandshake, LockKeyhole, MapPin, Route, Truck, Warehouse, Wifi, WifiOff } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { numberFormat } from "@/lib/format";
import { labelStatus } from "@/lib/constants";
import { toPublicLogisticsPoint, type PublicCollectionCenter, type PublicLogisticsPoint, type PublicLogisticsPointRow } from "@/lib/public-types";
import { CategoryIcon } from "./category-icon";
import { StatusPill } from "./status-pill";
import styles from "./coverage-explorer.module.css";

export type CoverageNeed = {
  id: string;
  category: string;
  summary: string;
  locationLabel: string;
  status: string;
  projectionId: string;
  neededQuantity: number;
  committedQuantity: number;
  coveredQuantity: number;
  unit: string;
  latitude: number | null;
  longitude: number | null;
  updatedAt: string;
};

type PublicMapRow = {
  id: string;
  category: string;
  summary: string;
  location_label: string;
  status: string;
  needed_quantity: number;
  committed_quantity: number;
  covered_quantity: number;
  unit: string;
  latitude: number;
  longitude: number;
  updated_at: string;
};

type MapProperties = {
  id: string;
  category: string;
  summary: string;
  locationLabel: string;
  status: string;
  progress: number;
};

type LogisticsProperties = {
  id: string;
  sourceType: "collection_center" | "dispatch";
  publicCode: string;
  label: string;
  status: string;
  originLabel: string;
  destinationLabel: string;
};

const REAL_MAP_STYLE = process.env.NEXT_PUBLIC_MAP_STYLE_URL || "https://tiles.openfreemap.org/styles/liberty";
const RASTER_TILE_URL = process.env.NEXT_PUBLIC_RASTER_TILE_URL || "https://tile.openstreetmap.org/{z}/{x}/{y}.png";

function formatBogotaTime(value: string) {
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp)) return "--:--";
  const bogota = new Date(timestamp - 5 * 60 * 60 * 1000);
  return `${String(bogota.getUTCHours()).padStart(2, "0")}:${String(bogota.getUTCMinutes()).padStart(2, "0")}`;
}

function toCoverageNeed(row: PublicMapRow): CoverageNeed {
  return {
    id: row.id,
    category: row.category,
    summary: row.summary,
    locationLabel: row.location_label,
    status: row.status,
    projectionId: row.id,
    neededQuantity: Number(row.needed_quantity),
    committedQuantity: Number(row.committed_quantity),
    coveredQuantity: Number(row.covered_quantity),
    unit: row.unit,
    latitude: row.latitude === null ? null : Number(row.latitude),
    longitude: row.longitude === null ? null : Number(row.longitude),
    updatedAt: row.updated_at,
  };
}

function toGeoJson(needs: CoverageNeed[]): FeatureCollection<Point, MapProperties> {
  return {
    type: "FeatureCollection",
    features: needs
      .filter((need) => need.latitude !== null && need.longitude !== null)
      .map((need) => ({
        type: "Feature",
        geometry: { type: "Point", coordinates: [Number(need.longitude), Number(need.latitude)] },
        properties: {
          id: need.id,
          category: need.category,
          summary: need.summary,
          locationLabel: need.locationLabel,
          status: need.status,
          progress: Math.min(100, Math.round((need.coveredQuantity / need.neededQuantity) * 100)),
        },
      })),
  };
}

function toCentersGeoJson(centers: PublicCollectionCenter[]): FeatureCollection<Point> {
  return {
    type: "FeatureCollection",
    features: centers
      .filter((center) => center.latitude !== null && center.longitude !== null)
      .map((center) => ({
        type: "Feature",
        geometry: { type: "Point", coordinates: [Number(center.longitude), Number(center.latitude)] },
        properties: { id: center.id, name: center.name, locationLabel: center.locationLabel },
      })),
  };
}

function toLiveCentersGeoJson(logistics: PublicLogisticsPoint[], fallbackCenters: PublicCollectionCenter[]): FeatureCollection<Point, LogisticsProperties> {
  const projectedCenters = logistics.filter((point) => point.sourceType === "collection_center" && point.originLatitude !== null && point.originLongitude !== null);
  if (!projectedCenters.length) {
    return {
      type: "FeatureCollection",
      features: toCentersGeoJson(fallbackCenters).features.map((feature) => ({
        ...feature,
        properties: {
          id: String(feature.properties?.id ?? ""),
          sourceType: "collection_center" as const,
          publicCode: "Centro",
          label: String(feature.properties?.name ?? "Centro de acopio"),
          status: "active",
          originLabel: String(feature.properties?.locationLabel ?? "Zona aproximada"),
          destinationLabel: "",
        },
      })),
    };
  }
  return {
    type: "FeatureCollection",
    features: projectedCenters.map((point) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: [Number(point.originLongitude), Number(point.originLatitude)] },
      properties: {
        id: point.id,
        sourceType: point.sourceType,
        publicCode: point.publicCode,
        label: point.label,
        status: point.status,
        originLabel: point.originLabel ?? "Zona aproximada",
        destinationLabel: "",
      },
    })),
  };
}

function toDispatchRoutesGeoJson(logistics: PublicLogisticsPoint[]): FeatureCollection<LineString, LogisticsProperties> {
  return {
    type: "FeatureCollection",
    features: logistics
      .filter((point) => point.sourceType === "dispatch" && point.originLatitude !== null && point.originLongitude !== null && point.destinationLatitude !== null && point.destinationLongitude !== null)
      .map((point) => ({
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: [
            [Number(point.originLongitude), Number(point.originLatitude)],
            [Number(point.destinationLongitude), Number(point.destinationLatitude)],
          ],
        },
        properties: {
          id: point.id,
          sourceType: point.sourceType,
          publicCode: point.publicCode,
          label: point.label,
          status: point.status,
          originLabel: point.originLabel ?? "Origen aproximado",
          destinationLabel: point.destinationLabel ?? "Destino aproximado",
        },
      })),
  };
}

function toDispatchDestinationsGeoJson(logistics: PublicLogisticsPoint[]): FeatureCollection<Point, LogisticsProperties> {
  return {
    type: "FeatureCollection",
    features: logistics
      .filter((point) => point.sourceType === "dispatch" && point.destinationLatitude !== null && point.destinationLongitude !== null)
      .map((point) => ({
        type: "Feature",
        geometry: { type: "Point", coordinates: [Number(point.destinationLongitude), Number(point.destinationLatitude)] },
        properties: {
          id: point.id,
          sourceType: point.sourceType,
          publicCode: point.publicCode,
          label: point.label,
          status: point.status,
          originLabel: point.originLabel ?? "Origen aproximado",
          destinationLabel: point.destinationLabel ?? "Destino aproximado",
        },
      })),
  };
}

function fitMap(map: MapLibreMap, needs: CoverageNeed[], centers: PublicCollectionCenter[], logistics: PublicLogisticsPoint[] = []) {
  const coordinates = [
    ...needs.filter((item) => item.latitude !== null && item.longitude !== null),
    ...centers.filter((item) => item.latitude !== null && item.longitude !== null),
    ...logistics.filter((item) => item.originLatitude !== null && item.originLongitude !== null).map((item) => ({ latitude: item.originLatitude, longitude: item.originLongitude })),
    ...logistics.filter((item) => item.destinationLatitude !== null && item.destinationLongitude !== null).map((item) => ({ latitude: item.destinationLatitude, longitude: item.destinationLongitude })),
  ];
  if (!coordinates.length) return;
  const longitudes = coordinates.map((item) => Number(item.longitude));
  const latitudes = coordinates.map((item) => Number(item.latitude));
  const bounds: [[number, number], [number, number]] = [
    [Math.min(...longitudes) - 0.28, Math.min(...latitudes) - 0.28],
    [Math.max(...longitudes) + 0.28, Math.max(...latitudes) + 0.28],
  ];
  map.fitBounds(bounds, {
    padding: { top: 54, right: 54, bottom: 54, left: 54 },
    maxZoom: coordinates.length === 1 ? 8 : 7.2,
    duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 650,
  });
}

export function CoverageExplorer({ needs, centers, logistics, eventId }: { needs: CoverageNeed[]; centers: PublicCollectionCenter[]; logistics: PublicLogisticsPoint[]; eventId: string }) {
  const [liveNeeds, setLiveNeeds] = useState(needs);
  const [liveLogistics, setLiveLogistics] = useState(logistics);
  const [category, setCategory] = useState("Todas");
  const [selectedId, setSelectedId] = useState(needs[0]?.id ?? "");
  const [selectedLogisticsId, setSelectedLogisticsId] = useState("");
  const [mapState, setMapState] = useState<"loading" | "ready" | "fallback">("loading");
  const [fallbackMapReady, setFallbackMapReady] = useState(false);
  const [syncState, setSyncState] = useState<"connecting" | "live" | "degraded">("connecting");
  const mapContainerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<MapLibreMap | null>(null);
  const fallbackMapContainerRef = useRef<HTMLDivElement | null>(null);
  const fallbackMapRef = useRef<LeafletMap | null>(null);
  const fallbackLayersRef = useRef<LeafletLayerGroup | null>(null);
  const leafletRef = useRef<typeof import("leaflet") | null>(null);
  const initialNeedsRef = useRef(needs);
  const initialCentersRef = useRef(centers);
  const initialLogisticsRef = useRef(logistics);
  const initialSelectedIdRef = useRef(needs[0]?.id ?? "");
  const categories = useMemo(() => ["Todas", ...Array.from(new Set(liveNeeds.map((need) => need.category)))], [liveNeeds]);
  const filteredNeeds = category === "Todas" ? liveNeeds : liveNeeds.filter((need) => need.category === category);
  const selected = filteredNeeds.find((need) => need.id === selectedId) ?? filteredNeeds[0];
  const geoJson = useMemo(() => toGeoJson(filteredNeeds), [filteredNeeds]);
  const centerGeoJson = useMemo(() => toLiveCentersGeoJson(liveLogistics, centers), [centers, liveLogistics]);
  const dispatchRoutesGeoJson = useMemo(() => toDispatchRoutesGeoJson(liveLogistics), [liveLogistics]);
  const dispatchDestinationsGeoJson = useMemo(() => toDispatchDestinationsGeoJson(liveLogistics), [liveLogistics]);
  const activeLogistics = liveLogistics.find((point) => point.id === selectedLogisticsId);
  const dispatches = useMemo(() => liveLogistics.filter((point) => point.sourceType === "dispatch"), [liveLogistics]);
  const collectionPoints = useMemo(() => liveLogistics.filter((point) => point.sourceType === "collection_center"), [liveLogistics]);

  useEffect(() => {
    let cancelled = false;
    let loadingTimeout: number | undefined;
    const container = mapContainerRef.current;
    if (!container || mapRef.current) return;

    /** Sin WebGL el estilo vectorial nunca carga: pasamos al mapa alternativo sin esperar. */
    function supportsWebGl() {
      try {
        const probe = document.createElement("canvas");
        return Boolean(probe.getContext("webgl2") ?? probe.getContext("webgl"));
      } catch {
        return false;
      }
    }

    async function initializeMap() {
      if (!supportsWebGl()) {
        setMapState("fallback");
        return;
      }
      try {
        const maplibregl = await import("maplibre-gl");
        if (cancelled || !container) return;
        const map = new maplibregl.Map({
          container,
          style: REAL_MAP_STYLE,
          center: [-73.6, 4.4],
          zoom: 4.2,
          minZoom: 3.4,
          maxZoom: 12,
          attributionControl: false,
        });
        mapRef.current = map;
        const activateFallback = () => {
          if (cancelled || mapRef.current !== map) return;
          if (loadingTimeout) window.clearTimeout(loadingTimeout);
          map.remove();
          mapRef.current = null;
          setMapState("fallback");
        };
        loadingTimeout = window.setTimeout(() => {
          if (!map.loaded()) activateFallback();
        }, 4500);
        map.addControl(new maplibregl.NavigationControl({ showCompass: false, visualizePitch: false }), "top-right");
        map.addControl(new maplibregl.AttributionControl({ compact: true, customAttribution: "OpenFreeMap · © OpenStreetMap" }), "bottom-right");

        map.on("load", () => {
          if (cancelled) return;
          if (loadingTimeout) window.clearTimeout(loadingTimeout);
          map.addSource("public-needs", {
            type: "geojson",
            data: toGeoJson(initialNeedsRef.current),
            cluster: true,
            clusterMaxZoom: 8,
            clusterRadius: 48,
          });
          map.addSource("public-centers", {
            type: "geojson",
            data: toLiveCentersGeoJson(initialLogisticsRef.current, initialCentersRef.current),
          });
          map.addSource("public-dispatch-routes", {
            type: "geojson",
            data: toDispatchRoutesGeoJson(initialLogisticsRef.current),
          });
          map.addSource("public-dispatch-destinations", {
            type: "geojson",
            data: toDispatchDestinationsGeoJson(initialLogisticsRef.current),
          });
          map.addLayer({
            id: "public-dispatch-routes",
            type: "line",
            source: "public-dispatch-routes",
            paint: {
              "line-color": "#b05734",
              "line-width": ["interpolate", ["linear"], ["zoom"], 3, 2.5, 9, 5],
              "line-dasharray": [2, 1.4],
              "line-opacity": 0.88,
            },
          });
          map.addLayer({
            id: "coverage-heat",
            type: "heatmap",
            source: "public-needs",
            maxzoom: 8,
            paint: {
              "heatmap-weight": ["interpolate", ["linear"], ["get", "progress"], 0, 0.35, 100, 1],
              "heatmap-intensity": ["interpolate", ["linear"], ["zoom"], 3, 0.8, 8, 1.45],
              "heatmap-color": ["interpolate", ["linear"], ["heatmap-density"], 0, "rgba(246,189,71,0)", 0.35, "rgba(246,189,71,.42)", 0.7, "rgba(74,137,112,.55)", 1, "rgba(21,61,55,.7)"],
              "heatmap-radius": ["interpolate", ["linear"], ["zoom"], 3, 18, 8, 36],
              "heatmap-opacity": ["interpolate", ["linear"], ["zoom"], 6, 0.72, 9, 0],
            },
          });
          map.addLayer({
            id: "clusters",
            type: "circle",
            source: "public-needs",
            filter: ["has", "point_count"],
            paint: {
              "circle-color": "#153d37",
              "circle-radius": ["step", ["get", "point_count"], 18, 10, 24, 40, 30],
              "circle-stroke-color": "#fffefb",
              "circle-stroke-width": 4,
            },
          });
          map.addLayer({
            id: "unclustered-needs",
            type: "circle",
            source: "public-needs",
            filter: ["!", ["has", "point_count"]],
            paint: {
              "circle-color": ["match", ["get", "category"], "Agua", "#2f7f9c", "Higiene", "#956d21", "Alimentos", "#a75d43", "Salud", "#a7443d", "#285d53"],
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 3, 8, 8, 13],
              "circle-stroke-color": "#fffefb",
              "circle-stroke-width": 4,
            },
          });
          map.addLayer({
            id: "selected-need",
            type: "circle",
            source: "public-needs",
            filter: ["==", ["get", "id"], initialSelectedIdRef.current],
            paint: {
              "circle-color": "rgba(0,0,0,0)",
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 3, 15, 8, 21],
              "circle-stroke-color": "#f6bd47",
              "circle-stroke-width": 5,
              "circle-opacity": 0,
            },
          });
          map.addLayer({
            id: "public-centers",
            type: "circle",
            source: "public-centers",
            paint: {
              "circle-color": "#236fa1",
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 3, 7, 8, 11],
              "circle-stroke-color": "#fffefb",
              "circle-stroke-width": 3,
            },
          });
          map.addLayer({
            id: "public-dispatch-destinations",
            type: "circle",
            source: "public-dispatch-destinations",
            paint: {
              "circle-color": "#b05734",
              "circle-radius": ["interpolate", ["linear"], ["zoom"], 3, 7, 8, 12],
              "circle-stroke-color": "#fffefb",
              "circle-stroke-width": 3,
            },
          });

          map.on("click", "unclustered-needs", (event) => {
            const id = event.features?.[0]?.properties?.id;
            if (typeof id === "string") setSelectedId(id);
          });
          map.on("click", "clusters", async (event) => {
            const clusterId = Number(event.features?.[0]?.properties?.cluster_id);
            if (!Number.isFinite(clusterId)) return;
            const source = map.getSource("public-needs") as GeoJSONSource;
            const zoom = await source.getClusterExpansionZoom(clusterId);
            const coordinates = (event.features?.[0]?.geometry as Point | undefined)?.coordinates;
            if (coordinates) map.easeTo({ center: [coordinates[0], coordinates[1]], zoom });
          });
          for (const layer of ["public-centers", "public-dispatch-destinations"]) {
            map.on("click", layer, (event) => {
              const id = event.features?.[0]?.properties?.id;
              if (typeof id === "string") setSelectedLogisticsId(id);
            });
          }
          for (const layer of ["clusters", "unclustered-needs", "public-centers", "public-dispatch-destinations"]) {
            map.on("mouseenter", layer, () => { map.getCanvas().style.cursor = "pointer"; });
            map.on("mouseleave", layer, () => { map.getCanvas().style.cursor = ""; });
          }

          fitMap(map, initialNeedsRef.current, initialCentersRef.current, initialLogisticsRef.current);
          setMapState("ready");
        });
        map.on("error", () => {
          if (!map.loaded()) activateFallback();
        });
      } catch {
        if (!cancelled) setMapState("fallback");
      }
    }

    void initializeMap();
    return () => {
      cancelled = true;
      if (loadingTimeout) window.clearTimeout(loadingTimeout);
      mapRef.current?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    if (mapState !== "fallback" || !fallbackMapContainerRef.current || fallbackMapRef.current) return;
    let cancelled = false;

    async function initializeFallbackMap() {
      const L = await import("leaflet");
      if (cancelled || !fallbackMapContainerRef.current) return;
      leafletRef.current = L;
      const map = L.map(fallbackMapContainerRef.current, {
        center: [4.7, -74.1],
        zoom: 5,
        zoomControl: true,
        attributionControl: true,
        preferCanvas: true,
      });
      L.tileLayer(RASTER_TILE_URL, {
        maxZoom: 19,
        crossOrigin: true,
        attribution: "© OpenStreetMap contributors",
      }).addTo(map);
      fallbackMapRef.current = map;
      fallbackLayersRef.current = L.layerGroup().addTo(map);
      setFallbackMapReady(true);
      window.setTimeout(() => map.invalidateSize(), 0);
    }

    void initializeFallbackMap();
    return () => {
      cancelled = true;
      fallbackMapRef.current?.remove();
      fallbackMapRef.current = null;
      fallbackLayersRef.current = null;
      leafletRef.current = null;
      setFallbackMapReady(false);
    };
  }, [mapState]);

  useEffect(() => {
    const L = leafletRef.current;
    const map = fallbackMapRef.current;
    const layers = fallbackLayersRef.current;
    if (!fallbackMapReady || !L || !map || !layers) return;
    layers.clearLayers();
    const bounds = L.latLngBounds([]);

    filteredNeeds.filter((need) => need.latitude !== null && need.longitude !== null).forEach((need) => {
      const position: [number, number] = [Number(need.latitude), Number(need.longitude)];
      bounds.extend(position);
      L.circleMarker(position, {
        radius: selected?.id === need.id ? 11 : 8,
        color: selected?.id === need.id ? "#f6bd47" : "#fffefb",
        weight: selected?.id === need.id ? 5 : 3,
        fillColor: need.category === "Agua" ? "#2f7f9c" : need.category === "Higiene" ? "#956d21" : "#285d53",
        fillOpacity: 1,
      }).bindTooltip(`${need.summary} · ${need.locationLabel}`).on("click", () => setSelectedId(need.id)).addTo(layers);
    });

    if (collectionPoints.length) {
      collectionPoints.filter((point) => point.originLatitude !== null && point.originLongitude !== null).forEach((point) => {
        const position: [number, number] = [Number(point.originLatitude), Number(point.originLongitude)];
        bounds.extend(position);
        L.circleMarker(position, { radius: 8, color: "#fffefb", weight: 3, fillColor: "#236fa1", fillOpacity: 1 })
          .bindTooltip(`${point.label} · ${point.originLabel}`)
          .on("click", () => focusLogistics(point))
          .addTo(layers);
      });
    } else {
      centers.filter((center) => center.latitude !== null && center.longitude !== null).forEach((center) => {
        const position: [number, number] = [Number(center.latitude), Number(center.longitude)];
        bounds.extend(position);
        L.circleMarker(position, { radius: 8, color: "#fffefb", weight: 3, fillColor: "#236fa1", fillOpacity: 1 }).bindTooltip(`${center.name} · ${center.locationLabel}`).addTo(layers);
      });
    }

    dispatches.filter((point) => point.originLatitude !== null && point.originLongitude !== null && point.destinationLatitude !== null && point.destinationLongitude !== null).forEach((point) => {
      const origin: [number, number] = [Number(point.originLatitude), Number(point.originLongitude)];
      const destination: [number, number] = [Number(point.destinationLatitude), Number(point.destinationLongitude)];
      bounds.extend(origin);
      bounds.extend(destination);
      L.polyline([origin, destination], { color: "#b05734", weight: 4, dashArray: "8 6", opacity: .88 }).bindTooltip(`${point.publicCode}: ${point.originLabel} → ${point.destinationLabel}`).on("click", () => focusLogistics(point)).addTo(layers);
      L.circleMarker(destination, { radius: 8, color: "#fffefb", weight: 3, fillColor: "#b05734", fillOpacity: 1 }).bindTooltip(`${point.publicCode} · ${labelStatus(point.status)}`).on("click", () => focusLogistics(point)).addTo(layers);
    });

    if (bounds.isValid()) map.fitBounds(bounds.pad(.16), { padding: [36, 36], maxZoom: 9, animate: false });
  }, [centers, collectionPoints, dispatches, fallbackMapReady, filteredNeeds, selected?.id]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || mapState !== "ready") return;
    const source = map.getSource("public-needs") as GeoJSONSource | undefined;
    source?.setData(geoJson);
    (map.getSource("public-centers") as GeoJSONSource | undefined)?.setData(centerGeoJson);
    (map.getSource("public-dispatch-routes") as GeoJSONSource | undefined)?.setData(dispatchRoutesGeoJson);
    (map.getSource("public-dispatch-destinations") as GeoJSONSource | undefined)?.setData(dispatchDestinationsGeoJson);
    if (map.getLayer("selected-need")) map.setFilter("selected-need", ["==", ["get", "id"], selected?.id ?? ""]);
    fitMap(map, filteredNeeds, centers, liveLogistics);
  }, [centerGeoJson, centers, dispatchDestinationsGeoJson, dispatchRoutesGeoJson, filteredNeeds, geoJson, liveLogistics, mapState, selected?.id]);

  useEffect(() => {
    const supabase = createClient();

    async function refreshMap() {
      const { data, error } = await supabase.rpc("public_need_map", { p_event_id: eventId });
      if (error) {
        setSyncState("degraded");
        return;
      }
      const refreshed = ((data ?? []) as PublicMapRow[]).map(toCoverageNeed);
      setLiveNeeds(refreshed);
      setSelectedId((current) => refreshed.some((need) => need.id === current) ? current : (refreshed[0]?.id ?? ""));
    }

    async function refreshLogistics() {
      const { data, error } = await supabase.rpc("public_logistics_map", { p_event_id: eventId });
      if (error) {
        setSyncState("degraded");
        return;
      }
      const refreshed = ((data ?? []) as PublicLogisticsPointRow[]).map(toPublicLogisticsPoint);
      setLiveLogistics(refreshed);
      setSelectedLogisticsId((current) => refreshed.some((point) => point.id === current) ? current : "");
    }

    const channel = supabase
      .channel(`public-territorial-map:${eventId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "public_need_projections", filter: `event_id=eq.${eventId}` }, () => { void refreshMap(); })
      .on("postgres_changes", { event: "*", schema: "public", table: "public_logistics_projections", filter: `event_id=eq.${eventId}` }, () => { void refreshLogistics(); })
      .subscribe((status) => {
        if (status === "SUBSCRIBED") setSyncState("live");
        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") setSyncState("degraded");
      });

    return () => { void supabase.removeChannel(channel); };
  }, [eventId]);

  function chooseCategory(nextCategory: string) {
    setCategory(nextCategory);
    const nextNeeds = nextCategory === "Todas" ? liveNeeds : liveNeeds.filter((need) => need.category === nextCategory);
    setSelectedId(nextNeeds[0]?.id ?? "");
  }

  function focusLogistics(point: PublicLogisticsPoint) {
    setSelectedLogisticsId(point.id);
    const longitude = point.destinationLongitude ?? point.originLongitude;
    const latitude = point.destinationLatitude ?? point.originLatitude;
    const map = mapRef.current;
    if (longitude !== null && latitude !== null && map) {
      map.easeTo({
        center: [longitude, latitude],
        zoom: Math.max(map.getZoom(), 8),
        duration: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 500,
      });
    }
  }

  const progress = selected ? Math.min(100, Math.round((selected.coveredQuantity / selected.neededQuantity) * 100)) : 0;
  const syncLabel = syncState === "live" ? "Actualización en vivo" : syncState === "degraded" ? "Reconectando" : "Conectando";

  return (
    <div className={styles.explorer} id="mapa">
      <header className={styles.header}>
        <div>
          <p className={styles.kicker}><MapPin size={13} /> Centro territorial</p>
          <h2 className={styles.title}>¿Dónde hace falta ayuda?</h2>
        </div>
        <div className={styles.headerBadges}>
          <span className={`${styles.sync} ${syncState === "live" ? styles.syncLive : syncState === "degraded" ? styles.syncDegraded : ""}`}>{syncState === "degraded" ? <WifiOff size={12} /> : <Wifi size={12} />} {syncLabel}</span>
          <span className={styles.privacy}><LockKeyhole size={12} /> Precisión protegida</span>
        </div>
      </header>

      <div className={styles.filters} aria-label="Filtrar mapa por categoría">
        {categories.map((item) => (
          <button className={styles.filter} type="button" aria-pressed={category === item} onClick={() => chooseCategory(item)} key={item}>
            {item}
          </button>
        ))}
      </div>

      <div className={styles.canvas} aria-label={`Mapa cartográfico real con ${filteredNeeds.length} necesidades, ${collectionPoints.length} centros y ${dispatches.length} despachos aproximados`}>
        <div className={styles.mapCanvas} ref={mapContainerRef} />
        {mapState === "loading" && <div className={styles.mapFeedback}><Activity size={18} /> Preparando cartografía real…</div>}
        {mapState === "fallback" && (
          <div className={`${styles.mapFeedback} ${styles.visualFallback}`}>
            <div className={styles.fallbackMapCanvas} ref={fallbackMapContainerRef} />
            <div className={styles.fallbackNote}><MapPin size={16} /><span><strong>Mapa alternativo</strong>Estás viendo una versión simplificada del mapa. Los puntos y la actualización en vivo siguen activos.</span></div>
          </div>
        )}
        <div className={styles.mapMeta} aria-hidden="true">
          <span>● Necesidad</span>
          <span className={styles.centerLegend}>● Centro de acopio</span>
          <span className={styles.dispatchLegend}>━ Despacho aproximado</span>
          <span>{filteredNeeds.length} {filteredNeeds.length === 1 ? "caso" : "casos"}</span>
        </div>
      </div>

      {selected ? (
        <article className={styles.detail} aria-live="polite">
          <div>
            <div className={styles.detailTop}><StatusPill status="verified">{selected.status}</StatusPill> <span className={styles.kicker} style={{ margin: 0 }}><CategoryIcon category={selected.category} /> {selected.category}</span></div>
            <h3>{selected.summary}</h3>
            <p className={styles.location}><MapPin size={13} /> {selected.locationLabel}</p>
          </div>
          <div className={styles.coverage}>
            <div className={styles.coverageHead}><strong>{progress}%</strong><span>cubierto</span></div>
            <div className={styles.progress} aria-label={`${progress}% cubierto`}><span style={{ width: `${progress}%` }} /></div>
            <span>{numberFormat.format(selected.coveredQuantity)} de {numberFormat.format(selected.neededQuantity)} {selected.unit}</span>
            <span>Comprometido {numberFormat.format(selected.committedQuantity)} · pendiente {numberFormat.format(Math.max(selected.neededQuantity - selected.committedQuantity, 0))} {selected.unit}</span>
            <a className={styles.helpAction} href={`/donar?necesidad=${selected.projectionId}`}><HeartHandshake size={15} /> Ayudar con esta necesidad</a>
          </div>
        </article>
      ) : <div className={styles.empty}>No hay necesidades públicas vigentes para este filtro.</div>}

      <section className={styles.logisticsPanel} aria-labelledby="live-logistics-title">
        <header className={styles.logisticsHeader}>
          <div><p className={styles.kicker}><Route size={13} /> Operación territorial</p><h3 id="live-logistics-title">Acopio y despachos en tiempo real</h3></div>
          <span><Wifi size={12} /> En vivo</span>
        </header>
        <div className={styles.logisticsGrid}>
          {collectionPoints.map((point) => (
            <button className={selectedLogisticsId === point.id ? styles.logisticsSelected : ""} type="button" onClick={() => focusLogistics(point)} aria-pressed={selectedLogisticsId === point.id} key={point.id}>
              <span className={styles.logisticsIcon}><Warehouse size={18} /></span>
              <span><small>Centro de acopio · {point.publicCode}</small><strong>{point.label}</strong><em><MapPin size={11} /> {point.originLabel}</em></span>
              <StatusPill status={point.status}>{point.status === "active" ? "Activo" : labelStatus(point.status)}</StatusPill>
            </button>
          ))}
          {dispatches.map((point) => (
            <button className={selectedLogisticsId === point.id ? styles.logisticsSelected : ""} type="button" onClick={() => focusLogistics(point)} aria-pressed={selectedLogisticsId === point.id} key={point.id}>
              <span className={`${styles.logisticsIcon} ${styles.dispatchIcon}`}><Truck size={18} /></span>
              <span><small>Despacho · {point.publicCode}</small><strong>{point.originLabel} → {point.destinationLabel}</strong><em>Actualizado {formatBogotaTime(point.updatedAt)}</em></span>
              <StatusPill status={point.status}>{labelStatus(point.status)}</StatusPill>
            </button>
          ))}
          {!dispatches.length && <div className={styles.logisticsEmpty}><Truck size={18} /><span><strong>Sin despachos públicos en curso</strong>Cuando bodega cree un despacho hacia una necesidad publicada, la ruta aproximada aparecerá aquí automáticamente.</span></div>}
        </div>
        {activeLogistics?.sourceType === "dispatch" && <p className={styles.logisticsSelection}><strong>{activeLogistics.publicCode}</strong> conecta {activeLogistics.originLabel} con {activeLogistics.destinationLabel}. Estado: {labelStatus(activeLogistics.status)}.</p>}
        <p className={styles.telemetryNote}><LockKeyhole size={13} /> La actualización en vivo refleja movimientos de la operación. No es el GPS de un vehículo ni muestra rutas, direcciones o personas exactas.</p>
      </section>
    </div>
  );
}
