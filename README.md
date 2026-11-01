# Black Canvas website

The website for Black Canvas, a full-service event management company across Saudi Arabia and the Globe.

It is a single static page: `index.html` plus the project photos in `img/`. There is no build step.

## Publish with GitHub Pages

1. In this repository, open **Settings → Pages**.
2. Under **Build and deployment**, set **Source** to *Deploy from a branch*, choose the `main` branch and the `/ (root)` folder, and save.
3. After a minute the site is live at `https://<your-username>.github.io/<repository-name>/`.

To use blackcanvasglobal.com instead, add the domain under **Settings → Pages → Custom domain** and point the domain's DNS at GitHub Pages.

## Contact form

The brief form opens the visitor's email app with the brief addressed to info@blackcanvasglobal.com. To have briefs arrive in the inbox automatically, connect the form to a form service or to the website platform used for blackcanvasglobal.com.

## Digital business cards

`card/` holds a mobile business card page for each team member, live at:

- blackcanvasglobal.com/card/moustafa/
- blackcanvasglobal.com/card/yara/
- blackcanvasglobal.com/card/wael/
- blackcanvasglobal.com/card/farha/

Each folder has the page (`index.html`) and the person's contact file (`.vcf`), used by the "Save to contacts" button. The QR code on each page holds the same contact details, so scanning it saves the contact without opening a link. The pages are marked `noindex` so phone numbers stay out of search results. To change someone's details, edit their `index.html` (the `PEOPLE` entry and the QR code) and their `.vcf` file.

## Team portal

`portal/` is a hidden, sign-in-only area at blackcanvasglobal.com/portal/. It isn't linked from the site and is marked `noindex`. After signing in, the team sees an apps screen: **Billing** (quotes and tax invoices) and **Project management** (event deliveries and tasks) are live, and **Crew assignment** is a placeholder for later.

- `portal/index.html`: sign in, forgot password, set password (from invite and reset emails), and the apps screen.
- `portal/billing/`: the billing app.
- `portal/projects/`: the project management app for events: an events dashboard, tasks by department on a board or list, timed templates that build each event's delivery checklist from its show dates, a printable production schedule, contacts and suppliers per event, and a timeline across all events. Add `?demo` to its address to try it with sample data kept only in your browser.
- `portal/config.js`: the Supabase project URL and publishable key. Both are meant to be public.
- `portal/portal.js`, `portal/brand.js`, `portal/vendor/`: shared sign-in helper, logo artwork and the Supabase library.
- `supabase/setup.sql`: the database tables and access rules.
- `supabase/functions/portal-invite/`: the Edge Function admins use to send invites.

When you change `brand.js`, `config.js` or `portal.js`, raise the `?v=` tag on their `<script>` links in both portal pages. GitHub Pages caches files for about 10 minutes, and the new tag makes browsers load the new version straight away.

Sign-in and data run on [Supabase](https://supabase.com). Access is per app: each person has a row in the `portal_access` table listing the apps they may open (`billing`, `crew`, `projects`) and whether they're an admin. The database enforces it: billing data is only readable and writable by people with the `billing` app, and project data only by people with the `projects` app, so hiding a tile isn't the only protection. The code is public in this repository, but the data isn't.

### Set up (once)

1. Create a free project at supabase.com (region: closest to Saudi Arabia, such as Frankfurt or Mumbai).
2. **SQL Editor → New query**: paste `supabase/setup.sql` and run it. Then run the "First admin" lines at the end of that file with your own email, so you can open Team access.
3. **Edge Functions**: deploy `supabase/functions/portal-invite/` with JWT verification turned off (the function checks the caller itself).
4. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up". Only people you invite can then have an account.
5. **Authentication → URL Configuration**: set **Site URL** to `https://blackcanvasglobal.com/portal/` and add `https://blackcanvasglobal.com/portal/**` under **Redirect URLs**.
6. **Project Settings → API Keys**: copy the Project URL and the publishable key into `portal/config.js`. Never use the secret or `service_role` key.

### Add a team member

Admins open **Team access** from the apps screen, enter the person's email, tick their apps and click **Add person**. With "Email them an invite now" ticked, the invite goes out straight away; otherwise use **Send invite** on their row later. They follow the link, enter their name and a password, and see only the apps you ticked. Untick or tick apps at any time; changes apply immediately. **Remove** takes all their access away.

Invites are sent by the `portal-invite` Edge Function (`supabase/functions/portal-invite/`), which only works for admins.

Supabase's built-in email sender only reaches members of your Supabase organization and allows a few emails an hour. To invite anyone reliably, set up your own sender under **Authentication → Emails → SMTP Settings** (for example your Microsoft 365 mailbox or a service such as Resend).

## Email signature

`email/` holds the company email signature: `logo.gif` (the animated logo, 534×220, shown at 180×74), `logo.png` (a still version) and `signature.html`, the HTML for a Microsoft 365 "Apply disclaimers" mail-flow rule. The `%%DisplayName%%`, `%%Title%%` and `%%MobilePhone%%` tokens fill in from each sender's Microsoft 365 profile.
