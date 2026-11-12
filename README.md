# CampusOS

CampusOS is a React/Vite application backed by Supabase Auth, Postgres, and Storage. The Thapar-inspired workspace and Cedar Ridge University are demo campuses. Their venue capacities, restrictions, and events are illustrative.

## Run locally

1. Install Node.js 22 or newer. From the project directory, run `npm ci` (or `npm install` if a lockfile is unavailable).
2. Create a **development** Supabase project. In its SQL editor, run [the migration](supabase/migrations/20261109000100_core.sql) once, followed by [the demo venue seed](supabase/seed.sql).
3. Copy `.env.example` to `.env.local`. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to the project URL and the public publishable or anon key. Never use the service-role key in the browser.
4. In Supabase Auth, enable email confirmation and allow `http://localhost:5173/profile` as a redirect URL.
5. Run `npm run dev` and open http://localhost:5173.

If hosting with Vercel, import this project as a Vite app, set the same two environment variables, and add the deployed site's `/profile` URL to the Supabase Auth redirect allowlist. The included Vercel configuration supports direct navigation to app routes.

## Try the booking workflow

In the development project's **Authentication → Users**, create and confirm five accounts: `organizer@example.com`, `admin@example.com`, `student@example.com`, `cedar-admin@example.com`, and `platform@example.com`. Choose passwords yourself. Then run [the demo account seed](supabase/demo-accounts.sql). It links the Auth accounts to their demo roles and adds sample bookings and tasks.

1. Sign in as the organizer. Select **Thapar-inspired Demo Campus** and open **Discover Venues → Fete Area**. Review the capacity, past Food Carnival, and booking calendar.
2. Request a future interval with a start and end time and an attendance within capacity. The request appears as pending under **My Bookings** and on the organizer's venue calendar.
3. In a separate browser profile, sign in as the college admin and go to **Admin console → Booking Approvals**. Approve the request.
4. Reload the organizer tab. Check **Dashboard**, the Fete Area calendar, **Notifications**, and the approved event under **My Events**.
5. Try another overlapping request. The database rejects it. Pending requests may overlap one another, but only one can be approved for the same time. Adjacent intervals are allowed.
6. To test onboarding, sign up as a student, verify the email, join a campus in Profile if needed, and submit organizer verification. The campus admin can approve the application. To test a new college, submit its application and approve it as the platform admin.

All displayed and entered booking times use the browser's local time zone; PostgreSQL stores timestamps with time zone. Private proposal and authorization documents are available to the uploader and relevant reviewers. Venue photographs are public. Public calendars expose confirmed titles and blocked intervals; pending requests are limited to their organizer and college admins.

## Verify or deploy without demo data

- Run `npm run build` to check the frontend production bundle.
- Run [the booking integration test](supabase/tests/booking.sql) from the SQL editor **after** the two demo seeds. It checks role enforcement, cross-campus approval rejection, approval propagation, overlap rejection, and adjacent booking acceptance. Its writes are rolled back.
- For a fresh production project, run only the migration. Create and verify the first platform administrator through Supabase Auth, then set `platform_admin=true` for that user's specific UUID in `public.profiles` from the Supabase SQL editor. The app's college application flow can then provision the first administrator for each institution.
- Request-more-information records an admin note. Organizers can cancel and submit a revised request; there is no in-place rescheduling.
