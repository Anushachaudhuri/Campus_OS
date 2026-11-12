-- Run after seed.sql and demo-accounts.sql in a disposable database.
begin;
do $$
declare c uuid:='10000000-0000-4000-8000-000000000001'; v uuid:='20000000-0000-4000-8000-000000000005'; o uuid; s uuid; a uuid; k uuid; b uuid; b2 uuid; req jsonb; t timestamptz:=now()+interval '40 days';
begin
select id into o from auth.users where email='organizer@example.com';
select id into s from auth.users where email='student@example.com';
select id into a from auth.users where email='admin@example.com';
select id into k from auth.users where email='cedar-admin@example.com';
if o is null or s is null or a is null or k is null then raise exception 'Missing test fixtures';end if;
req:=jsonb_build_object('venue_id',v,'title','Test booking','society','Test society','category','Fete','starts_at',t,'ends_at',t+interval '2 hours','attendance',20,'description','Integration test');
perform set_config('request.jwt.claim.sub',s::text,true);
begin perform campus_action('request',req);raise exception 'Unexpected permission';exception when raise_exception then if sqlerrm<>'Verified organizer required' then raise;end if;end;
perform set_config('request.jwt.claim.sub',o::text,true);
b:=(campus_action('request',req)->>'id')::uuid;
b2:=(campus_action('request',req)->>'id')::uuid;
perform set_config('request.jwt.claim.sub',k::text,true);
begin perform campus_action('review',jsonb_build_object('id',b,'status','approved'));raise exception 'Unexpected permission';exception when raise_exception then if sqlerrm<>'College admin required' then raise;end if;end;
perform set_config('request.jwt.claim.sub',a::text,true);
perform campus_action('review',jsonb_build_object('id',b,'status','approved'));
if not exists(select 1 from events where booking_id=b) or not exists(select 1 from notifications where user_id=o and message='Test booking: approved') or not exists(select 1 from venue_schedule(c,t,t+interval '2 hours') where venue_id=v and state='approved') then raise exception 'Approval did not propagate';end if;
begin perform campus_action('review',jsonb_build_object('id',b2,'status','approved'));raise exception 'Expected conflict';exception when raise_exception then if sqlerrm<>'This time overlaps a confirmed reservation or venue block' then raise;end if;end;
perform set_config('request.jwt.claim.sub',o::text,true);
perform campus_action('request',req||jsonb_build_object('starts_at',t+interval '2 hours','ends_at',t+interval '3 hours'));
perform set_config('request.jwt.claim.sub',k::text,true);
end$$;
set local role authenticated;
do $$begin
 if not admin('10000000-0000-4000-8000-000000000002') then raise exception 'Missing Cedar admin context';end if;
 if exists(select 1 from booking_requests where college_id='10000000-0000-4000-8000-000000000001') then raise exception 'Private booking leaked';end if;
 if exists(select 1 from verification_requests where college_id='10000000-0000-4000-8000-000000000001') then raise exception 'Private verification request leaked';end if;
end$$;
rollback;
