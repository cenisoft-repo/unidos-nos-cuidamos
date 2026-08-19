-- Fase 13 del loop de consolidación: el seguimiento del movimiento necesita dos estados que el
-- modelo no tenía. La cadena queda
--
--   Preparando → Despachado → En movimiento → Llegó → Recibido
--
-- `preparing` existe para que un despacho pueda armarse con su transporte antes de salir, y
-- `arrived` para distinguir «llegó al destino» de «el destino ya confirmó lo que recibió».
--
-- Los valores viven en su propia migración porque PostgreSQL no permite usar un valor de enum
-- recién agregado dentro de la misma transacción que lo agrega.

alter type public.shipment_status add value if not exists 'preparing' before 'dispatched';
alter type public.shipment_status add value if not exists 'arrived' after 'in_transit';
