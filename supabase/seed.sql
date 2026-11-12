insert into colleges(id,name,city,status,demo) values
('10000000-0000-4000-8000-000000000001','Thapar-inspired Demo Campus','Patiala, Punjab','approved',true),
('10000000-0000-4000-8000-000000000002','Cedar Ridge University','Fictional campus','approved',true)
on conflict do nothing;
with fixtures(n,c,setting,capacity,category,description,facilities,types) as (values
(1,1,'Outdoor',450,'Amphitheatre','Open-air seating and stage for performances.',array['Stage','Lighting'],array['Concert','Cultural performance']),
(2,1,'Indoor',320,'Auditorium','A seated hall for talks and formal events.',array['Projector','Sound','Stage'],array['Conference','Lecture','Ceremony']),
(3,1,'Indoor',150,'Auditorium','A flexible lecture and panel venue.',array['Projector','Sound','Wi-Fi'],array['Seminar','Workshop','Panel']),
(4,1,'Outdoor',120,'Walkway','A pedestrian space for displays and pop-ups.',array['Power','Display space'],array['Exhibition','Pop-up','Society showcase']),
(5,1,'Outdoor',600,'Event lawn','An open event lawn with room for stalls and gatherings.',array['Power','Stall space','Outdoor lighting'],array['Fete','Food carnival','Exhibition','Student market']),
(6,1,'Indoor',260,'Assembly hall','A demo assembly space for formal campus events.',array['Stage','Sound'],array['Convocation','Ceremony']),
(7,1,'Outdoor',240,'Campus plaza','An outdoor plaza for stalls and campus activities.',array['Power','Stall space'],array['Street festival','Student market']),
(8,2,'Indoor',180,'Lecture hall','A seated hall for presentations.',array['Projector','Wi-Fi'],array['Lecture','Seminar']),
(9,2,'Outdoor',500,'Event lawn','An open field for campus fairs.',array['Power','Stall space'],array['Fete','Concert']),
(10,2,'Indoor',75,'Studio','A smaller hands-on teaching and meeting space.',array['Wi-Fi','Worktables'],array['Workshop','Exhibition'])
), keyed as (select *,('20000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid vid from fixtures),
ins as (insert into venues(id,college_id,name,location,category,description,capacity,setting,restrictions)
select vid,('10000000-0000-4000-8000-'||lpad(c::text,12,'0'))::uuid,
(array['OAT','Main Auditorium','TAN Auditorium','Skywalk','Fete Area','CSED','H Chock','Juniper Hall','Cedar Green','Foundry Studio'])[n],
'Demo campus grounds',category,description,capacity,setting,'Illustrative capacity; confirm real venue limits and permissions independently.' from keyed on conflict do nothing returning id),
facility_insert as (insert into venue_facilities select vid,unnest(facilities) from keyed where vid in(select id from ins) on conflict do nothing)
insert into venue_suitable_event_types select vid,unnest(types) from keyed where vid in(select id from ins) on conflict do nothing;
insert into events(id,college_id,venue_id,title,society,category,description,starts_at,ends_at,attendance,demo)
select ('30000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
'10000000-0000-4000-8000-000000000001',('20000000-0000-4000-8000-'||lpad(v::text,12,'0'))::uuid,title,society,category,'Fictional example event for the CampusOS demo.',now()-n*interval '12 days',now()-n*interval '12 days'+interval '2 hours',att,true
from (values(1,5,'Campus Food Carnival','Student Council','Food carnival',285),(2,4,'Student Club Showcase','Campus Clubs','Exhibition',90),(3,1,'Cultural Night','Cultural Society','Cultural performance',310),(4,6,'Convocation','Academic Office','Convocation',225),(5,7,'Street Fest','Student Council','Street festival',180),(6,2,'Guest Lecture','Debate Society','Lecture',120),(7,3,'Technical Seminar','Tech Society','Seminar',108)) a(n,v,title,society,category,att)
on conflict do nothing;
