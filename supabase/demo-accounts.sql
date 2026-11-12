-- Create these five confirmed Auth accounts in a development project before running.
do $$
declare c uuid:='10000000-0000-4000-8000-000000000001'; d uuid:='10000000-0000-4000-8000-000000000002'; a uuid; o uuid; s uuid; k uuid; p uuid; b uuid;
begin
select id into a from auth.users where email='admin@example.com';
select id into o from auth.users where email='organizer@example.com';
select id into s from auth.users where email='student@example.com';
select id into k from auth.users where email='cedar-admin@example.com';
select id into p from auth.users where email='platform@example.com';
if a is null or o is null or s is null or k is null or p is null then raise exception 'Create all five demo accounts first';end if;
update profiles set platform_admin=true where id=p;
insert into college_memberships values(c,a,'admin'),(c,o,'organizer'),(c,s,'student'),(d,k,'admin') on conflict do nothing;
insert into verification_requests(id,college_id,user_id,society,designation,details) values('40000000-0000-4000-8000-000000000001',c,s,'Campus Club','Coordinator','Illustrative verification application.') on conflict do nothing;
insert into booking_requests(id,college_id,venue_id,organizer,title,society,category,starts_at,ends_at,attendance,description,status,reason)
select ('50000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,c,('20000000-0000-4000-8000-'||lpad(v::text,12,'0'))::uuid,o,title,'Tech Society',category,now()+n*interval '3 days',now()+n*interval '3 days'+interval '2 hours',60,'Fictional demonstration booking.',status,reason
from (values (1,3,'Technical Seminar','Seminar','approved',null),(2,7,'Street Fest','Street festival','pending',null),(3,1,'Cultural Night','Cultural performance','rejected','A revised event plan is needed.')) a(n,v,title,category,status,reason)
on conflict do nothing;
b:='50000000-0000-4000-8000-000000000001';
insert into events(id,booking_id,college_id,venue_id,organizer,title,society,category,description,starts_at,ends_at,demo)
select '60000000-0000-4000-8000-000000000001',id,c,venue_id,o,title,society,category,description,starts_at,ends_at,true from booking_requests where id=b and status='approved'
on conflict do nothing;
insert into volunteer_tasks(id,event_id,assignee,title,deadline) select '70000000-0000-4000-8000-000000000001',id,s,'Set up the registration desk',starts_at-interval '1 hour' from events where booking_id=b on conflict do nothing;
end$$;
