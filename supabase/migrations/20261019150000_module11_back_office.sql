-- Module 11 (F4): the back office writes stock. A count replaces the book; a delivery
-- or a write-off moves it by a delta, in one statement, so two tablets recording
-- at once can't overwrite each other (no read-then-write from the app).

create or replace function public.set_stock_count(p_ingredient text, p_amount_minor_units bigint)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_stock bigint;
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = 'insufficient_privilege';
  end if;
  update public.raw_ingredients
     set stock_minor_units = p_amount_minor_units, updated_at = now()
   where id = p_ingredient
  returning stock_minor_units into v_stock;
  if v_stock is null then
    raise exception 'no such ingredient' using errcode = 'no_data_found';
  end if;
  return v_stock;
end $$;

create or replace function public.adjust_stock(p_ingredient text, p_delta_minor_units bigint)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_stock bigint;
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = 'insufficient_privilege';
  end if;
  update public.raw_ingredients
     set stock_minor_units = stock_minor_units + p_delta_minor_units, updated_at = now()
   where id = p_ingredient
  returning stock_minor_units into v_stock;
  if v_stock is null then
    raise exception 'no such ingredient' using errcode = 'no_data_found';
  end if;
  return v_stock;
end $$;

revoke all on function public.set_stock_count(text, bigint), public.adjust_stock(text, bigint)
  from public, anon;
grant execute on function public.set_stock_count(text, bigint), public.adjust_stock(text, bigint)
  to authenticated;
