-- G-066 · Un codigo que la plataforma publica, la plataforma tiene que reconocerlo.
--
-- Comprobado contra produccion antes de tocar nada:
--
--   DON-FDC2048F1AD1F0AF61EEA727-2423fe3b  ->  []            (el que se publica)
--   DON-FDC2048F1AD1F0AF61EEA727           ->  el recorrido  (el que nadie ve)
--
-- Seis de los once codigos publicados en produccion eran irresolubles. Publicar un
-- identificador y despues no reconocerlo es la misma clase de defecto que G-063: una promesa
-- publica incumplida, de las que ensenan a desconfiar de todo lo demas que se publica.

CREATE OR REPLACE FUNCTION public.track_public_journey(p_tracking_code text)
 RETURNS TABLE(step integer, stage_key text, stage_label text, detail text, occurred_at timestamp with time zone, related_code text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  need public.need_cases;
  intake public.donation_intakes;
  donation public.donations;
  codigo text;
begin
  -- G-066 · La plataforma publicaba un identificador y despues no lo reconocia.
  --
  -- `validate_delivery` publica el codigo de un aporte en especie como
  -- `donor_tracking_code || '-' || left(donation_item.id, 8)`, para que cada articulo tenga
  -- su fila en la proyeccion publica (G-012). Son 37 caracteres. Esta guarda solo admitia los
  -- 28 de la forma base, asi que el codigo que `/transparencia` y el Excel publican devolvia
  -- vacio al pegarlo en `/seguimiento`.
  --
  -- Se normaliza en la base y no solo en el navegador porque el codigo publicado tiene que
  -- funcionar entre por donde entre: el formulario, un QR, un enlace o la propia API.
  codigo := upper(btrim(coalesce(p_tracking_code, '')));
  if codigo ~ '^(NEC|APO|DON)-[A-F0-9]{24}-[A-F0-9]{8}$' then
    -- El sufijo identifica el articulo; el recorrido es el del aporte que lo contiene.
    codigo := left(codigo, 28);
  end if;
  -- La guarda de formato no se relaja: admite exactamente lo que la plataforma emite y nada
  -- mas, que es para lo que estaba puesta.
  if codigo !~ '^(NEC|APO|DON)-[A-F0-9]{24}$' then return; end if;

  select * into need from public.need_cases as candidate where candidate.tracking_code = codigo;
  select * into intake from public.donation_intakes as candidate where candidate.tracking_code = codigo;
  select * into donation from public.donations as candidate where candidate.donor_tracking_code = codigo;

  -- Los dos códigos del mismo aporte son la misma historia vista desde dos lados.
  if donation.id is not null and intake.id is null and donation.intake_id is not null then
    select * into intake from public.donation_intakes as candidate where candidate.id = donation.intake_id;
  end if;
  if intake.id is not null and donation.id is null then
    select * into donation from public.donations as candidate where candidate.intake_id = intake.id;
  end if;

  return query
  select entry.step, entry.stage_key, entry.stage_label, entry.detail, entry.occurred_at, entry.related_code
  from (
    -- Necesidad ciudadana
    select 10 as step, 'need_reported' as stage_key, 'Reporte recibido' as stage_label,
      'El caso quedó protegido y entró a la cola de verificación.' as detail,
      need.created_at as occurred_at, need.tracking_code as related_code
    where need.id is not null

    union all
    select 20, 'need_verified', 'Necesidad verificada',
      'Una organización autorizada contrastó los hechos.',
      verification.created_at, need.tracking_code
    from public.need_verifications as verification
    where need.id is not null and verification.need_case_id = need.id and verification.decision = 'verify'

    union all
    select 30, 'need_published', 'Necesidad publicada',
      'El caso quedó visible sin dirección exacta ni contacto.',
      verification.created_at, need.tracking_code
    from public.need_verifications as verification
    where need.id is not null and verification.need_case_id = need.id and verification.decision = 'publish'

    -- Aporte declarado
    union all
    select 40, 'intake_reported', 'Aporte reportado',
      case when intake.kind = 'money'
        then 'Se registró un aporte económico gestionado fuera de la plataforma.'
        else 'Se registró una promesa de bienes. Todavía no acredita recepción.' end,
      intake.submitted_at, intake.tracking_code
    where intake.id is not null

    union all
    select 50, 'intake_approved', 'Aporte aprobado',
      'La revisión autorizó continuar con la coordinación.',
      decision.decided_at, intake.tracking_code
    from public.intake_verification_decisions as decision
    where intake.id is not null and decision.intake_id = intake.id and decision.decision = 'approve'

    -- Recorrido operacional. Aquí es donde el APO deja de quedarse congelado.
    union all
    select 60, 'donation_opened', 'Coordinación abierta',
      'El aporte pasó a tener seguimiento operacional propio.',
      donation.created_at, donation.donor_tracking_code
    where donation.id is not null

    union all
    select 70, 'stock_received', 'Recepción confirmada',
      -- `FM` quita los ceros decimales pero deja el punto: 40.000 quedaría como «40.».
      'El centro confirmó ' || rtrim(trim(to_char(lot.quantity_initial, 'FM999999990.999')), '.') || ' ' || lot.unit || ' en custodia.',
      lot.received_at, donation.donor_tracking_code
    from public.inventory_lots as lot
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id

    union all
    select 80, 'stock_allocated', 'Reservado para una necesidad',
      'La existencia quedó comprometida con un caso verificado.',
      allocation.created_at, donation.donor_tracking_code
    from public.allocations as allocation
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id

    union all
    select 90, 'shipment_dispatched', 'Despachado',
      'Salida hacia ' || shipment.public_destination || '.',
      shipment.dispatched_at, shipment.shipment_code
    from public.shipments as shipment
    join public.shipment_items as shipped on shipped.shipment_id = shipment.id
    join public.allocations as allocation on allocation.id = shipped.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id and shipment.dispatched_at is not null

    union all
    select 100, 'delivery_registered', 'Entrega registrada',
      case when delivery.quantity_damaged > 0
        then 'Se registró la entrega con una novedad pendiente de revisión.'
        else 'Se registró la entrega, pendiente de validación independiente.' end,
      delivery.delivered_at, shipment.shipment_code
    from public.deliveries as delivery
    join public.shipments as shipment on shipment.id = delivery.shipment_id
    join public.shipment_items as shipped on shipped.shipment_id = shipment.id
    join public.allocations as allocation on allocation.id = shipped.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id and delivery.delivered_at is not null

    union all
    select 110, 'delivery_validated', 'Entrega validada',
      'Una persona distinta de quien entregó confirmó el resultado y se actualizó la cobertura.',
      delivery.validated_at, shipment.shipment_code
    from public.deliveries as delivery
    join public.shipments as shipment on shipment.id = delivery.shipment_id
    join public.shipment_items as shipped on shipped.shipment_id = shipment.id
    join public.allocations as allocation on allocation.id = shipped.allocation_id
    join public.inventory_lots as lot on lot.id = allocation.lot_id
    join public.donation_items as item on item.id = lot.donation_item_id
    where donation.id is not null and item.donation_id = donation.id and delivery.validated_at is not null

    -- Dinero
    union all
    select 120, 'money_reconciled', 'Aporte conciliado',
      'Tesorería contrastó el soporte y publicó el monto conciliado.',
      movement.reconciled_at, donation.donor_tracking_code
    from public.financial_transactions as movement
    where donation.id is not null and movement.donation_id = donation.id and movement.reconciled_at is not null
  ) as entry
  where entry.occurred_at is not null
  -- Se ordena por etapa del proceso y no por fecha: el orden lógico del recorrido es un
  -- hecho estable, mientras que una fecha registrada con retraso desordenaría la lectura.
  order by entry.step, entry.occurred_at;
end;
$function$;

-- ---------------------------------------------------------------- el resumen, igual

CREATE OR REPLACE FUNCTION public.track_public_code(p_tracking_code text)
 RETURNS TABLE(code text, record_type text, safe_status text, last_update timestamp with time zone, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  codigo text;
begin
  -- G-066 · misma normalizacion que `track_public_journey`. Las dos se llaman desde la misma
  -- pantalla con el mismo codigo, asi que arreglar solo una habria dejado el resumen vacio
  -- junto a un recorrido completo: peor que fallar entero, porque parece que falta el dato.
  codigo := upper(btrim(coalesce(p_tracking_code, '')));
  if codigo ~ '^(NEC|APO|DON)-[A-F0-9]{24}-[A-F0-9]{8}$' then
    codigo := left(codigo, 28);
  end if;
  if codigo !~ '^(NEC|APO|DON)-[A-F0-9]{24}$' then return; end if;
  return query
    select n.tracking_code, 'need', n.status::text, n.updated_at,
      'Tu reporte está protegido. La ubicación exacta y el contacto no son públicos.'
    from public.need_cases n where n.tracking_code = codigo
    union all
    select i.tracking_code, 'intake', i.status::text, i.updated_at,
      'Esta constancia corresponde a un reporte y no acredita recepción, entrega ni conciliación.'
    from public.donation_intakes i where i.tracking_code = codigo
    union all
    select d.donor_tracking_code, 'donation', d.status::text, d.updated_at,
      'El estado se deriva de eventos operacionales autorizados.'
    from public.donations d where d.donor_tracking_code = codigo
    limit 1;
end;
$function$;
