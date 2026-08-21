-- G-066 · Un codigo que la plataforma publica, la plataforma tiene que reconocerlo.
--
-- `/transparencia` y la exportacion a Excel publican el codigo de un aporte en especie con un
-- sufijo por articulo —37 caracteres— y las dos RPC de seguimiento solo admitian los 28 de la
-- forma base. En produccion, seis de los once codigos publicados eran irresolubles.
--
-- Lo que se fija aqui es la relacion, no el formato: **lo que la proyeccion publica tiene que
-- resolverse**. Si manana cambia la forma del codigo, esta prueba sigue siendo la correcta.

begin;
select plan(9);

create temporary table aporte as
select donor_tracking_code as base, donor_tracking_code || '-2423fe3b' as publicado
from public.donations where donor_tracking_code is not null limit 1;

-- ------------------------------------------------------- la forma que se publica resuelve --
select ok(
  (select count(*)::integer from public.track_public_journey((select publicado from aporte))) > 0,
  'El recorrido resuelve el codigo con sufijo de articulo, que es el que se publica'
);
select is(
  (select count(*)::integer from public.track_public_journey((select publicado from aporte))),
  (select count(*)::integer from public.track_public_journey((select base from aporte))),
  'Y devuelve exactamente el mismo recorrido que la forma base: el sufijo identifica el articulo, no otro aporte'
);
select ok(
  (select count(*)::integer from public.track_public_code((select publicado from aporte))) > 0,
  'El resumen tambien lo resuelve: arreglar solo una de las dos dejaria media pantalla vacia'
);
-- Quien copia del portal no copia mayusculas con cuidado.
select ok(
  (select count(*)::integer from public.track_public_journey(lower((select publicado from aporte)))) > 0,
  'Da igual en que caja se pegue'
);
select ok(
  (select count(*)::integer from public.track_public_journey('  ' || (select publicado from aporte) || '  ')) > 0,
  'Y da igual que arrastre espacios al copiar'
);

-- --------------------------------------------------- pero la guarda NO se ha relajado --
-- Admitir la forma publicada no puede convertirse en admitir cualquier cosa: esa guarda
-- existe para que nadie barra la base probando codigos.
select is(
  (select count(*)::integer from public.track_public_journey((select base from aporte) || '-zzzzzzzz')),
  0,
  'Un sufijo que no es hexadecimal se rechaza'
);
select is(
  (select count(*)::integer from public.track_public_journey((select base from aporte) || '-2423fe3b-2423fe3b')),
  0,
  'Dos sufijos encadenados se rechazan'
);
select is(
  (select count(*)::integer from public.track_public_journey('DON-NOESUNCODIGO')),
  0,
  'Una cadena que no tiene la forma de un codigo se rechaza'
);
select is(
  (select count(*)::integer from public.track_public_code('%')),
  0,
  'Y un comodin no devuelve la base entera'
);

select * from finish();
rollback;
