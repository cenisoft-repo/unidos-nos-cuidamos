export type PublicCollectionCenter = {
  id: string;
  name: string;
  locationLabel: string;
  instructions: string | null;
  accepts: string[];
  restrictedItems: string[];
  coldChainCapable: boolean;
  latitude: number | null;
  longitude: number | null;
};

export type PublicCollectionCenterRow = {
  id: string;
  name: string;
  location_label: string;
  public_instructions?: string | null;
  accepts: string[] | null;
  restricted_items: string[] | null;
  cold_chain_capable: boolean;
  latitude: number | null;
  longitude: number | null;
};

export function toPublicCollectionCenter(row: PublicCollectionCenterRow): PublicCollectionCenter {
  return {
    id: row.id,
    name: row.name,
    locationLabel: row.location_label,
    instructions: row.public_instructions ?? null,
    accepts: row.accepts ?? [],
    restrictedItems: row.restricted_items ?? [],
    coldChainCapable: row.cold_chain_capable,
    latitude: row.latitude === null ? null : Number(row.latitude),
    longitude: row.longitude === null ? null : Number(row.longitude),
  };
}

export type PublicLogisticsPoint = {
  id: string;
  sourceType: "collection_center" | "dispatch";
  publicCode: string;
  label: string;
  status: string;
  originLabel: string | null;
  originLatitude: number | null;
  originLongitude: number | null;
  destinationLabel: string | null;
  destinationLatitude: number | null;
  destinationLongitude: number | null;
  updatedAt: string;
};

export type PublicLogisticsPointRow = {
  id: string;
  source_type: "collection_center" | "dispatch";
  public_code: string;
  label: string;
  status: string;
  origin_label: string | null;
  origin_latitude: number | null;
  origin_longitude: number | null;
  destination_label: string | null;
  destination_latitude: number | null;
  destination_longitude: number | null;
  updated_at: string;
};

export function toPublicLogisticsPoint(row: PublicLogisticsPointRow): PublicLogisticsPoint {
  return {
    id: row.id,
    sourceType: row.source_type,
    publicCode: row.public_code,
    label: row.label,
    status: row.status,
    originLabel: row.origin_label,
    originLatitude: row.origin_latitude === null ? null : Number(row.origin_latitude),
    originLongitude: row.origin_longitude === null ? null : Number(row.origin_longitude),
    destinationLabel: row.destination_label,
    destinationLatitude: row.destination_latitude === null ? null : Number(row.destination_latitude),
    destinationLongitude: row.destination_longitude === null ? null : Number(row.destination_longitude),
    updatedAt: row.updated_at,
  };
}
