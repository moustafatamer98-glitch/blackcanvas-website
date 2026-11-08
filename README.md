# Black Canvas website

The website for Black Canvas, a full-service event management company across Saudi Arabia and the Globe.

It is a single static page: `index.html` plus the project photos in `img/`. There is no build step.

## Publish with GitHub Pages

1. In this repository, open **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to *Deploy from a branch*, choose the `main` branch and the `/ (root)` folder, and save.
3. After a minute the site is live at `https://<your-username>.github.io/<repository-name>/`.

To use blackcanvas.live instead, add the domain under **Settings → Pages → Custom domain** and point the domain's DNS at GitHub Pages.

## Contact form

The brief form opens the visitor's email app with the brief addressed to info@blackcanvas.live. To have briefs arrive in the inbox automatically, connect the form to a form service or to the website platform used for blackcanvas.live.

## Digital business cards

`card/` holds a mobile business card page for each team member, live at:

- blackcanvas.live/card/moustafa/
- blackcanvas.live/card/yara/
- blackcanvas.live/card/wael/
- blackcanvas.live/card/farha/

Each folder has the page (`index.html`) and the person's contact file (`.vcf`), used by the "Save to contacts" button. The QR code on each page holds the same contact details, so scanning it saves the contact without opening a link. The pages are marked `noindex` so phone numbers stay out of search results. To change someone's details, edit their `index.html` (the `PEOPLE` entry and the QR code) and their `.vcf` file.

## Team portal

`portal/` is a hidden, sign-in-only area at blackcanvas.live/portal/. It isn't linked from the site and is marked `noindex`. After signing in, the team sees an apps screen with **Billing** (quotes and tax invoices), **Crew assignment** (crew on shifts for each event), **Staff assignment** (project staff lists with budgets), **Project management** (event deliveries and tasks) and **Bills** (bills to approve and pay, and client invoices to chase).

- `portal/index.html`: sign in, forgot password, set password (from invite and reset emails), and the apps screen.
- `portal/billing/`: the billing app.
- `portal/projects/`: the project management app for events: an events dashboard, tasks by department on a board or list, timed templates that build each event's delivery checklist from its show dates, a printable production schedule, contacts and suppliers per event, and a timeline across all events. Add `?demo` to its address to try it with sample data kept only in your browser.
- `portal/crew/`: the crew assignment app: a roster of staff, freelancers and agency crew, each with one or more roles and a day rate and a show rate per role, plus certificates and unavailable dates (shifts pay the show rate on show days and the day rate otherwise, or whichever the shift is set to); shifts by role and day for each event (events from Projects appear automatically, and crew-only jobs can be added); booking crew onto shifts with checks for double-booking, short rest between days, unavailable dates and expired certificates; a planner of who is where (1, 2 or 4 weeks, with filters by event, department, role, crew type, city and status, and booked, free, clashing or unavailable crew); crew costs and CSV export per event; printable call sheets and WhatsApp booking messages. Add `?demo` to its address to try it with sample data kept only in your browser.
- `portal/staff/`: the staff assignment app: a database of staff (employees, freelancers, contractors and agency staff) with one or more positions, pay (monthly salary, fixed fee, or a day rate and a show rate per position, with show days paid at the show rate) and leave; a staff list for every project (events from Projects appear automatically, and staff-only projects can be added) made of positions with dates, budget rates and allowances (per diem, accommodation, travel, other), each filled by one or more people; budget vs booked cost per position, department and cost type, with an optional overall staff budget per project; a picker that shows who's free for the dates and blocks anyone already booked; a timeline of who is on which project, with filters (project, department, position, staff type, city, status; booked, free, on leave) and 2 to 12-week views; a "who's free" filter; CSV export and printable staff lists. The database refuses any booking (on hold or confirmed) that would put the same person on two projects on the same day, and the Projects screen shows an overlap check of every booking plus anyone booked during their leave. Monthly salaries are costed pro rata (salary × days ÷ 30). Add `?demo` to its address to try it with sample data kept only in your browser.
- Importing crew or staff: both apps' **Import list** screens take an Excel (.xlsx) or .csv file, or rows pasted from a spreadsheet, and show everyone before saving. Fill-in templates are at `portal/crew/crew-import-template.xlsx` and `portal/staff/staff-import-template.xlsx` (also linked from the Import screens). The .xlsx is read in the browser with no spreadsheet library.
- `portal/bills/`: the bills app: supplier, freelancer, rent and subscription bills with an approve-then-pay flow (portal admins approve or reject; the database won't let a bill be paid before it's approved, or let anyone else change an approved amount), part-payments, supplier invoices and payment receipts stored privately, repeating bills that add the next one when paid, a Today screen of what's overdue, due soon and waiting for approval, and an Owed to us list of unpaid Billing invoices with ready-written email and WhatsApp reminders and a chasing log. The Bills tile on the apps screen shows what needs attention, and a weekday morning digest reads the same from `bills_digest()` in the database. Add `?demo` to its address to try it with sample data kept only in your browser (`?demo=team` shows it as a non-approver).
- `portal/config.js`: the Supabase project URL and publishable key. Both are meant to be public.
- `portal/portal.js`, `portal/brand.js`, `portal/vendor/`: shared sign-in helper, logo artwork and the Supabase library.
- `supabase/setup.sql`: the database tables and access rules.
- `supabase/functions/portal-invite/`: the Edge Function admins use to send invites.
- `supabase/functions/portal-directory/`: the Edge Function that copies the Microsoft 365 directory in, so Team access can suggest people.

When you change `brand.js`, `config.js` or `portal.js`, raise the `?v=` tag on their `<script>` links in both portal pages. GitHub Pages caches files for about 10 minutes, and the new tag makes browsers load the new version straight away.

Sign-in and data run on [Supabase](https://supabase.com). Access is per app: each person has a row in the `portal_access` table listing the apps they may open (`billing`, `crew`, `projects`, `bills`, `staff`) and whether they're an admin. The database enforces it: billing data is only readable and writable by people with the `billing` app, crew data only by people with the `crew` app, project data only by people with the `projects` app, bills data and files only by people with the `bills` app, and staff data only by people with the `staff` app, so hiding a tile isn't the only protection. The code is public in this repository, but the data isn't.

### Set up (once)

1. Create a free project at supabase.com (region: closest to Saudi Arabia, such as Frankfurt or Mumbai).
2. **SQL Editor → New query**: paste `supabase/setup.sql` and run it. Then run the "First admin" lines at the end of that file with your own email, so you can open Team access.
3. **Edge Functions**: deploy `supabase/functions/portal-invite/` with JWT verification turned off (the function checks the caller itself).
4. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up". Only people you invite can then have an account.
5. **Authentication → URL Configuration**: set **Site URL** to `https://blackcanvas.live/portal/` and add `https://blackcanvas.live/portal/**` under **Redirect URLs**.
6. **Project Settings → API Keys**: copy the Project URL and the publishable key into `portal/config.js`. Never use the secret or `service_role` key.

### Connect the Microsoft 365 directory (once)

This lets Team access suggest everyone with a company email. Until it's done, suggestions come from Staff and Crew only. You need to be a Microsoft 365 global admin (or have someone who is do steps 1 to 4).

1. Go to [entra.microsoft.com](https://entra.microsoft.com) → **Applications → App registrations → New registration**. Name it `Black Canvas portal directory`, keep "Accounts in this organizational directory only", leave Redirect URI empty, and click **Register**.
2. On the app's **Overview**, copy the **Application (client) ID** and the **Directory (tenant) ID**.
3. **API permissions → Add a permission → Microsoft Graph → Application permissions**, tick **User.Read.All**, click **Add permissions**, then click **Grant admin consent for …** and confirm. The status should turn green.
4. **Certificates & secrets → New client secret**, choose 24 months, click **Add**, and copy the **Value** straight away (it's only shown once).
5. In Supabase: **Edge Functions → Secrets**, add `MS_TENANT_ID` (the tenant ID), `MS_CLIENT_ID` (the client ID) and `MS_CLIENT_SECRET` (the secret value).
6. Open **Team access** in the portal. The directory is copied in, and the note under the form says suggestions now include Microsoft 365. It refreshes by itself whenever an admin opens Team access (at most every 30 minutes), so new starters appear and leavers drop out.

Only enabled member accounts with a mailbox are copied (no guests or disabled accounts), and only their name, email, job title and department. The client secret expires after the period you chose: before then, make a new one in Entra and update `MS_CLIENT_SECRET`. If something's wrong, Team access shows the reason under the form.

### Add a team member

Admins open **Team access** from the apps screen, enter the person's email, tick their apps and click **Add person**. With "Email them an invite now" ticked, the invite goes out straight away; otherwise use **Send invite** on their row later. They follow the link, enter their name and a password, and see only the apps you ticked. Untick or tick apps at any time; changes apply immediately. **Remove** takes all their access away.

**Permanent, temporary or for a project.** When adding someone (or with **Change** on their row) choose their access:
- **Permanent**: until you remove them. Only permanent people can be admins.
- **Temporary**: for a set time (today only, 3 days, 1 week, 2 weeks, 1 month, 3 months, or until a date you pick). Access stops at midnight after the last day, Riyadh time.
- **For a project**: tied to one event from Project management, ending at midnight after the event's de-rig (or last show day). If the event's dates change, the end moves with them; the person themselves can't change that event's dates. Choose **Everything in their apps** to give the apps you tick for the project's duration, or **Only this project** so they see and change only that event in Projects, Crew and Staff (they can view the crew and staff lists to book people, but not edit them, and Billing, Bills and Admin aren't available).

Each row shows what kind of access the person has and when it ends; ended access shows in red and can be extended with **Change**. People with limited access see a notice on the apps screen and a bar at the top of each app; once it has ended they can still sign in but see no apps. All of this is enforced by the database (`my_access()`, `has_app()` and the access rules in section 14 of `supabase/setup.sql`), not only hidden on screen.

**Finding people as you type.** In the Email or Name box, type part of a name (or email) and pick the person from the list: their work email and name (with job title) fill in for you. Suggestions come from the company's Microsoft 365 directory, the Staff app's database and the Crew roster (people in Staff or Crew need an email saved to appear). People already on the access list are marked "On the team". Only portal admins can search, through `portal_people_search()` in the database; nobody can read the copied directory directly.

Invites are sent by the `portal-invite` Edge Function (`supabase/functions/portal-invite/`), which only works for admins.

Supabase's built-in email sender only reaches members of your Supabase organization and allows a few emails an hour. To invite anyone reliably, set up your own sender under **Authentication → Emails → SMTP Settings** (for example your Microsoft 365 mailbox or a service such as Resend).

## Email signature

`email/` holds the company email signature: `logo.gif` (the animated logo, 534×220, shown at 180×74), `logo.png` (a still version) and `signature.html`, the HTML for a Microsoft 365 "Apply disclaimers" mail-flow rule. The `%%DisplayName%%`, `%%Title%%` and `%%MobilePhone%%` tokens fill in from each sender's Microsoft 365 profile.
