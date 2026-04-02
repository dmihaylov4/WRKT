-- Barbell racked plates: stores which plates each user has racked on their barbell.
-- rack_position stores slot index 0-3 only (bilateral rendering: one row = both sides of the bar).

create table barbell_racked_plates (
    user_id uuid references auth.users(id) on delete cascade,
    tier_id smallint not null,
    weight_kg real not null,
    engraving_text text not null default '',
    rack_position smallint not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, rack_position)
);

alter table barbell_racked_plates enable row level security;

create policy "Users can manage own racked plates"
    on barbell_racked_plates
    for all
    using (auth.uid() = user_id);

create policy "Friends can view racked plates"
    on barbell_racked_plates
    for select
    using (
        exists (
            select 1 from friendships
            where status = 'accepted'
              and (
                (user_id = auth.uid() and friend_id = barbell_racked_plates.user_id)
                or (friend_id = auth.uid() and user_id = barbell_racked_plates.user_id)
              )
        )
    );
