-- Normalize unracked earned plate rows before constraint checks.
-- This keeps older clients safe if they set is_racked = false but omit rack_position.

create or replace function public.set_earned_plates_updated_at()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.is_racked = false then
        new.rack_position = null;
    end if;
    new.updated_at = now();
    return new;
end;
$$;

revoke execute on function public.set_earned_plates_updated_at() from public, anon, authenticated;
