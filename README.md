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

Each folder has the page (`index.html`) and the person's contact file (`.vcf`), used by the "Save to contacts" button. The QR code on each page holds the same contact details, so scanning it saves the contact without opening a link. The pages are marked `noindex` so phone numbers stay out of search results. To change someone's details, edit their `index.html` (the `PEOPLE` entry and the QR code) and their `.vcf` file.

## Email signature

`email/` holds the company email signature: `logo.gif` (the animated logo, 534×220, shown at 180×74), `logo.png` (a still version) and `signature.html`, the HTML for a Microsoft 365 "Apply disclaimers" mail-flow rule. The `%%DisplayName%%`, `%%Title%%` and `%%MobilePhone%%` tokens fill in from each sender's Microsoft 365 profile.
