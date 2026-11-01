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

`portal/` is a hidden, sign-in-only area at blackcanvasglobal.com/portal/. It isn't linked from the site and is marked `noindex`. After signing in, the team sees an apps screen: **Billing** (quotes and tax invoices) is live, and **Crew assignment** and **Project management** are placeholders for later.

- `portal/index.html`: sign in, forgot password, set password (from invite and reset emails), and the apps screen.
- `portal/billing/`: the billing app.
- `portal/config.js`: the Supabase project URL and publishable key. Both are meant to be public.
- `portal/portal.js`, `portal/brand.js`, `portal/vendor/`: shared sign-in helper, logo artwork and the Supabase library.
- `supabase/setup.sql`: the database table and access rules.

When you change `brand.js`, `config.js` or `portal.js`, raise the `?v=` tag on their `<script>` links in both portal pages. GitHub Pages caches files for about 10 minutes, and the new tag makes browsers load the new version straight away.

Sign-in and data run on [Supabase](https://supabase.com). The access rules only let signed-in team members read or change data: any `@blackcanvasglobal.com` account, plus emails listed in the `portal_members` table. The code is public in this repository, but the data isn't.

### Set up (once)

1. Create a free project at supabase.com (region: closest to Saudi Arabia, such as Frankfurt or Mumbai).
2. **SQL Editor → New query**: paste `supabase/setup.sql` and run it.
3. **Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up". Only people you invite can then have an account.
4. **Authentication → URL Configuration**: set **Site URL** to `https://blackcanvasglobal.com/portal/` and add `https://blackcanvasglobal.com/portal/**` under **Redirect URLs**.
5. **Project Settings → API Keys**: copy the Project URL and the publishable key into `portal/config.js`. Never use the secret or `service_role` key.

### Add a team member

**Authentication → Users → Add user → Send invitation** with their email. They get an email, follow the link, enter their name and a password, and land on the apps screen. The portal shows that name instead of their email; anyone can change theirs by clicking it at the top right of the apps screen. If their email isn't `@blackcanvasglobal.com`, also add it to the `portal_members` table (**Table Editor → portal_members → Insert row**).

To remove someone, delete them under **Authentication → Users**.

## Email signature

`email/` holds the company email signature: `logo.gif` (the animated logo, 534×220, shown at 180×74), `logo.png` (a still version) and `signature.html`, the HTML for a Microsoft 365 "Apply disclaimers" mail-flow rule. The `%%DisplayName%%`, `%%Title%%` and `%%MobilePhone%%` tokens fill in from each sender's Microsoft 365 profile.
