# Atlas editorial redesign

Atlas is a buildless English-language journal about geography, cartography and Earth science. Its 16 HTML pages are ready for static hosting.

## Local preview

```sh
python3 -m http.server 8080 --directory atlas/site
```

Open `http://localhost:8080`. There are no package installs, build steps, API keys or runtime CDN dependencies.

## Structure and editing

- `site/index.html`: editorial homepage, photographic story selection and interactive globe.
- `site/explore.html`: searchable collection, topic filters and saved stories.
- `site/geography.html`, `cartography.html`, `earth-science.html`: themed collections.
- `site/articles/`: eight explainers with references, image captions, contents navigation and reading progress.
- `site/assets/css/styles.css`: responsive design, Georgia/system typography and natural colours.
- `site/assets/js/app.js`: search, mobile menu, local reading list and article tools.
- `site/assets/js/globe.js`: dependency-free WebGL sphere, local NASA texture, pointer/keyboard rotation, zoom and pause. Respects reduced motion, stops rendering outside the viewport, falls back to a local Earth image without WebGL. Not live satellite imagery.
- `site/assets/photos/credits.json`: attribution, original source and reuse licence for every photograph/map; also displayed on `sources.html`.
- `content.json`: original editorial text and metadata, retained from the earlier site.
- `tools/render.py`: optional Python-standard-library page generator; rerun after editing content or image credits.
- `tools/check_site.py`: local links, anchor, image-alt and credit checks.

```sh
python3 atlas/tools/render.py
python3 atlas/tools/check_site.py
node --check atlas/site/assets/js/app.js
node --check atlas/site/assets/js/globe.js
```

Images are served locally as WebP. Their creators and licences are credited visibly; responsive crops and format conversion are disclosed. The globe uses a NASA Blue Marble mosaic. No tracking or external fonts. Saved stories use browser localStorage only and degrade gracefully when storage is unavailable.

The existing deployment script and infrastructure configuration are unchanged. Original deployment instructions follow.

---

# Atlas — Earth & Place

Static, English-language educational website for **atlas.dateihafen.xyz**.

## Contents

- `atlas/site/`: 30 publicly served files: 16 HTML pages including eight articles, local CSS/JavaScript, original SVG illustrations, sitemap and robots.txt.
- `deploy-atlas.sh`: separate shell installer for an existing nginx-selfsteal Docker HTML mount.

The existing root `site/`, `deploy.sh`, `README.md` and `NGINX-EXAMPLE.md` are **not modified**.

## Non-disruptive installation

On the VPS that already runs `nginx-selfsteal`:

```sh
cd /root/temp
git pull --ff-only
sudo sh deploy-atlas.sh inspect --domain atlas.dateihafen.xyz
sudo sh deploy-atlas.sh stage
```

`stage` discovers the Docker host bind mount for `/var/www/html` and stages Atlas into `/var/www/html/atlas-earth` (inside the container), leaving the active site and services untouched. To use a dedicated existing nginx vhost, point that vhost's `root` to `/var/www/html/atlas-earth` after confirming your running configuration.

## Explicitly replace a default root placeholder

**Only if** `nginx -T` confirms that the site you intend to replace uses `/var/www/html` directly, and that you are prepared for all domains sharing that webroot to display Atlas:

```sh
sudo sh deploy-atlas.sh publish --confirm-root-replacement
```

The script makes a timestamped backup outside the served webroot of the files that it overwrites, then writes the new HTML/static assets and installs `index.html` last. Files unrelated to Atlas remain untouched. To roll back the most recent publish:

```sh
sudo sh deploy-atlas.sh rollback --confirm-root-replacement
```

Use `--webroot /absolute/host/path` only when you know the right host-side HTML directory; otherwise mount discovery is automatic. Other commands: `help` and `inspect`.

**Important:** The installer never edits or reloads nginx, TLS certificates, Certbot, DNS, Reality/SNI, rw-core, Docker Compose, or ports 80/443. For a new HTTPS hostname you must separately configure the correct existing vhost, certificate, and ingress routing. Prefer dedicated vhost roots on shared nodes.
