create extension if not exists btree_gist;
create table colleges(id uuid primary key default gen_random_uuid(),name text not null, city text not null, website text, domain text, contact text, designation text, document text, applicant uuid default auth.uid() references auth.users, status text not null default 'pending' check(status in ('pending','approved','rejected','suspended')), demo boolean default false, created_at timestamptz default now());
create table profiles(id uuid primary key references auth.users on delete cascade, name text not null, platform_admin boolean not null default false);
create table college_memberships(college_id uuid references colleges, user_id uuid references profiles, role text not null check(role in ('student','organizer','admin')), primary key(college_id,user_id));
create table societies(id uuid primary key default gen_random_uuid(),college_id uuid not null references colleges,name text not null);
create table verification_requests(id uuid primary key default gen_random_uuid(),college_id uuid not null references colleges,user_id uuid not null default auth.uid() references profiles,society text not null,designation text not null,details text not null,document text,status text not null default 'pending' check(status in ('pending','approved','rejected','revoked')),created_at timestamptz default now());
create unique index verification_pending on verification_requests(college_id,user_id) where status='pending';
create table venues(id uuid primary key default gen_random_uuid(),college_id uuid not null references colleges,name text not null,location text,category text not null,description text,capacity int not null check(capacity>0),setting text not null check(setting in ('Indoor','Outdoor')),restrictions text,image text,active boolean not null default true,unique(id,college_id),unique(college_id,name));
create table venue_facilities(venue_id uuid references venues on delete cascade,name text, primary key(venue_id,name));
create table venue_suitable_event_types(venue_id uuid references venues on delete cascade,name text, primary key(venue_id,name));
create table booking_requests(id uuid primary key default gen_random_uuid(),college_id uuid not null,venue_id uuid not null,organizer uuid not null references profiles,title text not null,society text not null,category text not null,starts_at timestamptz not null,ends_at timestamptz not null,attendance int not null check(attendance>0),description text not null,facilities text,volunteers int default 0 check(volunteers>=0),requirements text,proposal text,status text not null default 'pending' check(status in ('pending','approved','rejected','more_info','cancelled')),reason text,created_at timestamptz default now(),foreign key(venue_id,college_id) references venues(id,college_id),check(starts_at<ends_at),exclude using gist(venue_id with =,tstzrange(starts_at,ends_at,'[)') with &&) where(status='approved'));
create table venue_blocks(id uuid primary key default gen_random_uuid(),venue_id uuid not null references venues,starts_at timestamptz not null,ends_at timestamptz not null,reason text,check(starts_at<ends_at));
create table events(id uuid primary key default gen_random_uuid(),booking_id uuid unique references booking_requests, college_id uuid not null,venue_id uuid not null,organizer uuid references profiles,title text not null,society text not null,category text not null,description text,starts_at timestamptz not null,ends_at timestamptz not null,attendance int,demo boolean default false,photo text,checklist jsonb not null default '{"Venue permission":true,"Sound and lighting":false,"Volunteer allocation":false,"Registration arrangements":false,"Safety coordination":false,"Event-day setup":false}', foreign key(venue_id,college_id) references venues(id,college_id));
create table volunteer_tasks(id uuid primary key default gen_random_uuid(),event_id uuid not null references events,assignee uuid not null references profiles,title text not null,deadline timestamptz,complete boolean default false);
create table attendees(event_id uuid references events,user_id uuid references profiles,registered_at timestamptz default now(),checked_in_at timestamptz,primary key(event_id,user_id));
create table notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references profiles,message text not null,created_at timestamptz default now(),seen boolean default false);
create table approval_audit_logs(id bigint generated always as identity primary key,college_id uuid references colleges,actor uuid references profiles,action text not null,target uuid,created_at timestamptz default now());
create index booking_lookup on booking_requests(venue_id,starts_at);
create index event_lookup on events(college_id,starts_at);
create index block_lookup on venue_blocks(venue_id,starts_at);
create function new_profile() returns trigger language plpgsql security definer set search_path=public as $$begin insert into profiles(id,name) values(new.id,coalesce(nullif(new.raw_user_meta_data->>'name',''),split_part(new.email,'@',1)));return new;end$$;
create trigger new_profile after insert on auth.users for each row execute function new_profile();
create function enroll_verified_user() returns trigger language plpgsql security definer set search_path=public as $$
declare c uuid; m jsonb:=new.raw_user_meta_data;
begin
if new.email_confirmed_at is null or coalesce(m->>'college','') !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then return new;end if;
c:=(m->>'college')::uuid;
if exists(select 1 from colleges where id=c and status='approved') then
 insert into college_memberships values(c,new.id,'student') on conflict do nothing;
 if m->>'intended'='organizer' and nullif(trim(m->>'society'),'') is not null and nullif(trim(m->>'designation'),'') is not null and nullif(trim(m->>'details'),'') is not null then
  insert into verification_requests(college_id,user_id,society,designation,details) values(c,new.id,m->>'society',m->>'designation',m->>'details') on conflict do nothing;
 end if;
end if;
return new;
end$$;
create trigger signup_verified after update of email_confirmed_at on auth.users for each row when(old.email_confirmed_at is null and new.email_confirmed_at is not null) execute function enroll_verified_user();
create function platform() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from profiles where id=auth.uid() and platform_admin)$$;
create function visible(c uuid) returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from colleges where id=c and status='approved')$$;
create function member(c uuid, roles text[]) returns boolean language sql stable security definer set search_path=public as $$select visible(c) and exists(select 1 from college_memberships where college_id=c and user_id=auth.uid() and role=any(roles))$$;
create function admin(c uuid) returns boolean language sql stable security definer set search_path=public as $$select member(c,array['admin'])$$;
create function manage_event(e uuid) returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from events where id=e and (admin(college_id) or (organizer=auth.uid() and member(college_id,array['organizer']))))$$;
do $$declare t text;begin foreach t in array array['colleges','profiles','college_memberships','societies','verification_requests','venues','venue_facilities','venue_suitable_event_types','booking_requests','venue_blocks','events','volunteer_tasks','attendees','notifications','approval_audit_logs'] loop execute format('alter table %I enable row level security',t);execute format('revoke all on %I from anon,authenticated',t);execute format('grant select on %I to anon,authenticated',t);end loop;end$$;
-- Limit public college reads to a directory; contact data is available only through the authorized inbox.
revoke select on colleges from anon,authenticated;
grant select(id,name,city,website,status,demo) on colleges to anon,authenticated;
create policy college_read on colleges for select using(status='approved' or applicant=auth.uid() or platform());
create policy profile_read on profiles for select using(id=auth.uid() or exists(select 1 from college_memberships m where m.user_id=profiles.id and admin(m.college_id)));
create policy membership_read on college_memberships for select using(user_id=auth.uid() or admin(college_id));
create policy society_read on societies for select using(visible(college_id));
create policy verification_read on verification_requests for select using(user_id=auth.uid() or admin(college_id));
create policy venue_read on venues for select using((active and visible(college_id)) or admin(college_id));
create policy facilities_read on venue_facilities for select using(exists(select 1 from venues where id=venue_id));
create policy types_read on venue_suitable_event_types for select using(exists(select 1 from venues where id=venue_id));
create policy booking_read on booking_requests for select using(organizer=auth.uid() or admin(college_id));
create policy block_read on venue_blocks for select using(exists(select 1 from venues where id=venue_id and admin(college_id)));
create policy event_read on events for select using(visible(college_id));
create policy task_read on volunteer_tasks for select using(assignee=auth.uid() or manage_event(event_id));
create policy attendee_read on attendees for select using(user_id=auth.uid() or manage_event(event_id));
create policy notification_read on notifications for select using(user_id=auth.uid());
create policy audit_read on approval_audit_logs for select using(admin(college_id) or platform());

create function campus_action(op text,p jsonb default '{}') returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); c uuid; v uuid; x uuid; who uuid; s text; a timestamptz; z timestamptz; b booking_requests; w venues; q verification_requests; result jsonb; n int;
begin
if u is null then raise exception 'Sign in first';end if;
if (nullif(p->>'document','') is not null and split_part(p->>'document','/',1)<>u::text)
or (nullif(p->>'proposal','') is not null and split_part(p->>'proposal','/',1)<>u::text) then raise exception 'Upload your own attachment';end if;
c:=nullif(p->>'college_id','')::uuid; v:=nullif(p->>'venue_id','')::uuid; x:=nullif(p->>'id','')::uuid;
if op='join' then
 if not visible(c) then raise exception 'College unavailable';end if;
 insert into college_memberships values(c,u,'student') on conflict do nothing;
elsif op='register_college' then
 insert into colleges(name,city,website,domain,contact,designation,document,applicant) values(p->>'name',p->>'city',p->>'website',p->>'domain',p->>'contact',p->>'designation',p->>'document',u);
elsif op='college_inbox' then
 if not platform() then raise exception 'Platform access required';end if;
 return coalesce((select jsonb_agg(to_jsonb(i) order by created_at desc) from colleges i),'[]');
elsif op='college_decision' then
 if not platform() then raise exception 'Platform access required';end if;
 s:=p->>'status'; if s is null or s not in ('approved','rejected','suspended') then raise exception 'Invalid decision';end if;
 update colleges set status=s where id=x returning applicant into who;
 if s='approved' and who is not null then insert into college_memberships values(x,who,'admin') on conflict(college_id,user_id) do update set role='admin';end if;
 insert into approval_audit_logs(college_id,actor,action,target) values(x,u,'College '||s,x);
elsif op='platform_access' then
 if not platform() or x=u then raise exception 'Cannot change this platform role';end if;
 update profiles set platform_admin=coalesce((p->>'enabled')::boolean,false) where id=x;
 insert into approval_audit_logs(actor,action,target) values(u,'Platform access changed',x);
elsif op='verify_request' then
 if not member(c,array['student']) then raise exception 'Join as a student first';end if;
 insert into verification_requests(college_id,user_id,society,designation,details,document) values(c,u,p->>'society',p->>'designation',p->>'details',p->>'document');
elsif op='verify_decision' then
 select * into q from verification_requests where id=x for update;
 if not found or not admin(q.college_id) then raise exception 'College admin required';end if;
 s:=p->>'status';
 if s is null or not ((q.status='pending' and s in ('approved','rejected')) or (q.status='approved' and s='revoked')) then raise exception 'Invalid transition';end if;
 if s='approved' then update college_memberships set role='organizer' where college_id=q.college_id and user_id=q.user_id and role='student'; if not found then raise exception 'Applicant is not a student';end if;end if;
 if s='revoked' then update college_memberships set role='student' where college_id=q.college_id and user_id=q.user_id and role='organizer';end if;
 update verification_requests set status=s where id=x;
 insert into notifications(user_id,message) values(q.user_id,'Organizer verification: '||s);
 insert into approval_audit_logs(college_id,actor,action,target) values(q.college_id,u,'Organizer '||s,x);
elsif op in ('request','review','block','cancel','venue_save') then
 -- Every mutation affecting a venue schedule locks the same venue row first.
 if op in ('review','cancel') then select venue_id into v from booking_requests where id=x;end if;
 if op='venue_save' and v is null then
   if not admin(c) then raise exception 'College admin required';end if;
   insert into venues(college_id,name,category,setting,capacity) values(c,p->>'name',p->>'category',p->>'setting',(p->>'capacity')::int) returning id into v;
 end if;
 select * into w from venues where id=v for update;
 if not found then raise exception 'Venue not found';end if;
 c:=w.college_id;
 if op='request' and not member(c,array['organizer']) then raise exception 'Verified organizer required';end if;
 if op in ('review','block','venue_save') and not admin(c) then raise exception 'College admin required';end if;
 if op in ('review','cancel') then
   select * into b from booking_requests where id=x for update;
   if op='cancel' then
     if b.organizer<>u or not member(c,array['organizer']) or b.status not in ('pending','approved','more_info') or b.starts_at<=now() then raise exception 'Cannot cancel this booking';end if;
     s:='cancelled';
   else
     s:=p->>'status';
     if b.status not in ('pending','more_info') or s is null or s not in ('approved','rejected','more_info') then raise exception 'Invalid booking decision';end if;
     if s<>'approved' and coalesce(trim(p->>'reason'),'')='' then raise exception 'Enter a reason';end if;
   end if;
   a:=b.starts_at; z:=b.ends_at; n:=b.attendance;
 else a:=(p->>'starts_at')::timestamptz; z:=(p->>'ends_at')::timestamptz; n:=(p->>'attendance')::int;
 end if;
 if op in ('request','block') or s='approved' then
   if a is null or z is null or a>=z or a<=now() then raise exception 'Select a valid future interval';end if;
   if op<>'block' and (not w.active or n is null or n<1 or n>w.capacity) then raise exception 'Venue is inactive or attendance exceeds capacity';end if;
   if exists(select 1 from booking_requests where venue_id=v and status='approved' and starts_at<z and ends_at>a) or exists(select 1 from venue_blocks where venue_id=v and starts_at<z and ends_at>a) then raise exception 'This time overlaps a confirmed reservation or venue block';end if;
 end if;
 if op='request' then
   insert into booking_requests(college_id,venue_id,organizer,title,society,category,starts_at,ends_at,attendance,description,facilities,volunteers,requirements,proposal) values(c,v,u,p->>'title',p->>'society',p->>'category',a,z,n,p->>'description',p->>'facilities',coalesce((p->>'volunteers')::int,0),p->>'requirements',p->>'proposal') returning id into x;
 elsif op='block' then insert into venue_blocks(venue_id,starts_at,ends_at,reason) values(v,a,z,p->>'reason') returning id into x;
 elsif op='venue_save' then
   update venues set name=p->>'name',category=p->>'category',setting=p->>'setting',capacity=(p->>'capacity')::int,location=p->>'location',description=p->>'description',restrictions=p->>'restrictions',image=nullif(p->>'image',''),active=coalesce((p->>'active')::boolean,true) where id=v;
   delete from venue_facilities where venue_id=v;
   insert into venue_facilities select v,value from jsonb_array_elements_text(coalesce(p->'facilities','[]')) on conflict do nothing;
   delete from venue_suitable_event_types where venue_id=v;
   insert into venue_suitable_event_types select v,value from jsonb_array_elements_text(coalesce(p->'types','[]')) on conflict do nothing;
   x:=v;
 else
   update booking_requests set status=s,reason=p->>'reason' where id=x;
   if s='approved' then
     insert into events(booking_id,college_id,venue_id,organizer,title,society,category,description,starts_at,ends_at,demo) values(x,c,v,b.organizer,b.title,b.society,b.category,b.description,a,z,(select demo from colleges where id=c));
   elsif s='cancelled' then
     delete from volunteer_tasks where event_id in(select id from events where booking_id=x);
     delete from attendees where event_id in(select id from events where booking_id=x);
     delete from events where booking_id=x;
   end if;
   insert into notifications(user_id,message) values(b.organizer,b.title||': '||replace(s,'_',' ')||coalesce(' — '||(p->>'reason'),''));
 end if;
 insert into approval_audit_logs(college_id,actor,action,target) values(c,u,op||coalesce(' '||s,''),x);
elsif op='register_event' then
 if not exists(select 1 from events where id=x and ends_at>now() and member(college_id,array['student','organizer','admin'])) then raise exception 'Join this campus to register for an upcoming event';end if;
 insert into attendees(event_id,user_id) values(x,u) on conflict do nothing;
elsif op='checkin' then
 if not manage_event(x) then raise exception 'Event manager required';end if;
 update attendees set checked_in_at=now() where event_id=x and user_id=(p->>'user_id')::uuid and checked_in_at is null;
elsif op='event_people' then
 select college_id into c from events where id=x;
 if not manage_event(x) then raise exception 'Event manager required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',m.user_id,'name',pr.name)) from college_memberships m join profiles pr on pr.id=m.user_id where m.college_id=c),'[]');
elsif op='task_add' then
 select college_id into c from events where id=x;
 who:=(p->>'assignee')::uuid;
 if not manage_event(x) or not exists(select 1 from college_memberships where college_id=c and user_id=who) then raise exception 'Select a member of this campus';end if;
 insert into volunteer_tasks(event_id,assignee,title,deadline) values(x,who,p->>'title',nullif(p->>'deadline','')::timestamptz);
 insert into notifications(user_id,message) values(who,'New volunteer task: '||(p->>'title'));
elsif op='task_done' then
 update volunteer_tasks set complete=true where id=x and assignee=u;
elsif op='checklist' then
 if not manage_event(x) then raise exception 'Event manager required';end if;
 update events set checklist=jsonb_set(checklist,array[p->>'item'],to_jsonb((p->>'done')::boolean),false) where id=x;
elsif op='seen' then update notifications set seen=true where user_id=u;
elsif op='profile' then update profiles set name=p->>'name' where id=u;
else raise exception 'Unknown action';
end if;
return jsonb_build_object('id',x);
end$$;
revoke execute on function campus_action(text,jsonb) from public,anon;
grant execute on function campus_action(text,jsonb) to authenticated;

create function venue_schedule(c uuid,a timestamptz,z timestamptz) returns table(venue_id uuid, starts_at timestamptz, ends_at timestamptz, state text,title text)
language sql stable security definer set search_path=public as $$
select b.venue_id,b.starts_at,b.ends_at,b.status,case when b.status='approved' or b.organizer=auth.uid() or admin(c) then b.title else 'Pending request' end
from booking_requests b join venues v on v.id=b.venue_id where b.college_id=c and visible(c) and (v.active or admin(c)) and b.starts_at<z and b.ends_at>a and (b.status='approved' or (b.status in ('pending','more_info') and (b.organizer=auth.uid() or admin(c))))
union all select k.venue_id,k.starts_at,k.ends_at,'blocked','Unavailable' from venue_blocks k join venues v on v.id=k.venue_id where v.college_id=c and visible(c) and (v.active or admin(c)) and k.starts_at<z and k.ends_at>a
$$;
grant execute on function venue_schedule(uuid,timestamptz,timestamptz) to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('venue-photos','venue-photos',true,5242880,array['image/jpeg','image/png','image/webp']),
('campus-documents','campus-documents',false,10485760,array['application/pdf','image/jpeg','image/png']);
create policy venue_photo_upload on storage.objects for insert to authenticated with check(bucket_id='venue-photos' and admin((storage.foldername(name))[1]::uuid));
create policy document_upload on storage.objects for insert to authenticated with check(bucket_id='campus-documents' and (storage.foldername(name))[1]=auth.uid()::text);
create function can_read_document(path text) returns boolean language sql stable security definer set search_path=public as $$
select split_part(path,'/',1)=auth.uid()::text or exists(select 1 from verification_requests q where q.document=path and admin(q.college_id)) or exists(select 1 from booking_requests b where b.proposal=path and admin(b.college_id)) or (platform() and exists(select 1 from colleges c where c.document=path))
$$;
revoke execute on function can_read_document(text) from public,anon;
grant execute on function can_read_document(text) to authenticated;
create policy document_read on storage.objects for select to authenticated using(bucket_id='campus-documents' and can_read_document(name));
