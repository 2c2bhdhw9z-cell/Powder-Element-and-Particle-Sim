create table if not exists lab_saves (
  id text primary key,
  user_id text not null,
  name text not null,
  mode text not null,
  data text not null,
  created_at timestamptz not null default now()
);
create index if not exists lab_saves_user_idx on lab_saves (user_id, created_at desc);

create table if not exists lab_maps (
  id text primary key,
  user_id text not null,
  title text not null,
  author text not null,
  description text not null default '',
  tags text not null default '',
  thumbnail text not null default '',
  grid_data text not null,
  likes int not null default 0,
  downloads int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists lab_maps_created_idx on lab_maps (created_at desc);
