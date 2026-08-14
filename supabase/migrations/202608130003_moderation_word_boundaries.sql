create or replace function public.contains_sensitive_content(input text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(input, '') ~* '(\+?57[[:space:]-]?)?3[0-9]{2}[[:space:]-]?[0-9]{3}[[:space:]-]?[0-9]{4}|\m(cuenta|cuentas|ahorros|corriente|nequi|daviplata|bancolombia)\M|n[uú]mero de tarjeta|https?://';
$$;
