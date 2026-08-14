-- PostgreSQL no crea índices automáticamente para las columnas que referencian
-- claves foráneas. Indexarlas evita escaneos completos en joins, RLS y cascadas.

do $$
declare
  target record;
  target_index_name text;
begin
  for target in
    select distinct
      table_schema.nspname as schema_name,
      target_table.relname as table_name,
      target_column.attname as column_name
    from pg_catalog.pg_constraint as foreign_key
    join pg_catalog.pg_class as target_table
      on target_table.oid = foreign_key.conrelid
    join pg_catalog.pg_namespace as table_schema
      on table_schema.oid = target_table.relnamespace
    join lateral unnest(foreign_key.conkey) as key_column(attnum)
      on true
    join pg_catalog.pg_attribute as target_column
      on target_column.attrelid = foreign_key.conrelid
      and target_column.attnum = key_column.attnum
    where foreign_key.contype = 'f'
      and table_schema.nspname = 'public'
      and not exists (
        select 1
        from pg_catalog.pg_index as existing_index
        where existing_index.indrelid = foreign_key.conrelid
          and key_column.attnum = any(existing_index.indkey)
      )
  loop
    target_index_name := format(
      'fk_%s_%s_%s_idx',
      left(target.table_name, 24),
      left(target.column_name, 20),
      substr(md5(target.schema_name || '.' || target.table_name || '.' || target.column_name), 1, 8)
    );

    execute format(
      'create index if not exists %I on %I.%I (%I)',
      target_index_name,
      target.schema_name,
      target.table_name,
      target.column_name
    );
  end loop;
end;
$$;
