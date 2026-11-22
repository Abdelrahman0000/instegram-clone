-- Instagram Clone. Isolated project schema, least-privilege client access.
begin;
create extension if not exists pgcrypto;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text not null unique check(username ~ '^[a-z0-9_.]{3,24}$'),
 full_name text not null default '' check(char_length(full_name)<=60),
 bio text not null default '' check(char_length(bio)<=160),
 avatar_url text not null default '', website text not null default '' check(char_length(website)<=200),
 is_seed boolean not null default false, created_at timestamptz not null default now()
);
create table public.posts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles on delete cascade,
 caption text not null default '' check(char_length(caption)<=2200), media_url text not null,
 media_type text not null check(media_type in ('image','video')), location text not null default '' check(char_length(location)<=100),
 created_at timestamptz not null default now()
);
create table public.likes (post_id uuid references public.posts on delete cascade,user_id uuid references public.profiles on delete cascade,created_at timestamptz default now(),primary key(post_id,user_id));
create table public.comments (id uuid primary key default gen_random_uuid(),post_id uuid not null references public.posts on delete cascade,user_id uuid not null references public.profiles on delete cascade,body text not null check(char_length(body) between 1 and 1000),created_at timestamptz not null default now());
create table public.saves (post_id uuid references public.posts on delete cascade,user_id uuid references public.profiles on delete cascade,created_at timestamptz default now(),primary key(post_id,user_id));
create table public.follows (follower_id uuid references public.profiles on delete cascade,following_id uuid references public.profiles on delete cascade,created_at timestamptz default now(),primary key(follower_id,following_id),check(follower_id<>following_id));
create table public.friendships (id uuid primary key default gen_random_uuid(),requester_id uuid not null references public.profiles on delete cascade,addressee_id uuid not null references public.profiles on delete cascade,status text not null default 'pending' check(status in ('pending','accepted')),created_at timestamptz not null default now(),check(requester_id<>addressee_id));
create unique index friendship_pair on public.friendships(least(requester_id,addressee_id),greatest(requester_id,addressee_id));
create table public.messages (id uuid primary key default gen_random_uuid(),sender_id uuid not null references public.profiles on delete cascade,recipient_id uuid not null references public.profiles on delete cascade,body text not null default '' check(char_length(body)<=2000),media_url text,media_type text check(media_type in ('image','video')),post_id uuid references public.posts on delete set null,read_at timestamptz,created_at timestamptz not null default now(),check(sender_id<>recipient_id),check(char_length(body)>0 or media_url is not null or post_id is not null));
create table public.stories (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles on delete cascade,media_url text not null,media_type text not null check(media_type in ('image','video')),caption text not null default '' check(char_length(caption)<=200),created_at timestamptz not null default now(),expires_at timestamptz not null default(now()+interval '24 hours'));
create table public.story_views (story_id uuid references public.stories on delete cascade,user_id uuid references public.profiles on delete cascade,created_at timestamptz default now(),primary key(story_id,user_id));
create table public.notifications (id uuid primary key default gen_random_uuid(),recipient_id uuid not null references public.profiles on delete cascade,actor_id uuid not null references public.profiles on delete cascade,kind text not null,post_id uuid references public.posts on delete cascade,is_read boolean not null default false,created_at timestamptz not null default now());
create index posts_time on public.posts(created_at desc);
create index comments_post on public.comments(post_id,created_at);
create index follows_target on public.follows(following_id);
create index messages_recipient on public.messages(recipient_id,created_at desc);
create index messages_sender on public.messages(sender_id,created_at desc);
create index notifications_recipient on public.notifications(recipient_id,created_at desc);
create index stories_expiry on public.stories(expires_at);

create function public.new_profile() returns trigger language plpgsql security definer set search_path='' as $$
declare candidate text;
begin
 candidate:=lower(coalesce(new.raw_user_meta_data->>'username','user_'||substr(replace(new.id::text,'-',''),1,12)));
 if candidate !~ '^[a-z0-9_.]{3,24}$' then raise exception 'Username must use 3-24 lowercase letters, numbers, dots or underscores'; end if;
 insert into public.profiles(id,username,full_name) values(new.id,candidate,left(coalesce(new.raw_user_meta_data->>'full_name',''),60));
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_profile();

-- Public feed metadata is visible, but emails, saves, relationships and chats are not exposed.
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.saves enable row level security;
alter table public.follows enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;
alter table public.stories enable row level security;
alter table public.story_views enable row level security;
alter table public.notifications enable row level security;
revoke all on public.profiles,public.posts,public.likes,public.comments,public.saves,public.follows,public.friendships,public.messages,public.stories,public.story_views,public.notifications from anon,authenticated;
grant select on public.profiles,public.posts,public.likes,public.comments,public.follows,public.stories to anon,authenticated;
grant select on public.saves,public.friendships,public.messages,public.story_views,public.notifications to authenticated;
grant update(username,full_name,bio,avatar_url,website) on public.profiles to authenticated;
grant insert,delete on public.posts,public.likes,public.comments,public.saves,public.follows,public.messages,public.stories,public.story_views to authenticated;
grant update(caption,location) on public.posts to authenticated;
grant update(body) on public.comments to authenticated;
grant update(is_read) on public.notifications to authenticated;

create policy profiles_read on public.profiles for select using(true);
create policy profiles_own_update on public.profiles for update to authenticated using(id=(select auth.uid()) and not is_seed) with check(id=(select auth.uid()));
create policy posts_read on public.posts for select using(true);
create policy posts_own_insert on public.posts for insert to authenticated with check(user_id=(select auth.uid()) and media_url like 'https://hzxaapssxluttyzaycse.supabase.co/storage/v1/object/public/media/'||auth.uid()::text||'/%');
create policy posts_own_update on public.posts for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy posts_own_delete on public.posts for delete to authenticated using(user_id=(select auth.uid()));
create policy likes_read on public.likes for select using(true);
create policy likes_own_insert on public.likes for insert to authenticated with check(user_id=(select auth.uid()));
create policy likes_own_delete on public.likes for delete to authenticated using(user_id=(select auth.uid()));
create policy comments_read on public.comments for select using(true);
create policy comments_own_insert on public.comments for insert to authenticated with check(user_id=(select auth.uid()));
create policy comments_own_update on public.comments for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy comments_delete on public.comments for delete to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.posts where id=post_id and user_id=(select auth.uid())));
create policy saves_own_select on public.saves for select to authenticated using(user_id=(select auth.uid()));
create policy saves_own_insert on public.saves for insert to authenticated with check(user_id=(select auth.uid()));
create policy saves_own_delete on public.saves for delete to authenticated using(user_id=(select auth.uid()));
create policy follows_read on public.follows for select using(true);
create policy follows_own_insert on public.follows for insert to authenticated with check(follower_id=(select auth.uid()));
create policy follows_own_delete on public.follows for delete to authenticated using(follower_id=(select auth.uid()));
create policy friendships_participant on public.friendships for select to authenticated using((select auth.uid()) in(requester_id,addressee_id));
create policy messages_participant on public.messages for select to authenticated using((select auth.uid()) in(sender_id,recipient_id));
create policy messages_send on public.messages for insert to authenticated with check(sender_id=(select auth.uid()) and (media_url is null or media_url like 'https://hzxaapssxluttyzaycse.supabase.co/storage/v1/object/authenticated/chat-media/'||auth.uid()::text||'/%'));
create policy messages_own_delete on public.messages for delete to authenticated using(sender_id=(select auth.uid()));
create policy stories_live on public.stories for select using(expires_at>now());
create policy stories_own_insert on public.stories for insert to authenticated with check(user_id=(select auth.uid()) and expires_at<=now()+interval '24 hours 1 minute' and media_url like 'https://hzxaapssxluttyzaycse.supabase.co/storage/v1/object/public/media/'||auth.uid()::text||'/%');
create policy stories_own_delete on public.stories for delete to authenticated using(user_id=(select auth.uid()));
create policy story_views_select on public.story_views for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.stories where id=story_id and user_id=(select auth.uid())));
create policy story_views_insert on public.story_views for insert to authenticated with check(user_id=(select auth.uid()));
create policy notifications_own on public.notifications for select to authenticated using(recipient_id=(select auth.uid()));
create policy notifications_read on public.notifications for update to authenticated using(recipient_id=(select auth.uid())) with check(recipient_id=(select auth.uid()));

create function public.request_friend(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or auth.uid()=target then raise exception 'Sign in to add a friend'; end if;
 insert into public.friendships(requester_id,addressee_id,status) select auth.uid(),target,case when is_seed then 'accepted' else 'pending' end from public.profiles where id=target;
 insert into public.notifications(recipient_id,actor_id,kind) values(target,auth.uid(),'friend_request');
end $$;
create function public.respond_friend(friendship uuid,accept boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if accept then update public.friendships set status='accepted' where id=friendship and addressee_id=auth.uid() and status='pending';
 else delete from public.friendships where id=friendship and addressee_id=auth.uid() and status='pending'; end if;
end $$;
create function public.remove_friend(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 delete from public.friendships where (requester_id=auth.uid() and addressee_id=target) or (addressee_id=auth.uid() and requester_id=target);
end $$;
create function public.mark_messages_read(sender uuid) returns void language sql security definer set search_path='' as $$ update public.messages set read_at=now() where recipient_id=auth.uid() and sender_id=sender and read_at is null $$;
create function public.delete_my_account() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 delete from auth.users where id=auth.uid();
end $$;
-- No private data in triggers, just a notification for the affected account.
create function public.activity_notification() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid; actor uuid; post uuid; event text;
begin
 if tg_table_name='likes' or tg_table_name='comments' then
  select user_id into target from public.posts where id=new.post_id; actor:=new.user_id; post:=new.post_id; event:=case when tg_table_name='likes' then 'like' else 'comment' end;
 elsif tg_table_name='follows' then target:=new.following_id; actor:=new.follower_id; event:='follow';
 else target:=new.recipient_id; actor:=new.sender_id; event:='message'; end if;
 if target is not null and target<>actor then insert into public.notifications(recipient_id,actor_id,kind,post_id) values(target,actor,event,post); end if;
 return new;
end $$;
create trigger like_notice after insert on public.likes for each row execute function public.activity_notification();
create trigger comment_notice after insert on public.comments for each row execute function public.activity_notification();
create trigger follow_notice after insert on public.follows for each row execute function public.activity_notification();
create trigger message_notice after insert on public.messages for each row execute function public.activity_notification();
revoke all on function public.new_profile(),public.activity_notification(),public.request_friend(uuid),public.respond_friend(uuid,boolean),public.remove_friend(uuid),public.mark_messages_read(uuid),public.delete_my_account() from public,anon,authenticated;
grant execute on function public.request_friend(uuid),public.respond_friend(uuid,boolean),public.remove_friend(uuid),public.mark_messages_read(uuid),public.delete_my_account() to authenticated;

-- Public posts and avatars, private chat attachments. Maximum file size 20 MB.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('media','media',true,20971520,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']),('chat-media','chat-media',false,20971520,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm']);
create policy media_public_read on storage.objects for select using(bucket_id='media');
create policy media_own_insert on storage.objects for insert to authenticated with check(bucket_id in('media','chat-media') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy media_own_delete on storage.objects for delete to authenticated using(bucket_id in('media','chat-media') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy private_chat_read on storage.objects for select to authenticated using(bucket_id='chat-media' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(select 1 from public.messages m where m.recipient_id=(select auth.uid()) and m.media_url='https://hzxaapssxluttyzaycse.supabase.co/storage/v1/object/authenticated/chat-media/'||name)));
-- Notifications and messages refresh on events. A timed UI fallback is not required.
alter publication supabase_realtime add table public.messages,public.notifications,public.friendships,public.posts,public.likes,public.comments,public.follows;
commit;
