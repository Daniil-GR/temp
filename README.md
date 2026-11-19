# Cloudenza Notes

A small, real, English-language informational website about web fundamentals: DNS, TLS and HTTP caching. Static files only; no tracking, analytics, fake uptime figures or invented services.

## Files

- `site/index.html` — content and layout
- `site/assets/style.css` — responsive styles
- `site/assets/app.js` — page search, theme and origin-response check
- `deploy.sh` — inspect the current Docker Selfsteal layout and install **only the site's files** into a new directory in its existing web root
- `NGINX-EXAMPLE.md` — an example of a vhost, to adapt after inspecting the node

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
```

Installation is intentionally non-disruptive. It copies to a separate `cloudenza-notes` directory under the web root that the existing nginx container already mounts. It never changes Docker Compose, TLS, DNS, port bindings, Reality, routing, container services or nginx config.

**Important:** Installing site files is not equivalent to activating a new HTTPS hostname. Before the new domain works on a secondary IPv4, the operator must configure the DNS A record, a valid certificate, an nginx virtual host, and the existing Selfsteal/Reality SNI/port routing as appropriate. See `NGINX-EXAMPLE.md`. Do not reuse a certificate for a hostname it does not cover.

Neither domain names nor server IP addresses are stored in this public repository.
