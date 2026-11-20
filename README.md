# Cloudenza Notes

A small, real, English-language editorial website about web fundamentals: DNS, TLS, HTTP caching and response diagnostics. Static files only; no tracking, analytics, fake uptime figures or invented services.

## Files

- `site/index.html` — editorial landing page and guide directory
- `site/articles/dns.html` — DNS resolution and records
- `site/articles/https.html` — TLS, certificates, SNI and ALPN
- `site/articles/caching.html` — cache freshness, validation and shared caches
- `site/articles/http.html` — HTTP methods, responses and diagnostics
- `site/assets/article.css` and `site/assets/article.js` — responsive article layouts, theme, table of contents, progress indicator and copy buttons
- `site/assets/style.css` — responsive styles
- `site/assets/app.js` — page search, theme and origin-response check
- `deploy.sh` — inspect the Selfsteal layout, install site files and optionally activate a separate nginx TLS virtual host after you supply a valid certificate
- `NGINX-EXAMPLE.md` — an example of a vhost, to adapt after inspecting the node

## Editorial scope

Four dedicated article pages, each around 750–900 words, combine definitions, practical examples, interactive reading navigation and links to primary RFCs. They are intentionally not presented as original research, laboratory measurements or commercial service reports. The browser check reports a single observed request, not ongoing uptime.

## Updating existing deployed files

For an existing deployment with a configured nginx virtual host:

```sh
cd /root/temp
git pull --ff-only
sudo sh deploy.sh install
```

Then test the new pages over HTTPS using the existing site hostname: `/articles/dns.html`, `/articles/https.html`, `/articles/caching.html`, `/articles/http.html`.

Only static files are updated; existing nginx, TLS, DNS and Reality configurations remain unchanged. The installer backs up the prior site directory before replacing its files.

## Local preview

```sh
cd site
python3 -m http.server 8080 --bind 127.0.0.1
```

Open http://127.0.0.1:8080.

## Deployment on an existing Selfsteal node

```sh
git clone https://github.com/Daniil-GR/temp.git
cd temp
sudo sh deploy.sh inspect
sudo sh deploy.sh install
sudo sh deploy.sh prepare-http --domain YOUR_NEW_SUBDOMAIN
```

**Install** is intentionally non-disruptive: it copies to a separate `cloudenza-notes` directory under the existing mounted web root without changing any services or configurations. **Prepare-http** is optional: it creates an isolated port-80 nginx vhost and enables standard ACME HTTP-01 webroot verification after the DNS A record has been configured. **Activate** is optional: after a matching certificate has been issued and installed inside the current nginx SSL volume, it validates and adds a separate nginx TLS vhost, then runs `nginx -t` and reloads nginx. It does not change Docker Compose, DNS, network bindings or Reality routing.

**Important:** Installing site files is not equivalent to activating a new HTTPS hostname. Before the new domain works on a secondary IPv4, the operator must configure the DNS A record, a valid certificate, the nginx virtual host, and the existing Selfsteal/Reality SNI/port routing as appropriate. See `NGINX-EXAMPLE.md`. Do not reuse a certificate for a hostname it does not cover.

Neither domain names nor server IP addresses are stored in this public repository.
